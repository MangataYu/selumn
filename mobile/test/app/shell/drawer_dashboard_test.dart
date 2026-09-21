import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/shell/drawer_dashboard.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DashboardStats _stats({bool empty = false}) => DashboardStats(
  useDays: 125,
  diaryCount: empty ? 0 : 47,
  wordCount: empty ? 0 : 600,
  categoryCount: 1,
  streakDays: empty ? 0 : 1,
  thisMonthCount: empty ? 0 : 2,
  tagCount: empty ? 0 : 22,
  byDay: empty
      ? const {}
      : {
          _today(): const DayWriting(
            count: 2,
            words: 600,
            level: 3,
            ids: ['first', 'second'],
            coverName: null,
            coverIsVideo: false,
            categoryId: null,
            title: '',
          ),
        },
  lastYearCount: empty ? 0 : 47,
);

class _Dashboard extends DashboardController {
  final Future<DashboardStats> Function() load;

  _Dashboard(this.load);

  @override
  Future<DashboardStats> build() => load();
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Future<DashboardStats> Function() load,
  double width = 320,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        dashboardControllerProvider.overrideWith(() => _Dashboard(load)),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          theme: buildMuiTheme(brightness: Brightness.light),
          localizationsDelegates: const [
            ...GlobalMaterialLocalizations.delegates,
            GlobalMuiLocalizations.delegate,
          ],
          supportedLocales: AppLocaleUtils.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 640),
                textScaler: TextScaler.linear(textScale),
              ),
              child: SingleChildScrollView(
                child: SizedBox(width: width, child: const DrawerDashboard()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _cells() => find.descendant(
  of: find.byType(MHeatmap),
  matching: find.byType(GestureDetector),
);

void main() {
  testWidgets('抽屉顶部显示日记、标签、使用天数和最近的热力图', (tester) async {
    await _pumpDashboard(tester, load: () async => _stats());
    await tester.pumpAndSettle();

    for (final text in ['47', '22', '125']) {
      expect(find.text(text), findsOneWidget);
    }
    for (final label in [
      l10n.app.homeNavigatorDiary,
      l10n.app.dashTagCount,
      l10n.app.dashUseDays,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    final heatmap = tester.widget<MHeatmap>(find.byType(MHeatmap));
    expect(heatmap.levels[_today()], 3);
    expect(find.text(l10n.app.meHeatmapHint), findsOneWidget);
    final scrollable = tester.widget<Scrollable>(
      find.descendant(
        of: find.byType(MHeatmap),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      scrollable.controller!.position.pixels,
      scrollable.controller!.position.maxScrollExtent,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击日期显示当天篇数和字数，再次点击取消选择', (tester) async {
    await _pumpDashboard(tester, load: () async => _stats());
    await tester.pumpAndSettle();

    await tester.tap(_cells().last);
    await tester.pump();
    expect(
      find.text(
        '${TimeFormat.monthDay(_today())} · '
        '${l10n.diary.timelineMonthCount(count: 2)} · '
        '${l10n.diary.wordCount(count: 600)}',
      ),
      findsOneWidget,
    );
    expect(tester.widget<MHeatmap>(find.byType(MHeatmap)).selected, _today());

    await tester.tap(_cells().last);
    await tester.pump();
    expect(find.text(l10n.app.meHeatmapHint), findsOneWidget);
    expect(tester.widget<MHeatmap>(find.byType(MHeatmap)).selected, isNull);

    await tester.tap(_cells().at(_cells().evaluate().length - 2));
    await tester.pump();
    expect(find.textContaining(l10n.app.meDayNothing), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有日记时显示零值、空网格和写作提示', (tester) async {
    await _pumpDashboard(tester, load: () async => _stats(empty: true));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNWidgets(2));
    expect(find.text('125'), findsOneWidget);
    expect(find.text(l10n.app.meHeatmapEmpty), findsOneWidget);
    expect(tester.widget<MHeatmap>(find.byType(MHeatmap)).levels, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('加载中不会把统计显示成零，数据完成后显示热力图', (tester) async {
    final pending = Completer<DashboardStats>();
    await _pumpDashboard(tester, load: () => pending.future);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
    pending.complete(_stats());
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(MHeatmap), findsOneWidget);
  });

  testWidgets('加载失败显示错误，并可重试恢复', (tester) async {
    var attempts = 0;
    await _pumpDashboard(
      tester,
      load: () async {
        if (++attempts == 1) throw StateError('failed to read dashboard');
        return _stats();
      },
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.common.loadFailed), findsOneWidget);
    expect(find.byType(MHeatmap), findsNothing);
    await tester.tap(find.text(l10n.common.retry));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text(l10n.common.loadFailed), findsNothing);
    expect(find.byType(MHeatmap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏和两倍字号不溢出，日期详情仍完整可见', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpDashboard(
      tester,
      width: 272,
      textScale: 2,
      load: () async => _stats(),
    );
    await tester.pumpAndSettle();
    await tester.tap(_cells().last);
    await tester.pump();

    expect(tester.takeException(), isNull);
    final detail = find.textContaining(l10n.diary.wordCount(count: 600));
    expect(detail, findsOneWidget);
    expect(tester.getRect(detail).right, lessThanOrEqualTo(272));
    expect(tester.getRect(detail).bottom, lessThan(640));
    expect(tester.widget<Text>(detail).maxLines, isNull);
  });
}
