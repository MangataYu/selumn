/// Only fixed codes cross the account boundary; server messages stay private.
class AccountException implements Exception {
  const AccountException(this.code);

  final String code;

  @override
  String toString() => 'AccountException($code)';
}

class AccountUser {
  const AccountUser({
    required this.id,
    required this.email,
    required this.emailVerified,
    required this.createdAt,
  });

  factory AccountUser.fromJson(Map<String, dynamic> json) {
    if (json['email_verified'] is! bool) {
      throw const FormatException('Invalid account user');
    }
    return AccountUser(
      id: _string(json, 'id'),
      email: _string(json, 'email'),
      emailVerified: json['email_verified'] as bool,
      createdAt: _date(json, 'created_at'),
    );
  }

  final String id;
  final String email;
  final bool emailVerified;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'email_verified': emailVerified,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}

class AccountSession {
  const AccountSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.user,
  });

  factory AccountSession.fromJson(Map<String, dynamic> json) {
    if (json['token_type'] != 'Bearer' ||
        json['user'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid account session');
    }
    return AccountSession(
      accessToken: _token(json, 'access_token'),
      refreshToken: _token(json, 'refresh_token'),
      accessExpiresAt: _date(json, 'access_expires_at'),
      refreshExpiresAt: _date(json, 'refresh_expires_at'),
      user: AccountUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final AccountUser user;

  AccountSession withUser(AccountUser user) => AccountSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    accessExpiresAt: accessExpiresAt,
    refreshExpiresAt: refreshExpiresAt,
    user: user,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'token_type': 'Bearer',
    'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
    'user': user.toJson(),
  };
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Invalid account field');
  }
  return value;
}

String _token(Map<String, dynamic> json, String key) {
  final value = _string(json, key);
  if (value.length > 512 ||
      !RegExp(r'^[A-Za-z0-9._~+/-]+=*$').hasMatch(value)) {
    throw const FormatException('Invalid account token');
  }
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null) throw const FormatException('Invalid account date');
  return value.toUtc();
}
