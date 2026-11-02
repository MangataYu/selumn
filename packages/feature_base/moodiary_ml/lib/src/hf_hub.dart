import 'package:moodiary_storage/moodiary_storage.dart';

abstract final class HfHub {
  static const officialEndpoint = 'https://huggingface.co';
  static const mirrorEndpoint = 'https://hf-mirror.com';

  /// An unset endpoint preserves the previous mirror preference and default.
  static String get endpoint {
    final stored = MoodiaryKVs.modelDownloadEndpoint.get() ?? '';
    if (stored.trim().isNotEmpty) return normalize(stored);
    return (MoodiaryKVs.modelDownloadMirror.get() ?? true)
        ? mirrorEndpoint
        : officialEndpoint;
  }

  /// Accept a host or HTTP(S) base URL, including an optional path prefix.
  static String normalize(String endpoint) {
    var base = endpoint.trim();
    if (base.isEmpty) throw const FormatException('Empty endpoint');
    if (!base.contains('://')) base = 'https://$base';
    final uri = Uri.tryParse(base);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        base.contains(RegExp(r'\s'))) {
      throw const FormatException('Invalid endpoint');
    }
    return base.replaceFirst(RegExp(r'/+$'), '');
  }

  static String resolve(String hfPath) => '$endpoint/$hfPath';
}
