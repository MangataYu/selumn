import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Physical app storage areas. No category implies that its files are safe to
/// delete: media and temporary files can be in use by another operation.
enum StorageCategory {
  database,
  image,
  audio,
  video,
  model,
  font,
  logs,
  cache,
  other,
}

class StorageUsage {
  final Map<StorageCategory, int> bytesByCategory;

  StorageUsage(Map<StorageCategory, int> bytes)
    : bytesByCategory = Map.unmodifiable({
        for (final category in StorageCategory.values)
          category: bytes[category] ?? 0,
      });

  int get totalBytes => bytesByCategory.values.fold(0, (a, b) => a + b);
}

/// Read-only filesystem accounting. Link targets are never traversed.
///
/// The filesystem may change while a scan is in progress, so the result is a
/// snapshot rather than a guarantee that any file can be safely removed.
class StorageScanner {
  final String supportPath;
  final String cachePath;

  const StorageScanner({required this.supportPath, required this.cachePath});

  Future<StorageUsage> scan() async {
    final support = await _resolvedPath(supportPath);
    final cache = await _resolvedPath(cachePath);
    return Isolate.run(() => _scan(support, cache));
  }
}

Future<({String path, bool exists})> _resolvedPath(String path) async {
  final absolute = p.normalize(p.absolute(path));
  try {
    final resolved = await Directory(absolute).resolveSymbolicLinks();
    return (path: p.normalize(resolved), exists: true);
  } on PathNotFoundException {
    // Missing roots are treated as empty, but permission errors must surface.
    return (path: absolute, exists: false);
  }
}

Future<StorageUsage> _scan(
  ({String path, bool exists}) supportRoot,
  ({String path, bool exists}) cacheRoot,
) async {
  final support = supportRoot.path;
  final cache = cacheRoot.path;
  final bytes = <StorageCategory, int>{};

  Future<void> visit(
    String root, {
    required bool isCache,
    String? exclude,
  }) async {
    final directory = Directory(root);
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final path = p.normalize(p.absolute(entity.path));
      if (exclude != null &&
          (p.equals(path, exclude) || p.isWithin(exclude, path))) {
        continue;
      }
      final int size;
      try {
        size = await entity.length();
      } on PathNotFoundException {
        // Another operation can remove a file while the scan is running.
        continue;
      }
      final area = isCache
          ? StorageCategory.cache
          : _supportCategory(root, path);
      bytes[area] = (bytes[area] ?? 0) + size;
    }
  }

  if (p.equals(support, cache)) {
    // One physical tree cannot be partitioned reliably into app data/cache.
    throw ArgumentError('Support and cache directories must be different');
  }
  if (supportRoot.exists) {
    await visit(
      support,
      isCache: false,
      exclude: p.isWithin(support, cache) ? cache : null,
    );
  }
  if (cacheRoot.exists) {
    await visit(
      cache,
      isCache: true,
      exclude: p.isWithin(cache, support) ? support : null,
    );
  }
  return StorageUsage(bytes);
}

StorageCategory _supportCategory(String root, String path) {
  final parts = p.split(p.relative(path, from: root));
  final top = parts.first;
  if (parts.length == 1 && top.startsWith('error.log.')) {
    return .logs;
  }
  return switch (top) {
    'database' => .database,
    'image' => .image,
    'audio' => .audio,
    'video' => .video,
    'model' => .model,
    'font' => .font,
    'sync_logs' || 'error.log' => .logs,
    _ => .other,
  };
}
