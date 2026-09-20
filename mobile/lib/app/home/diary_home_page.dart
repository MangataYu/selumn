import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_diary/moodiary_diary.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_mobile/app/shell/root_navigation.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_sync/moodiary_sync.dart';
import 'package:mui/mui.dart';

class _DiaryListView extends ConsumerStatefulWidget {
  final VoidCallback? onOpenDrawer;

  const _DiaryListView({this.onOpenDrawer});

  @override
  ConsumerState<_DiaryListView> createState() => _DiaryListViewState();
}

class _DiaryListViewState extends ConsumerState<_DiaryListView> {
  Widget _buildDiaryView(DiaryFilter filter) {
    return ValueListenableBuilder(
      valueListenable: MoodiaryKVs.homeViewMode.getNotifier(),
      builder: (context, viewMode, _) {
        return ValueListenableBuilder(
          valueListenable: MoodiaryKVs.homeSortMode.getNotifier(),
          builder: (context, sortMode, _) {
            final viewModeType = ViewModeType.getType(viewMode);
            final sort = DiarySort.getType(sortMode);
            return AnimatedSwitcher(
              duration: Durations.short3,
              child: KeyedSubtree(
                key: ValueKey('$viewMode-$sortMode-$filter'),
                child: switch (viewModeType) {
                  .timeline => DiaryTimelineView(filter: filter, sort: sort),
                  .feed => DiaryFeedView(filter: filter, sort: sort),
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(diarySelectionProvider);
    final selecting = selection.isNotEmpty;
    final filter = ref.watch(homeDiaryFilterProvider);

    final body = _buildDiaryView(filter);
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(diarySelectionProvider.notifier).clear();
      },
      child: Scaffold(
        appBar: selecting
            ? _selectionAppBar(context, selection.length)
            : _normalAppBar(context, filter),
        body: body,
      ),
    );
  }

  PreferredSizeWidget _selectionAppBar(BuildContext context, int count) {
    return AppBar(
      leading: IconButton(
        tooltip: context.l10n.common.cancel,
        icon: const Icon(LucideIcons.x),
        onPressed: () => ref.read(diarySelectionProvider.notifier).clear(),
      ),
      title: Text(context.l10n.app.homeSelected(count: count)),
      actions: [
        IconButton(
          tooltip: context.l10n.common.delete,
          icon: const Icon(LucideIcons.trash2),
          onPressed: count == 0 ? null : _deleteSelected,
        ),
      ],
    );
  }

  PreferredSizeWidget _normalAppBar(BuildContext context, DiaryFilter filter) {
    return RootNavigation(
      onOpenDrawer: widget.onOpenDrawer,
      menuIcon: const Icon(LucideIcons.menu),
      bottom: filter.isAll
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(
                MediaQuery.textScalerOf(context).scale(24) + 8,
              ),
              child: Padding(
                padding: const .fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: .centerLeft,
                  child: _FilterTitle(filter: filter),
                ),
              ),
            ),
      actions: [
        IconButton(
          tooltip: context.l10n.diary.search,
          icon: const Icon(LucideIcons.search),
          onPressed: () => const DiarySearchRoute().push(context),
        ),
        const SyncStatusButton(),
        ValueListenableBuilder(
          valueListenable: MoodiaryKVs.homeViewMode.getNotifier(),
          builder: (context, homeViewMode, _) {
            final viewModeType = ViewModeType.getType(homeViewMode);
            return IconButton(
              tooltip: context.l10n.diary.pageViewModeButton,
              icon: Icon(switch (viewModeType) {
                .timeline => LucideIcons.gitCommitVertical,
                .feed => LucideIcons.layoutList,
              }),
              onPressed: () => ViewModeSheet.show(context),
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteSelected() async {
    final ids = ref.read(diarySelectionProvider);
    if (ids.isEmpty) return;
    final confirmed = await MAlert.confirm(
      context,
      title: l10n.app.homeDeleteTitle,
      message: l10n.app.homeDeleteMessage(count: ids.length),
      confirmLabel: l10n.common.delete,
      isDestructive: true,
    );
    if (!confirmed) return;
    final filter = ref.read(homeDiaryFilterProvider);
    final n = await ref
        .read(
          diaryControllerProvider(
            tag: filter.tagPath,
            untagged: filter.untagged,
          ).notifier,
        )
        .softDeleteByIds(ids);
    if (!mounted) return;
    ref.read(diarySelectionProvider.notifier).clear();
    if (n == 0) {
      toast.info(message: l10n.app.homeNothingToDelete);
    } else {
      toast.success(message: l10n.app.homeMovedToRecycle(count: n));
    }
  }
}

class _FilterTitle extends ConsumerWidget {
  final DiaryFilter filter;

  const _FilterTitle({required this.filter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(tagDiaryCountsProvider).value;
    final label = filter.untagged
        ? context.l10n.diary.tagNoTag
        : '#${filter.tagPath}';
    final count = counts == null
        ? null
        : filter.untagged
        ? counts.untagged
        : counts.byTag[filter.tagPath] ?? 0;

    return Row(
      mainAxisSize: .min,
      children: [
        Icon(filter.untagged ? LucideIcons.tag : LucideIcons.hash, size: 16),
        const SizedBox(width: 8),
        Flexible(child: Text(label, maxLines: 1, overflow: .ellipsis)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            context.l10n.diary.searchResult(count: count),
            style: context.theme.typography.labelSmall.onSurfaceVariant,
          ),
        ],
      ],
    );
  }
}

class DiaryHomePage extends StatelessWidget {
  final VoidCallback? onOpenDrawer;

  const DiaryHomePage({super.key, this.onOpenDrawer});

  @override
  Widget build(BuildContext context) {
    return _DiaryListView(onOpenDrawer: onOpenDrawer);
  }
}
