import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show RootIsolateToken;

import 'package:crypto/crypto.dart';
import 'package:moodiary_platform/moodiary_platform.dart';
import 'package:path/path.dart' as p;

import 'media_type.dart';

/// An original media file or its thumbnail.
class MediaKey {
  const MediaKey(this.type, this.name);

  final MediaType type;
  final String name;
}

/// A shared claim on one or more media files.
///
/// Keep the lease until the unsaved use has ended or the database reference
/// has been committed. Always release it, including on cancellation.
class MediaLease {
  MediaLease._(this._release);

  final Future<void> Function() _release;
  bool _released = false;

  Future<void> release() async {
    MediaGuard._checkRootIsolate();
    if (_released) return;
    _released = true;
    await _release();
  }
}

/// Coordinates media usage and deletion across app processes.
///
/// Every writer must acquire a shared lease before creating or reusing a name
/// and retain it until its new reference is committed or discarded. A deleter
/// must acquire an exclusive lease and check all references inside its action.
/// The lock is deliberately global: a media user defers all cleanup, which
/// covers filesystem aliases and avoids platform-specific filename matching.
/// File locks are advisory: older app versions and uncoordinated writers do not
/// honour them. Never remove the lock directory, even when resetting media.
///
/// On POSIX file locks are process-wide, not isolate-wide. Calls are therefore
/// restricted to the Flutter root isolate, where all instances share the same
/// in-process lock table. Background work must be coordinated by its caller.
class MediaGuard {
  MediaGuard({String? supportPath})
    : _root = p.normalize(
        p.absolute(supportPath ?? PlatformService.get().applicationSupportPath),
      );

  final String _root;
  late final Future<String> _resolvedRoot = Directory(_root)
      .resolveSymbolicLinks()
      .then(p.normalize);
  static final Map<String, _Entry> _entries = {};

  /// Claims a single file until [MediaLease.release] completes.
  Future<MediaLease> acquire(MediaType type, String name) =>
      acquireAll([MediaKey(type, name)]);

  /// Claims names in stable order to avoid deadlock. Partial claims are
  /// released when acquisition fails.
  Future<MediaLease> acquireAll(Iterable<MediaKey> keys) async {
    _checkRootIsolate();
    final root = await _resolvedRoot;
    // One lock is sufficient even for a multi-file operation. Materialize the
    // iterable once so an empty set does not needlessly hold up all cleanup.
    final ids = keys.isEmpty ? <String>[] : [_id(root)];
    final releases = <Future<void> Function()>[];
    try {
      for (final id in ids) {
        releases.add(await _acquire(root, id));
      }
    } catch (_) {
      for (final release in releases.reversed) {
        await release();
      }
      rethrow;
    }
    return MediaLease._(() async {
      Object? error;
      StackTrace? trace;
      for (final release in releases.reversed) {
        try {
          await release();
        } catch (e, s) {
          error ??= e;
          trace ??= s;
        }
      }
      if (error != null) Error.throwWithStackTrace(error, trace!);
    });
  }

  /// Runs [action] while no coordinated user holds this file. Returns false
  /// if another lease owns it; filesystem and action failures are propagated.
  Future<bool> tryExclusive(
    MediaType type,
    String name,
    Future<void> Function() action,
  ) async {
    _checkRootIsolate();
    if (!supportsDeletion(MediaKey(type, name))) return false;
    final root = await _resolvedRoot;
    final id = _id(root);
    if (_entries.containsKey(id)) return false;
    final entry = _Exclusive();
    _entries[id] = entry;
    RandomAccessFile? file;
    var locked = false;
    try {
      file = await _open(root, id);
      try {
        await file.lock(FileLock.exclusive);
        locked = true;
      } on FileSystemException catch (e) {
        if (_isContention(e)) return false;
        rethrow;
      }
      await action();
      return true;
    } finally {
      try {
        if (locked) await file!.unlock();
      } finally {
        try {
          await file?.close();
        } finally {
          _entries.remove(id);
          entry.done.complete();
        }
      }
    }
  }

  Future<Future<void> Function()> _acquire(String root, String id) async {
    while (true) {
      final existing = _entries[id];
      if (existing is _Exclusive) {
        await existing.done.future;
        continue;
      }
      if (existing is _Shared && existing.closing) {
        await existing.done.future;
        continue;
      }
      final shared = existing is _Shared ? existing : _Shared();
      if (existing == null) {
        _entries[id] = shared;
        shared.ready = _openShared(root, id);
      }
      shared.references++;
      try {
        await shared.ready;
      } catch (_) {
        shared.references--;
        if (shared.references == 0) {
          _entries.remove(id);
          shared.done.complete();
        }
        rethrow;
      }
      return () => _release(id, shared);
    }
  }

  Future<RandomAccessFile> _openShared(String root, String id) async {
    final file = await _open(root, id);
    try {
      await file.lock(FileLock.blockingShared);
      return file;
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<void> _release(String id, _Shared entry) async {
    entry.references--;
    if (entry.references != 0) return;
    entry.closing = true;
    final file = await entry.ready;
    try {
      await file.unlock();
    } finally {
      try {
        await file.close();
      } finally {
        _entries.remove(id);
        entry.done.complete();
      }
    }
  }

  Future<RandomAccessFile> _open(String root, String id) async {
    final digest = sha256.convert(utf8.encode(id)).toString();
    final dir = Directory(p.join(root, '.media-locks'));
    await dir.create(recursive: true);
    // Append creates the lock file without truncating a file opened by another
    // process. Lock files must remain stable for the lifetime of the app data.
    return File(p.join(dir.path, '$digest.lock')).open(mode: FileMode.append);
  }

  /// Whether this individual name is unambiguous enough for deletion.
  /// Callers must also reject cleanup when any persisted references have names
  /// whose filesystem aliases cannot be established safely.
  static bool supportsDeletion(MediaKey key) {
    final name = key.name;
    if (name.isEmpty || name.endsWith('.')) return false;
    // Names outside the app's simple ASCII alphabet can be aliases on some
    // filesystems (Unicode normalization, NTFS streams and short names).
    if (name.codeUnits.any((code) {
      final letter = (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
      final digit = code >= 48 && code <= 57;
      return !letter && !digit && code != 45 && code != 46 && code != 95;
    })) {
      return false;
    }
    final stem = name.split('.').first.toUpperCase();
    if (const {'CON', 'PRN', 'AUX', 'NUL'}.contains(stem)) return false;
    if (RegExp(r'^(COM|LPT)[1-9]$').hasMatch(stem)) return false;
    return true;
  }

  String _id(String root) {
    final normalized = p.normalize(root);
    final identity = Platform.isWindows ? normalized.toLowerCase() : normalized;
    return '$identity\u0000media';
  }

  static void _checkRootIsolate() {
    if (RootIsolateToken.instance == null) {
      throw StateError('MediaGuard must be used from the root isolate');
    }
  }

  static bool _isContention(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (Platform.isWindows) return code == 33 || code == 32;
    // fcntl reports EAGAIN/EACCES on Linux; EAGAIN is 35 on macOS.
    return code == 11 || code == 13 || code == 35;
  }
}

sealed class _Entry {}

class _Exclusive extends _Entry {
  final done = Completer<void>();
}

class _Shared extends _Entry {
  late Future<RandomAccessFile> ready;
  final done = Completer<void>();
  int references = 0;
  bool closing = false;
}
