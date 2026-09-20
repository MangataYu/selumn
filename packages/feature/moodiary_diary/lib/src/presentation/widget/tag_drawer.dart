import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

class TagDrawer extends ConsumerStatefulWidget {
  final Widget? navigation;
  final VoidCallback? onFilterSelected;
  final bool isDiarySelected;

  const TagDrawer({
    super.key,
    this.navigation,
    this.onFilterSelected,
    this.isDiarySelected = true,
  });

  @override
  ConsumerState<TagDrawer> createState() => _TagDrawerState();
}

class _TagDrawerState extends ConsumerState<TagDrawer> {
  String _query = '';

  void _pick(DiaryFilter filter) {
    ref.read(diarySelectionProvider.notifier).clear();
    ref.read(homeDiaryFilterProvider.notifier).select(filter);
    Navigator.of(context).pop();
    widget.onFilterSelected?.call();
  }

  Future<void> _manage(String tag) async {
    final action = await MAlert.show<String>(
      context,
      title: '#$tag',
      actions: [
        MAction(label: l10n.common.cancel),
        MAction(label: l10n.diary.tagRename, value: 'rename'),
        MAction(
          label: l10n.diary.tagDelete,
          value: 'delete',
          isDestructive: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    final repository = getIt<DiaryRepository>();
    if (action == 'rename') {
      final value = await MAlert.prompt(
        context,
        title: l10n.diary.tagRename,
        initialValue: tag,
        hintText: l10n.diary.tagRenameHint,
        validator: (value) {
          final path = TagPath.normalize(value);
          return path == null || !TagPath.isInline(path)
              ? l10n.diary.tagInvalid
              : null;
        },
        onSubmit: (value) async {
          try {
            await repository.renameTag(tag, TagPath.normalize(value)!);
            return null;
          } catch (_) {
            return l10n.diary.tagUpdateFailed;
          }
        },
      );
      if (!mounted || value == null) return;
      final selected = ref.read(homeDiaryFilterProvider).tagPath;
      if (selected != null && TagPath.matches(selected, tag)) {
        ref
            .read(homeDiaryFilterProvider.notifier)
            .select(
              .tag(
                '${TagPath.normalize(value)!}${selected.substring(tag.length)}',
              ),
            );
        ref.read(diarySelectionProvider.notifier).clear();
      }
    } else {
      final confirmed = await MAlert.confirm(
        context,
        title: l10n.diary.tagDelete,
        message: l10n.diary.tagDeleteMessage(tag: tag),
        confirmLabel: l10n.common.delete,
        isDestructive: true,
      );
      if (!confirmed || !mounted) return;
      try {
        await repository.deleteTag(tag);
        if (!mounted) return;
        final selected = ref.read(homeDiaryFilterProvider).tagPath;
        if (selected != null && TagPath.matches(selected, tag)) {
          ref.read(homeDiaryFilterProvider.notifier).reset();
          ref.read(diarySelectionProvider.notifier).clear();
        }
      } catch (_) {
        if (mounted) toast.error(message: l10n.diary.tagUpdateFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final filter = ref.watch(homeDiaryFilterProvider);
    final tagsAsync = ref.watch(diaryTagsProvider);
    final tags = tagsAsync.value ?? const <String>[];
    final paths = {
      for (final tag in tags) ...TagPath.ancestors(tag),
      ...tags,
    }.toList()..sort();
    final counts = ref.watch(tagDiaryCountsProvider).value;
    final query = _query.trim().toLowerCase();
    final visible = paths.where((path) => path.toLowerCase().contains(query));

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: .only(bottom: 12 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            Padding(
              padding: const .fromLTRB(20, 20, 20, 14),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    context.l10n.common.appName,
                    style: context
                        .theme
                        .typography
                        .titleLarge
                        .emphasized
                        .onSurface,
                  ),
                  if (counts != null)
                    Text(
                      context.l10n.diary.searchResult(count: counts.total),
                      style:
                          context.theme.typography.labelMedium.onSurfaceVariant,
                    ),
                ],
              ),
            ),
            if (widget.navigation != null) widget.navigation!,
            Padding(
              padding: const .fromLTRB(16, 4, 16, 6),
              child: Row(
                children: [
                  Text(
                    context.l10n.common.tag,
                    style:
                        context.theme.typography.labelMedium.onSurfaceVariant,
                  ),
                  const Spacer(),
                  Text(
                    context.l10n.common.tagCount(count: tags.length),
                    style: context.theme.typography.labelSmall.outline,
                  ),
                ],
              ),
            ),
            if (paths.length >= 8)
              Padding(
                padding: const .fromLTRB(12, 0, 12, 8),
                child: SearchBar(
                  hintText: context.l10n.diary.tagSearchHint,
                  leading: const Icon(LucideIcons.search, size: 20),
                  constraints: const BoxConstraints(minHeight: 42),
                  elevation: const WidgetStatePropertyAll(0),
                  backgroundColor: WidgetStatePropertyAll(
                    colors.surfaceContainerHigh,
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
            if (query.isEmpty)
              _TagTile(
                label: context.l10n.diary.categoryAllDiary,
                count: counts?.total,
                selected: widget.isDiarySelected && filter.isAll,
                icon: LucideIcons.notebookPen,
                onTap: () => _pick(const .all()),
              ),
            for (final path in visible)
              _TagTile(
                label: query.isEmpty ? path.split('/').last : path,
                count: counts == null ? null : counts.byTag[path] ?? 0,
                depth: query.isEmpty ? path.split('/').length - 1 : 0,
                selected: widget.isDiarySelected && filter.tagPath == path,
                icon: LucideIcons.hash,
                onTap: () => _pick(.tag(path)),
                onLongPress: () => _manage(path),
              ),
            if (visible.isEmpty && query.isNotEmpty)
              Padding(
                padding: const .all(16),
                child: Text(context.l10n.diary.tagNoMatch),
              ),
            if (tagsAsync.hasError)
              Padding(
                padding: const .all(16),
                child: Text(context.l10n.diary.tagUpdateFailed),
              ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.outlineVariant),
            _TagTile(
              label: context.l10n.diary.tagNoTag,
              count: counts?.untagged,
              selected: widget.isDiarySelected && filter.untagged,
              icon: LucideIcons.tag,
              onTap: () => _pick(const .untagged()),
            ),
            Padding(
              padding: const .fromLTRB(12, 4, 12, 0),
              child: Align(
                alignment: .centerRight,
                child: IconButton.filledTonal(
                  tooltip: context.l10n.app.homeNavigatorSetting,
                  icon: const Icon(LucideIcons.settings, size: 20),
                  onPressed: () {
                    Navigator.of(context).pop();
                    const SettingRoute().push(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagTile extends StatelessWidget {
  final String label;
  final int? count;
  final int depth;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _TagTile({
    required this.label,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.depth = 0,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Semantics(
      selected: selected,
      child: Padding(
        padding: const .symmetric(horizontal: 12, vertical: 1),
        child: Material(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: .circular(28),
          clipBehavior: .antiAlias,
          child: MInkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: .fromLTRB(14 + depth.clamp(0, 4) * 12, 12, 14, 12),
              child: Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: .ellipsis),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$count',
                      style:
                          context.theme.typography.labelMedium.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
