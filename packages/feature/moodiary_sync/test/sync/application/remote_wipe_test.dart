import 'dart:convert';
import 'dart:typed_data';

// FRB 的 initMock 接口需要未从公共入口导出的生成 API 类型。
// ignore: implementation_imports
import 'package:fast_crypto/src/rust/frb_generated.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_sync/src/application/remote_wipe.dart';
import 'package:moodiary_sync/src/data/codec.dart';
import 'package:moodiary_sync/src/data/incremental_engine.dart';
import 'package:moodiary_sync/src/data/model/manifest.dart';
import 'package:moodiary_sync/src/data/sync.dart';
import 'package:moodiary_sync/src/data/sync_key_manager.dart';
import 'package:moodiary_sync/src/data/sync_keyfile.dart';

import '../sync_test_harness.dart';

// 只替换原生密码学边界，让密钥轮换流程在没有 Rust 动态库的测试环境也能执行。
// 密文绑定完整密钥，错误口令 / DEK 必须失败；AES 本身由 Rust 测试覆盖。
final class _FakeCryptoApi implements FastCryptoLibApi {
  final _derived = <String, Uint8List>{};
  final _sealed = <String, ({List<int> key, List<int> data})>{};

  @override
  Future<Uint8List> crateApiCryptoAesDeriveKey({
    required String salt,
    required String userKey,
    int? mCostKib,
    int? tCost,
    int? pCost,
  }) async => _derived.putIfAbsent(
    jsonEncode([salt, userKey, mCostKib, tCost, pCost]),
    () => Uint8List.fromList(List.filled(32, _derived.length + 1)),
  );

  @override
  Future<Uint8List> crateApiCryptoAesEncrypt({
    required List<int> key,
    required List<int> data,
  }) async {
    final token = 'cipher-${_sealed.length}';
    _sealed[token] = (key: [...key], data: [...data]);
    return utf8.encode(token);
  }

  @override
  Future<Uint8List> crateApiCryptoAesDecrypt({
    required List<int> key,
    required List<int> encryptedData,
  }) async {
    final sealed = _sealed[utf8.decode(encryptedData)];
    if (sealed == null || !listEquals(sealed.key, key)) {
      throw StateError('auth tag mismatch');
    }
    return Uint8List.fromList(sealed.data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used here');
}

void main() {
  late FakeRemoteBackend backend;
  late FakeDiaryStore local;
  late FakeMediaFiles media;
  late List<int> oldDek;
  late SyncKeyfile oldKeyfile;

  IncrementalSyncEngine engine(
    FakeRemoteBackend remote,
    FakeDiaryStore diaries,
    FakeMediaFiles files,
  ) => IncrementalSyncEngine(
    remote,
    diaryStore: diaries,
    categoryStore: FakeCategoryStore(),
    placeStore: FakePlaceStore(),
    mediaInfoStore: FakeMediaInfoStore(),
    tombstoneStore: diaries.tombstones,
    mediaFiles: files,
  );

  setUpAll(() => FastCryptoLib.initMock(api: _FakeCryptoApi()));
  tearDownAll(FastCryptoLib.dispose);

  setUp(() async {
    await setUpSyncEnv();
    backend = FakeRemoteBackend();
    await getIt.unregister<IRemoteSyncBackend>(instanceName: 'webdav');
    getIt.registerSingleton<IRemoteSyncBackend>(
      backend,
      instanceName: 'webdav',
    );
    local = FakeDiaryStore([
      buildDiary(
        id: 'local',
        modifiedMs: 100,
        title: '保留的日记',
        content: '本机正文',
        images: ['photo.jpg'],
      ),
    ]);
    media = FakeMediaFiles()..put('image', 'photo.jpg', [1, 2, 3, 4]);
    oldDek = SyncKeyManager.generateDek();
    oldKeyfile = await SyncKeyManager.wrapDek(
      dek: oldDek,
      passphrase: 'old-password',
    );
    await SyncKeyManager.storeDek(oldDek);
    SyncKeyManager.cacheKeyfile(oldKeyfile);
    await SyncKeyManager.writeRemoteKeyfile(backend, oldKeyfile);
    final seeded = await engine(backend, local, media).push();
    expect(seeded.failed, 0);
    expect(seeded.diaryCount, 1);
  });
  tearDown(tearDownSyncEnv);

  test('重置生成新 DEK，保留本机日记与媒体，其他设备可用新口令恢复重传内容', () async {
    final diariesBefore = Map.of(local.diaries);
    final mediaBefore = Map.of(media.files);

    final report = await RemoteWipe.run(
      backend,
      passphrase: 'new-password',
      configured: {'webdav'},
    );

    expect(report.failed, 0);
    expect(backend.objects.keys, {SyncKeys.keysPath, SyncKeys.manifestPath});
    expect(local.diaries, diariesBefore);
    expect(local.tombstones.rows, isEmpty);
    expect(media.files, mediaBefore);
    expect(SyncKeyManager.hasForceMediaReupload('webdav'), isTrue);

    final newDek = (await SyncKeyManager.loadDek())!;
    expect(newDek, isNot(orderedEquals(oldDek)));
    final emptyManifest = backend.objects[SyncKeys.manifestPath]!;
    expect(SyncCipher.isCipherText(emptyManifest), isTrue);
    expect(
      SyncManifest.fromJson(
        await SyncCipher.withKey(newDek).decode(emptyManifest),
      ).entries,
      isEmpty,
    );
    await expectLater(
      SyncCipher.withKey(oldDek).decode(emptyManifest),
      throwsA(isA<SyncException>()),
    );

    final synced = await engine(backend, local, media).sync();
    expect(synced.failed, 0);
    expect(synced.pushed.diaries, 1);
    expect(local.diaries, diariesBefore);
    expect(media.files, mediaBefore);
    expect(SyncKeyManager.hasForceMediaReupload('webdav'), isFalse);

    // 换成没有任何本机密钥缓存的新客户端，仅从云端信封和新口令解锁。
    await SyncKeyManager.clearDek();
    MoodiaryKVs.syncDeviceId.set('second-device');
    expect(await SyncKeyManager.loadDek(), isNull);
    expect(SyncKeyManager.cachedKeyfile(), isNull);
    expect(await SyncKeyManager.probeRemote(backend), RemoteKeyStatus.locked);
    final keyfile = (await SyncKeyManager.readRemoteKeyfile(backend))!;
    await expectLater(
      SyncKeyManager.unwrapDek(keyfile: keyfile, passphrase: 'old-password'),
      throwsA(isA<SyncException>()),
    );
    final unlocked = await SyncKeyManager.unwrapDek(
      keyfile: keyfile,
      passphrase: 'new-password',
    );
    expect(unlocked, orderedEquals(newDek));
    await SyncKeyManager.installKey(
      dek: unlocked,
      keyfile: keyfile,
      backendId: 'webdav',
      configured: {'webdav'},
    );
    final received = FakeDiaryStore();
    final receivedMedia = FakeMediaFiles();
    final pulled = await engine(backend, received, receivedMedia).pull();
    expect(pulled.failed, 0);
    expect(received.diaries, diariesBefore);
    expect(receivedMedia.files, mediaBefore);
  });

  test('重置只清空当前后端，待补传密钥不能覆盖另一个后端的旧密文与信封', () async {
    final other = FakeRemoteBackend(
      backendId: 's3',
      objects: {
        for (final entry in backend.objects.entries)
          entry.key: Uint8List.fromList(entry.value),
      },
    );
    await getIt.unregister<IRemoteSyncBackend>(instanceName: 's3');
    getIt.registerSingleton<IRemoteSyncBackend>(other, instanceName: 's3');
    final otherBefore = Map.of(other.objects);

    await RemoteWipe.run(
      backend,
      passphrase: 'new-password',
      configured: {'webdav', 's3'},
    );

    expect(other.ops, isEmpty);
    expect(other.objects, otherBefore);
    expect(SyncKeyManager.pendingUploadBackends(), ['s3']);
    await expectLater(
      SyncKeyManager.uploadPendingKeyfile(other),
      throwsA(isA<SyncKeyConflictException>()),
    );
    expect(SyncKeyManager.hasKeyConflict('s3'), isTrue);
    expect(other.objects, otherBefore);
    expect(other.opCount('write'), 0);
    expect(other.opCount('delete'), 0);
    final oldManifest = await SyncCipher.withKey(oldDek)
        .decode(other.objects[SyncKeys.manifestPath]!);
    expect(
      SyncManifest.fromJson(oldManifest).entries.keys,
      contains('d:local'),
    );
  });

  test('新信封已写入但加密清单补种失败时保留本机旧密钥，重试可完成重建', () async {
    final diariesBefore = Map.of(local.diaries);
    final mediaBefore = Map.of(media.files);
    backend.beforeOp = (op, key) {
      if (op == 'write' && key == SyncKeys.manifestPath) {
        throw const SyncException('offline');
      }
    };

    await expectLater(
      RemoteWipe.run(backend, passphrase: 'new-password'),
      throwsA(isA<SyncException>()),
    );

    expect(backend.hasObject(SyncKeys.keysPath), isTrue);
    expect(backend.hasObject(SyncKeys.manifestPath), isFalse);
    expect(backend.hasObject(SyncKeys.lockPath), isFalse);
    expect(await SyncKeyManager.loadDek(), orderedEquals(oldDek));
    expect(SyncKeyManager.cachedKeyfile()!.toJson(), oldKeyfile.toJson());
    expect(SyncKeyManager.hasKeyConflict('webdav'), isTrue);
    expect(local.diaries, diariesBefore);
    expect(media.files, mediaBefore);

    backend.beforeOp = null;
    final retried = await RemoteWipe.run(
      backend,
      passphrase: 'new-password',
      configured: {'webdav'},
    );
    expect(retried.failed, 0);
    expect(SyncKeyManager.hasKeyConflict('webdav'), isFalse);
    expect(await SyncKeyManager.loadDek(), isNot(orderedEquals(oldDek)));
    final keyfile = (await SyncKeyManager.readRemoteKeyfile(backend))!;
    final recovered = await SyncKeyManager.unwrapDek(
      keyfile: keyfile,
      passphrase: 'new-password',
    );
    expect(recovered, orderedEquals((await SyncKeyManager.loadDek())!));
    expect(
      SyncManifest.fromJson(
        await SyncCipher.withKey(recovered)
            .decode(backend.objects[SyncKeys.manifestPath]!),
      ).entries,
      isEmpty,
    );
  });
}
