// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Only observes account credentials. Local journals and sync stay independent.

@ProviderFor(AccountController)
final accountControllerProvider = AccountControllerProvider._();

/// Only observes account credentials. Local journals and sync stay independent.
final class AccountControllerProvider
    extends $AsyncNotifierProvider<AccountController, AccountSession?> {
  /// Only observes account credentials. Local journals and sync stay independent.
  AccountControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: _doNotRetry,
        name: r'accountControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountControllerHash();

  @$internal
  @override
  AccountController create() => AccountController();
}

String _$accountControllerHash() => r'cc3ecdc8f7a530030761a7aafd3ddd81a20929ff';

/// Only observes account credentials. Local journals and sync stay independent.

abstract class _$AccountController extends $AsyncNotifier<AccountSession?> {
  FutureOr<AccountSession?> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AccountSession?>, AccountSession?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AccountSession?>, AccountSession?>,
              AsyncValue<AccountSession?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
