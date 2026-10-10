import 'package:moodiary_di/moodiary_di.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/account_repository.dart';

part 'account_controller.g.dart';

/// Only observes account credentials. Local journals and sync stay independent.
@Riverpod(retry: _doNotRetry)
class AccountController extends _$AccountController {
  AccountRepository get _repository => getIt<AccountRepository>();

  @override
  Future<AccountSession?> build() async {
    final repository = _repository;
    final subscription = repository.changes.listen((_) {
      if (ref.mounted) state = AsyncData(repository.session);
    });
    ref.onDispose(subscription.cancel);
    return repository.load();
  }

  Future<void> login({required String email, required String password}) async {
    await _repository.login(email: email, password: password);
  }

  Future<void> register({required String email, required String password}) =>
      _repository.register(email: email, password: password);

  Future<void> verifyEmail({required String token, required String password}) =>
      _repository.verifyEmail(token: token, password: password);

  Future<void> resendVerification({required String email}) =>
      _repository.resendVerification(email: email);

  Future<void> forgotPassword({required String email}) =>
      _repository.forgotPassword(email: email);

  Future<void> resetPassword({
    required String token,
    required String password,
  }) => _repository.resetPassword(token: token, password: password);

  Future<void> refreshAccount() async {
    await _repository.refreshUser();
  }

  Future<void> logout() => _repository.logout();
}

// Credential failures need an explicit retry or local sign-out; repeatedly
// reading a corrupt or locked store cannot recover the session.
Duration? _doNotRetry(int retryCount, Object error) => null;
