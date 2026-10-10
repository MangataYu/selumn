import 'dart:convert';

/// Account configuration is independent of local diary storage and startup.
class AccountConfig {
  const AccountConfig({this.apiUrl = '', this.environment = 'production'});

  const AccountConfig.fromEnvironment()
    : apiUrl = const String.fromEnvironment('SELUMN_API_URL'),
      environment = const String.fromEnvironment(
        'SELUMN_ENVIRONMENT',
        defaultValue: 'production',
      );

  final String apiUrl;
  final String environment;

  bool get isConfigured => apiUrl.trim().isNotEmpty;
  bool get isValid => _validatedUri != null;
  bool get isEnabled => isConfigured && isValid;

  /// Only origins are accepted, so endpoints cannot escape a path prefix.
  Uri? get _validatedUri {
    if (!{'production', 'staging', 'development'}.contains(environment)) {
      return null;
    }
    try {
      final uri = Uri.tryParse(apiUrl.trim());
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          uri.port < 1 ||
          uri.port > 65535) {
        return null;
      }
      if (uri.scheme == 'https') return Uri.parse(uri.origin);
      if (environment == 'development' &&
          uri.scheme == 'http' &&
          _isLocalHost(uri.host)) {
        return Uri.parse(uri.origin);
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  String? get baseUrl => _validatedUri?.toString();

  /// Separate credentials even when staging and production share one host.
  String get storagePrefix {
    final identity = '$environment\n${baseUrl ?? apiUrl.trim()}';
    return 'selumn_account_v1_${base64Url.encode(utf8.encode(identity))}';
  }

  static bool _isLocalHost(String host) {
    final normalized = host
        .toLowerCase()
        .replaceAll('[', '')
        .replaceAll(']', '');
    if (normalized == 'localhost' || normalized == '::1') return true;
    final parts = normalized.split('.').map(int.tryParse).toList();
    if (parts.length == 4 &&
        parts.every((part) => part != null && part >= 0 && part <= 255)) {
      return parts[0] == 127 ||
          parts[0] == 10 ||
          (parts[0] == 192 && parts[1] == 168) ||
          (parts[0] == 172 && parts[1]! >= 16 && parts[1]! <= 31);
    }
    return normalized.contains(':') &&
        (normalized.startsWith('fc') || normalized.startsWith('fd'));
  }
}
