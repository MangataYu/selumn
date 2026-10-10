import 'package:moodiary_i18n/moodiary_i18n.dart';

import '../data/account_repository.dart';

/// Never render server messages, URLs or exception strings in account UI.
String accountErrorText(Object error, Translations l10n) {
  if (error is! AccountException) return l10n.account.serviceError;
  return switch (error.code) {
    'disabled' ||
    'configuration_invalid' => l10n.account.unavailableDescription,
    'invalid_credentials' => l10n.account.invalidCredentials,
    'email_unverified' => l10n.account.unverifiedError,
    'invalid_token' => l10n.account.invalidToken,
    'registration_closed' => l10n.account.registrationClosed,
    'device_limit' => l10n.account.deviceLimit,
    'rate_limited' => l10n.account.rateLimited,
    'unauthorized' || 'session_expired' => l10n.account.sessionExpired,
    'network_error' => l10n.account.networkError,
    'logout_remote_failed' => l10n.account.logoutRemoteError,
    'storage_error' || 'invalid_session' => l10n.account.storageError,
    'invalid_input' => l10n.account.invalidInput,
    _ => l10n.account.serviceError,
  };
}
