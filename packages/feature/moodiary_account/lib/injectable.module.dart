// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'dart:async' as _i687;

import 'package:injectable/injectable.dart' as _i526;
import 'package:moodiary_account/src/data/account_http_module.dart' as _i177;
import 'package:moodiary_account/src/data/account_repository.dart' as _i473;
import 'package:moodiary_http/moodiary_http.dart' as _i765;
import 'package:moodiary_storage/moodiary_storage.dart' as _i877;

class MoodiaryAccountPackageModule extends _i526.MicroPackageModule {
  // initializes the registration of main-scope dependencies inside of GetIt
  @override
  _i687.FutureOr<void> init(_i526.GetItHelper gh) {
    final accountHttpModule = _$AccountHttpModule();
    gh.lazySingleton<_i765.IHttpClient>(
      () => accountHttpModule.accountHttpClient(),
      instanceName: 'selumnAccount',
    );
    gh.lazySingleton<_i473.AccountRepository>(
      () => _i473.AccountRepository.production(
        gh<_i765.IHttpClient>(instanceName: 'selumnAccount'),
        gh<_i877.ISecureKVStorage>(),
      ),
      dispose: (i) => i.dispose(),
    );
  }
}

class _$AccountHttpModule extends _i177.AccountHttpModule {}
