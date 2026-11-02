import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_ml/src/hf_hub.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

void main() {
  setUp(() {
    getIt.registerSingleton<IKVStorage>(MemoryKVStorage());
  });

  tearDown(() async => getIt.reset());

  test('retains the legacy mirror default and preference', () {
    expect(HfHub.endpoint, HfHub.mirrorEndpoint);
    MoodiaryKVs.modelDownloadMirror.set(false);
    expect(HfHub.endpoint, HfHub.officialEndpoint);
    MoodiaryKVs.modelDownloadMirror.set(true);
    expect(HfHub.endpoint, HfHub.mirrorEndpoint);
  });

  test('an explicit endpoint overrides the legacy preference', () {
    MoodiaryKVs.modelDownloadMirror.set(false);
    MoodiaryKVs.modelDownloadEndpoint.set(' mirror.example/base/ ');
    expect(HfHub.endpoint, 'https://mirror.example/base');
    expect(
      HfHub.resolve('example/model/resolve/main/tokenizer.json'),
      'https://mirror.example/base/example/model/resolve/main/tokenizer.json',
    );
  });

  test('rejects invalid or ambiguous base addresses', () {
    for (final value in [
      '',
      'ftp://example.com',
      'https://',
      'https://user:password@example.com',
      'https://example.com/?token=x',
      'https://example.com/#fragment',
      'https://example .com',
    ]) {
      expect(
        () => HfHub.normalize(value),
        throwsFormatException,
        reason: value,
      );
    }
    expect(HfHub.normalize('http://localhost:8080/'), 'http://localhost:8080');
  });
}
