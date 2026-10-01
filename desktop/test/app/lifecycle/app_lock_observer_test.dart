import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_desktop/app/lifecycle/app_lock_observer.dart';
import 'package:moodiary_desktop/app/router/router.dart' as desktop;
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

Future<void> _pumpApp(WidgetTester tester, String location) async {
  desktop.router.go(location);
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: desktop.router,
      builder: (_, child) => AppLockObserver(child: child!),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _hide(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  // A hidden window does not render frames; inspect the page after restoring it.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    desktop.router = GoRouter(
      routes: [
        for (final path in [
          DiaryHomeRoute.path,
          DiaryRoute.path,
          NewDiaryRoute.path,
          LockRoute.path,
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text(path)),
          ),
      ],
    );
  });
  tearDownAll(() => desktop.router.dispose());

  setUp(() async {
    getIt.pushNewScope(
      init: (gi) => gi
        ..registerSingleton<IKVStorage>(MemoryKVStorage())
        ..registerSingleton<ISecureKVStorage>(MemorySecureKVStorage()),
    );
    await MoodiarySecureKVs.password.set('test pin');
    await AppLockPin.load();
    MoodiaryKVs.lockNow.set(true);
  });
  tearDown(() async {
    await AppLockPin.clear();
    await getIt.popScope();
  });

  for (final path in [DiaryRoute.path, NewDiaryRoute.path]) {
    testWidgets('minimizing $path covers the diary with the lock page', (
      tester,
    ) async {
      await _pumpApp(tester, path);
      await _hide(tester);

      expect(desktop.router.state.uri.path, LockRoute.path);
      expect(desktop.router.state.params['lock_type'], 'pause');
      expect(find.text(LockRoute.path), findsOneWidget);

      await _hide(tester);
      desktop.router.pop();
      await tester.pumpAndSettle();
      expect(desktop.router.state.uri.path, path);
      expect(desktop.router.canPop(), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('minimizing keeps the diary open when immediate lock is off', (
    tester,
  ) async {
    MoodiaryKVs.lockNow.set(false);
    await _pumpApp(tester, DiaryRoute.path);
    await _hide(tester);

    expect(desktop.router.state.uri.path, DiaryRoute.path);
    expect(desktop.router.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('minimizing without an enabled PIN does not open the lock', (
    tester,
  ) async {
    await AppLockPin.clear();
    await _pumpApp(tester, NewDiaryRoute.path);
    await _hide(tester);

    expect(desktop.router.state.uri.path, NewDiaryRoute.path);
    expect(desktop.router.canPop(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
