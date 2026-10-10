import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_account/src/data/account_repository.dart';
import 'package:moodiary_account/src/presentation/account_page.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

final _session = AccountSession(
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
  accessExpiresAt: DateTime.utc(2099),
  refreshExpiresAt: DateTime.utc(2099),
  user: AccountUser(
    id: 'test-user',
    email: 'reader@example.com',
    emailVerified: true,
    createdAt: DateTime.utc(2026),
  ),
);

class _Repository implements AccountRepository {
  _Repository({
    this.config = const AccountConfig(apiUrl: 'https://accounts.example.com'),
    this.session,
  });

  @override
  final AccountConfig config;
  @override
  AccountSession? session;
  final events = StreamController<void>.broadcast();
  final calls = <String>[];
  String? receivedEmail;
  String? receivedPassword;
  String? receivedToken;
  Object? refreshError;
  Object? loadError;
  Object? logoutError;

  @override
  Stream<void> get changes => events.stream;

  @override
  Future<AccountSession?> load() async {
    calls.add('load');
    if (loadError != null) throw loadError!;
    return session;
  }

  @override
  Future<AccountSession> login({
    required String email,
    required String password,
  }) async {
    calls.add('login');
    receivedEmail = email;
    receivedPassword = password;
    session = _session;
    events.add(null);
    return _session;
  }

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    calls.add('register');
    receivedEmail = email;
    receivedPassword = password;
  }

  @override
  Future<void> verifyEmail({
    required String token,
    required String password,
  }) async {
    calls.add('verify');
    receivedToken = token;
    receivedPassword = password;
  }

  @override
  Future<void> resendVerification({required String email}) async {
    calls.add('resend');
    receivedEmail = email;
  }

  @override
  Future<void> forgotPassword({required String email}) async {
    calls.add('forgot');
    receivedEmail = email;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    calls.add('reset');
    receivedToken = token;
    receivedPassword = password;
  }

  @override
  Future<AccountUser> refreshUser() async {
    calls.add('refresh');
    if (refreshError != null) {
      session = null;
      events.add(null);
      throw refreshError!;
    }
    return session!.user;
  }

  @override
  Future<void> logout() async {
    calls.add('logout');
    session = null;
    events.add(null);
    if (logoutError != null) throw logoutError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _host(WidgetTester tester, _Repository repository) async {
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  getIt.registerSingleton<AccountRepository>(repository);
  addTearDown(() async {
    await getIt.reset();
    await repository.events.close();
  });
  final theme = buildMuiTheme(brightness: Brightness.light);
  await tester.pumpWidget(
    ProviderScope(
      child: TranslationProvider(
        child: MuiTheme(
          data: theme,
          child: MaterialApp(
            theme: theme,
            locale: const Locale('zh'),
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: const [
              ...GlobalMaterialLocalizations.delegates,
              GlobalMuiLocalizations.delegate,
            ],
            home: const AccountPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String name) => find.byKey(ValueKey('account-$name'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async => LocaleSettings.setLocale(AppLocale.zh));

  testWidgets('未开通时不加载凭据，不显示登录表单，说明本地功能可用', (tester) async {
    final repository = _Repository(config: const AccountConfig());
    await _host(tester, repository);

    expect(find.text(l10n.account.unavailableTitle), findsOneWidget);
    expect(find.text(l10n.account.localDescription), findsOneWidget);
    expect(_field('email'), findsNothing);
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('测试服务有标识，登录保留密码原文且不启动日记同步', (tester) async {
    final repository = _Repository(
      config: const AccountConfig(
        apiUrl: 'https://staging.example.com',
        environment: 'staging',
      ),
    );
    await _host(tester, repository);
    expect(find.text(l10n.account.stagingEnvironment), findsOneWidget);
    await tester.enterText(_field('email'), ' reader@example.com ');
    await tester.enterText(_field('password'), ' a password with spaces ');
    await _tap(tester, _field('submit'));

    expect(repository.receivedEmail, 'reader@example.com');
    expect(repository.receivedPassword, ' a password with spaces ');
    expect(repository.calls, ['load', 'login']);
    expect(find.text('reader@example.com'), findsOneWidget);
    expect(find.text(l10n.account.cloudDescription), findsOneWidget);
    expect(_field('password'), findsNothing);
  });

  testWidgets('无效邮箱和过短注册密码不会调用服务', (tester) async {
    final repository = _Repository();
    await _host(tester, repository);
    await _tap(tester, find.text(l10n.account.register));
    await tester.enterText(_field('email'), 'not-an-email');
    await tester.enterText(_field('password'), 'short');
    await tester.enterText(_field('confirm-password'), 'different');
    await _tap(tester, _field('submit'));

    expect(find.text(l10n.account.emailRequired), findsOneWidget);
    expect(find.text(l10n.account.passwordInvalid), findsOneWidget);
    expect(find.text(l10n.account.passwordMismatch), findsOneWidget);
    expect(repository.calls, ['load']);
  });

  testWidgets('注册后验证邮箱使用邮件令牌和原密码，验证后仍需登录', (tester) async {
    final repository = _Repository();
    await _host(tester, repository);
    await _tap(tester, find.text(l10n.account.register));
    await tester.enterText(_field('email'), 'reader@example.com');
    await tester.enterText(_field('password'), ' a valid password ');
    await tester.enterText(_field('confirm-password'), ' a valid password ');
    await _tap(tester, _field('submit'));
    expect(find.text(l10n.account.mailAccepted), findsOneWidget);
    expect(find.text(l10n.account.verifyHint), findsOneWidget);
    expect(repository.session, isNull);

    await tester.enterText(_field('token'), ' mail-token ');
    await tester.enterText(_field('password'), ' a valid password ');
    await _tap(tester, _field('submit'));

    expect(repository.calls, ['load', 'register', 'verify']);
    expect(repository.receivedToken, 'mail-token');
    expect(repository.receivedPassword, ' a valid password ');
    expect(find.text(l10n.account.verified), findsOneWidget);
    expect(_field('token'), findsNothing);
    expect(repository.session, isNull);
  });

  testWidgets('找回密码的通用响应转入重设，重设成功不会自动登录', (tester) async {
    final repository = _Repository();
    await _host(tester, repository);
    await _tap(tester, find.text(l10n.account.forgot));
    await tester.enterText(_field('email'), 'reader@example.com');
    await _tap(tester, _field('submit'));
    expect(find.text(l10n.account.mailAccepted), findsOneWidget);
    await tester.enterText(_field('token'), 'reset-token');
    await tester.enterText(_field('password'), 'replacement password');
    await tester.enterText(_field('confirm-password'), 'replacement password');
    await _tap(tester, _field('submit'));

    expect(repository.calls, ['load', 'forgot', 'reset']);
    expect(repository.receivedToken, 'reset-token');
    expect(find.text(l10n.account.passwordReset), findsOneWidget);
    expect(repository.session, isNull);
  });

  testWidgets('重发验证邮件只需邮箱，不强制填写原密码和令牌', (tester) async {
    final repository = _Repository();
    await _host(tester, repository);
    await _tap(tester, find.text(l10n.account.verify));
    await tester.enterText(_field('email'), 'reader@example.com');
    await _tap(tester, find.text(l10n.account.resendVerification));

    expect(repository.calls, ['load', 'resend']);
    expect(repository.receivedEmail, 'reader@example.com');
    expect(find.text(l10n.account.mailAccepted), findsOneWidget);
    expect(find.text(l10n.account.passwordRequired), findsNothing);
    expect(find.text(l10n.account.tokenRequired), findsNothing);
  });

  testWidgets('退出先说明保留本地数据，确认后只清账号', (tester) async {
    final repository = _Repository(session: _session);
    await _host(tester, repository);
    await _tap(tester, _field('logout'));
    expect(find.text(l10n.account.logoutDescription), findsOneWidget);
    expect(repository.calls, ['load']);
    await _tap(tester, find.text(l10n.account.logout).last);

    expect(repository.calls, ['load', 'logout']);
    expect(find.text(l10n.account.loggedOut), findsOneWidget);
    expect(_field('email'), findsOneWidget);
    expect(find.text(l10n.account.localDescription), findsOneWidget);
  });

  testWidgets('账号失效回登录，显示本地数据不受影响而不输出原始异常', (tester) async {
    final repository = _Repository(session: _session)
      ..refreshError = const AccountException('session_expired');
    await _host(tester, repository);
    await _tap(tester, find.text(l10n.account.refreshAccount));

    expect(_field('email'), findsOneWidget);
    expect(find.text(l10n.account.sessionExpired), findsOneWidget);
    expect(find.textContaining('AccountException'), findsNothing);
    expect(find.text(l10n.account.localDescription), findsOneWidget);
  });

  testWidgets('损坏会话可退出清理，不会困在重试状态', (tester) async {
    final repository = _Repository()
      ..loadError = const AccountException('invalid_session');
    await _host(tester, repository);
    expect(find.text(l10n.account.storageError), findsOneWidget);
    await _tap(tester, _field('logout'));
    expect(find.text(l10n.account.logoutDescription), findsOneWidget);
    await _tap(tester, find.text(l10n.account.logout).last);

    expect(repository.calls, ['load', 'logout']);
    expect(_field('email'), findsOneWidget);
    expect(find.text(l10n.account.loggedOut), findsOneWidget);
  });

  testWidgets('离线退出明确区分本机退出与未确认的服务端撤销', (tester) async {
    final repository = _Repository(session: _session)
      ..logoutError = const AccountException('network_error');
    await _host(tester, repository);
    await _tap(tester, _field('logout'));
    await _tap(tester, find.text(l10n.account.logout).last);

    expect(repository.session, isNull);
    expect(_field('email'), findsOneWidget);
    expect(find.text(l10n.account.logoutRemoteError), findsOneWidget);
    expect(find.text(l10n.account.networkError), findsNothing);
  });
}
