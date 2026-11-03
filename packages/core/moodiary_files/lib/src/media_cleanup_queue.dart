import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:path/path.dart' as p;

import 'media_guard.dart';
import 'media_type.dart';

/// Durable requests to reconsider specific media after their references change.
///
/// Enqueue before committing the reference change. Replaying a request is safe
/// only when the consumer rechecks all references under the media guard.
class MediaCleanupQueue {
  MediaCleanupQueue({String? supportPath})
    : _directory = Directory(
        p.join(
          supportPath ?? PlatformService.get().applicationSupportPath,
          '.media-cleanup-queue',
        ),
      );

  final Directory _directory;

  Future<void> enqueue(Iterable<MediaKey> candidates) async {
    final items = [
      for (final key in candidates) {'type': key.type.value, 'name': key.name},
    ];
    if (items.isEmpty) return;
    await _directory.create(recursive: true);
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temp = File(p.join(_directory.path, '$id.tmp'));
    final target = p.join(_directory.path, '$id.json');
    await temp.create(exclusive: true);
    try {
      await temp.writeAsString(jsonEncode(items), flush: true);
      await temp.rename(target);
    } catch (_) {
      try {
        await temp.delete();
      } on PathNotFoundException {
        // The rename may already have succeeded.
      }
      rethrow;
    }
  }

  /// Requests may also be read by another process; a consumer must tolerate
  /// replay and call [MediaCleanupRequest.complete] only after safe handling.
  Future<List<MediaCleanupRequest>> pending({
    void Function(Object error, StackTrace stackTrace)? onInvalid,
  }) async {
    final requests = <MediaCleanupRequest>[];
    try {
      await for (final entity in _directory.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final parsed = jsonDecode(await entity.readAsString());
          if (parsed is! List) {
            throw const FormatException('Invalid cleanup queue');
          }
          final candidates = <MediaKey>[];
          for (final item in parsed) {
            if (item is! Map ||
                item['type'] is! String ||
                item['name'] is! String) {
              throw const FormatException('Invalid cleanup request');
            }
            final type = MediaType.values.where((t) => t.value == item['type']);
            if (type.length != 1) {
              throw const FormatException('Invalid media type');
            }
            candidates.add(MediaKey(type.single, item['name'] as String));
          }
          requests.add(
            MediaCleanupRequest._(entity, List.unmodifiable(candidates)),
          );
        } on PathNotFoundException {
          // Another process completed the same request.
        } catch (error, stackTrace) {
          if (onInvalid == null) rethrow;
          onInvalid(error, stackTrace);
        }
      }
    } on PathNotFoundException {
      // No requests have been enqueued yet.
    }
    return requests;
  }
}

class MediaCleanupRequest {
  MediaCleanupRequest._(this._file, this.candidates);

  final File _file;
  final List<MediaKey> candidates;

  Future<void> complete() async {
    try {
      await _file.delete();
    } on PathNotFoundException {
      // Another process already completed it.
    }
  }
}
