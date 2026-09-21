import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:mui/mui.dart';

class DiaryManagementSection extends ConsumerWidget {
  const DiaryManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeCount = ref.watch(placeControllerProvider).value?.length;
    final colors = context.theme.colors;
    Widget lead(IconData icon) => Icon(icon, color: colors.onSurfaceVariant);
    Widget chevron() => lead(LucideIcons.chevronRight);

    return MSliverSettingGroup(
      children: [
        SettingListTile(
          title: context.l10n.diary.tagManagerTitle,
          leading: lead(LucideIcons.tags),
          trailing: chevron(),
          onTap: () => const TagManagerRoute().push(context),
        ),
        SettingListTile(
          title: context.l10n.app.placeManager,
          leading: lead(LucideIcons.mapPinned),
          trailing: placeCount == null
              ? chevron()
              : Row(
                  mainAxisSize: .min,
                  children: [
                    Text(
                      '$placeCount',
                      style: context.theme.typography.bodySmall.primary,
                    ),
                    const SizedBox(width: 4),
                    chevron(),
                  ],
                ),
          onTap: () => const PlaceManagerRoute().push(context),
        ),
        SettingListTile(
          title: context.l10n.app.recycle,
          leading: lead(LucideIcons.trash),
          trailing: chevron(),
          onTap: () => const RecycleRoute().push(context),
        ),
      ],
    );
  }
}
