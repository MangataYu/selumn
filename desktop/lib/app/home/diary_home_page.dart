import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_desktop/app/home/diary_navigation.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_sync/moodiary_sync.dart';
import 'package:mui/mui.dart';

class DesktopDiaryHomePage extends ConsumerWidget {
  final VoidCallback? onOpenDrawer;

  const DesktopDiaryHomePage({super.key, this.onOpenDrawer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(homeDiaryFilterProvider);
    final selection = ref.watch(diarySelectionProvider);
    final selecting = selection.isNotEmpty;
    final label = switch (filter.content) {
      .images => context.l10n.diary.filterImages,
      .links => context.l10n.diary.filterLinks,
      .audio => context.l10n.diary.filterAudio,
      null =>
        filter.untagged
            ? context.l10n.diary.tagNoTag
            : filter.tagPath == null
            ? context.l10n.app.homeNavigatorDiary
            : '#${filter.tagPath}',
    };

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        leading: selecting
            ? IconButton(
                tooltip: context.l10n.common.cancel,
                icon: const Icon(LucideIcons.x),
                onPressed: () =>
                    ref.read(diarySelectionProvider.notifier).clear(),
              )
            : onOpenDrawer == null
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                icon: const Icon(LucideIcons.menu),
                onPressed: onOpenDrawer,
              ),
        automaticallyImplyLeading: false,
        title: Text(
          selecting
              ? context.l10n.app.homeSelected(count: selection.length)
              : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: selecting
            ? [
                IconButton(
                  tooltip: context.l10n.common.delete,
                  icon: const Icon(LucideIcons.trash2),
                  onPressed: () => _deleteSelected(context, ref),
                ),
              ]
            : [
                IconButton(
                  tooltip: context.l10n.diary.search,
                  icon: const Icon(LucideIcons.search),
                  onPressed: () => const DiarySearchRoute().push(context),
                ),
                const SyncStatusButton(),
              ],
      ),
      body: ValueListenableBuilder(
        valueListenable: MoodiaryKVs.homeSortMode.getNotifier(),
        builder: (context, sortMode, _) =>
            DiaryFeedView(filter: filter, sort: DiarySort.getType(sortMode)),
      ),
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.small(
              tooltip: context.l10n.app.homePageAddDiaryButton,
              onPressed: () => openNewDiary(context, tag: filter.tagPath),
              child: const Icon(LucideIcons.pencilLine),
            ),
    );
  }

  Future<void> _deleteSelected(BuildContext context, WidgetRef ref) async {
    final ids = ref.read(diarySelectionProvider);
    if (ids.isEmpty) return;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.app.homeDeleteTitle,
      message: l10n.app.homeDeleteMessage(count: ids.length),
      confirmLabel: l10n.common.delete,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final filter = ref.read(homeDiaryFilterProvider);
    final n = await ref
        .read(
          diaryControllerProvider(
            tag: filter.tagPath,
            untagged: filter.untagged,
            content: filter.content,
          ).notifier,
        )
        .softDeleteByIds(ids);
    if (!context.mounted) return;
    ref.read(diarySelectionProvider.notifier).clear();
    if (n == 0) {
      toast.info(message: l10n.app.homeNothingToDelete);
    } else {
      toast.success(message: l10n.app.homeMovedToRecycle(count: n));
    }
  }
}
