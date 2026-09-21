import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

class DrawerDashboard extends ConsumerStatefulWidget {
  const DrawerDashboard({super.key});

  @override
  ConsumerState<DrawerDashboard> createState() => _DrawerDashboardState();
}

class _DrawerDashboardState extends ConsumerState<DrawerDashboard> {
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardControllerProvider);
    final stats = dashboard.value;
    final l10n = context.l10n;

    return Padding(
      padding: const .fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Row(
            crossAxisAlignment: .start,
            children: [
              _Metric(
                label: l10n.app.homeNavigatorDiary,
                value: stats?.diaryCount,
              ),
              const SizedBox(width: 8),
              _Metric(label: l10n.app.dashTagCount, value: stats?.tagCount),
              const SizedBox(width: 8),
              _Metric(label: l10n.app.dashUseDays, value: stats?.useDays),
            ],
          ),
          const SizedBox(height: 16),
          dashboard.when(
            data: (data) => _heatmap(context, data),
            loading: () => const SizedBox(
              height: 113,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (_, _) => Column(
              mainAxisSize: .min,
              children: [
                Text(
                  l10n.common.loadFailed,
                  textAlign: .center,
                  style: context.theme.typography.bodySmall.onSurfaceVariant,
                ),
                TextButton(
                  onPressed: () => ref.invalidate(dashboardControllerProvider),
                  child: Text(l10n.common.retry),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heatmap(BuildContext context, DashboardStats stats) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final l10n = context.l10n;
    final day = _selectedDay;
    final writing = stats.byDay[day];
    final String detail;
    if (day == null) {
      detail = stats.diaryCount == 0
          ? l10n.app.meHeatmapEmpty
          : l10n.app.meHeatmapHint;
    } else if (writing == null) {
      detail = '${TimeFormat.monthDay(day)} · ${l10n.app.meDayNothing}';
    } else {
      detail =
          '${TimeFormat.monthDay(day)} · '
          '${l10n.diary.timelineMonthCount(count: writing.count)} · '
          '${l10n.diary.wordCount(count: writing.words)}';
    }

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        MHeatmap(
          endDate: today,
          levels: {
            for (final entry in stats.byDay.entries)
              entry.key: entry.value.level,
          },
          selected: day,
          onDaySelected: (day) =>
              setState(() => _selectedDay = day == _selectedDay ? null : day),
          monthLabel: TimeFormat.monthAbbr,
          semanticsLabel: l10n.app.meHeatmapSemantics,
        ),
        const SizedBox(height: 10),
        Text(
          detail,
          style: context.theme.typography.labelSmall.onSurfaceVariant,
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final int? value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final typo = context.theme.typography;
    return Expanded(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          Text(
            value == null ? '—' : '$value',
            style: typo.titleLarge.emphasized.onSurface.copyWith(
              fontFeatures: const [.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: typo.labelSmall.onSurfaceVariant),
        ],
      ),
    );
  }
}
