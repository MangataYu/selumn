import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_diary/src/presentation/calendar/calendar_page.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

import 'support/pump.dart';

class _EmptyDashboard extends DashboardController {
  @override
  Future<DashboardStats> build() async => const DashboardStats(
    useDays: 0,
    diaryCount: 0,
    wordCount: 0,
    categoryCount: 0,
    streakDays: 0,
    thisMonthCount: 0,
    tagCount: 0,
    byDay: {},
    lastYearCount: 0,
  );
}

Future<void> _pumpCalendar(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    muiTestApp(
      const CalendarPage(),
      wrapScaffold: false,
      locale: const Locale('en'),
      overrides: [
        dashboardControllerProvider.overrideWith(_EmptyDashboard.new),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(setupPluralResolvers);

  setUp(() {
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en';
    addTearDown(() => Intl.defaultLocale = previousLocale);
  });

  testWidgets('desktop mouse buttons page months and return to today', (
    tester,
  ) async {
    final now = DateTime.now();
    await _pumpCalendar(tester);

    await tester.tap(
      find.byTooltip(l10n.diary.calendarNextMonth),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(TimeFormat.monthTitle(DateTime(now.year, now.month + 1))),
      findsOneWidget,
    );

    await tester.tap(
      find.byTooltip(l10n.diary.calendarPreviousMonth),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text(TimeFormat.monthTitle(now)), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.diary.calendarPreviousMonth));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.diary.calendarBackToToday));
    await tester.pumpAndSettle();
    expect(find.text(TimeFormat.monthTitle(now)), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'desktop mouse buttons page years and preserve the selected month',
    (tester) async {
      final now = DateTime.now();
      await _pumpCalendar(tester);
      await tester.tap(find.byTooltip(l10n.diary.calendarYearView));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip(l10n.diary.calendarNextYear),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(TimeFormat.yearTitle(DateTime(now.year + 1))),
        findsOneWidget,
      );
      await tester.tap(
        find.byTooltip(l10n.diary.calendarPreviousYear),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text(TimeFormat.yearTitle(now)), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.diary.calendarNextYear));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.diary.calendarMonthView));
      await tester.pumpAndSettle();
      expect(
        find.text(TimeFormat.monthTitle(DateTime(now.year + 1, now.month))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('short year view can scroll to the last month', (tester) async {
    await _pumpCalendar(tester);
    await tester.tap(find.byTooltip(l10n.diary.calendarYearView));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(500, 360);
    await tester.pumpAndSettle();

    final december = find.text(TimeFormat.monthAbbr(DateTime(2026, 12)));
    expect(december.hitTestable(), findsNothing);
    await tester.drag(find.byType(GridView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(december.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('mobile keeps the compact gesture navigation', (tester) async {
    await _pumpCalendar(tester);
    expect(find.byTooltip(l10n.diary.calendarPreviousMonth), findsNothing);
    expect(find.byTooltip(l10n.diary.calendarNextMonth), findsNothing);
    expect(find.byTooltip(l10n.diary.calendarYearView), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
