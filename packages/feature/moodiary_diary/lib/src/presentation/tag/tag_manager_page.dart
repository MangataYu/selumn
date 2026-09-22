import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_diary/src/application/tag_management.dart';
import 'package:moodiary_diary/src/application/tag_order.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_actions.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:mui/mui.dart';

class TagManagerPage extends ConsumerStatefulWidget {
  const TagManagerPage({super.key});

  @override
  ConsumerState<TagManagerPage> createState() => _TagManagerPageState();
}

class _TagManagerPageState extends ConsumerState<TagManagerPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String? _parent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _back(String? parent) {
    if (parent == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _parent = TagOrderDraft.parentOf(parent);
        _query = '';
        _searchController.clear();
      });
    }
  }

  void _reorder(
    List<String> tags,
    String? parent,
    List<String> children,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex == newIndex) return;
    final management = ref.read(tagManagementProvider);
    final latestTags = ref.read(diaryTagsProvider).value ?? tags;
    final draft = TagOrderDraft(latestTags, management.savedOrder);
    final latestChildren = draft.childrenOf(parent);
    final from = latestChildren.indexOf(children[oldIndex]);
    final to = latestChildren.indexOf(children[newIndex]);
    // A tag may have changed while a drag was in progress.
    if (from < 0 || to < 0) return;
    draft.reorder(parent, from, to);
    try {
      management.saveOrder(draft.paths, latestTags);
      HapticFeedback.mediumImpact();
    } catch (_) {
      toast.error(message: l10n.diary.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(diaryTagsProvider);
    final counts = ref.watch(tagDiaryCountsProvider).value?.byTag;
    final spacing = context.spacing;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    var parent = _parent;
    if (tagsAsync.hasValue) {
      final paths = TagOrderDraft(tagsAsync.requireValue, const []).paths;
      // Return to the nearest remaining parent after an external tag update.
      while (parent != null && !paths.contains(parent)) {
        parent = TagOrderDraft.parentOf(parent);
      }
    }
    final currentParent = parent;
    return PopScope<void>(
      canPop: currentParent == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back(currentParent);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            key: const ValueKey('tag-manager-back'),
            onPressed: () => _back(currentParent),
          ),
          title: Text(context.l10n.diary.tagManagerTitle),
        ),
        body: SafeArea(
          top: false,
          child: ValueListenableBuilder(
            valueListenable: MoodiaryKVs.defaultTag.getNotifier(),
            builder: (context, defaultTag, _) => Column(
              children: [
                if (!keyboardVisible)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: spacing.lg),
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Row(
                          children: [
                            Text(
                              context.l10n.diary.tagDefaultTitle,
                              style:
                                  context.theme.typography.bodyLarge.onSurface,
                            ),
                            SizedBox(width: spacing.md),
                            Expanded(
                              child: Text(
                                defaultTag.isEmpty
                                    ? context.l10n.diary.tagDefaultNone
                                    : '#$defaultTag',
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: context
                                    .theme
                                    .typography
                                    .bodyMedium
                                    .onSurfaceVariant,
                              ),
                            ),
                            if (defaultTag.isNotEmpty)
                              IconButton(
                                key: const ValueKey(
                                  'tag-manager-clear-default',
                                ),
                                tooltip: context.l10n.diary.tagClearDefault,
                                icon: const Icon(LucideIcons.x, size: 20),
                                onPressed: () {
                                  try {
                                    ref
                                        .read(tagManagementProvider)
                                        .setDefaultTag('');
                                  } catch (_) {
                                    toast.error(message: l10n.diary.saveFailed);
                                  }
                                },
                              )
                            else
                              const SizedBox(height: 48),
                          ],
                        ),
                        Text(
                          context.l10n.diary.tagDefaultHint,
                          style: context
                              .theme
                              .typography
                              .bodySmall
                              .onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: tagsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          Text(context.l10n.diary.tagUpdateFailed),
                          TextButton(
                            onPressed: () => ref.invalidate(diaryTagsProvider),
                            child: Text(context.l10n.common.retry),
                          ),
                        ],
                      ),
                    ),
                    data: (tags) {
                      if (tags.isEmpty) {
                        return Center(
                          child: Text(context.l10n.diary.tagSortEmpty),
                        );
                      }
                      return Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.md,
                              vertical: spacing.sm,
                            ),
                            child: SearchBar(
                              controller: _searchController,
                              hintText: context.l10n.diary.tagSearchHint,
                              leading: const Icon(LucideIcons.search, size: 20),
                              constraints: const BoxConstraints(minHeight: 40),
                              elevation: const WidgetStatePropertyAll(0),
                              onChanged: (value) =>
                                  setState(() => _query = value),
                            ),
                          ),
                          if (_query.trim().isEmpty && !keyboardVisible)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                spacing.lg,
                                0,
                                spacing.lg,
                                spacing.xs,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  context.l10n.diary.tagSortHint,
                                  style: context
                                      .theme
                                      .typography
                                      .bodySmall
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (currentParent != null && _query.trim().isEmpty)
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.lg,
                                vertical: spacing.xs,
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '#$currentParent',
                                  key: const ValueKey('tag-manager-parent'),
                                  maxLines: 1,
                                  overflow: .ellipsis,
                                  style: context
                                      .theme
                                      .typography
                                      .bodyMedium
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          Expanded(
                            child: ValueListenableBuilder(
                              valueListenable: MoodiaryKVs.tagOrder
                                  .getNotifier(),
                              builder: (context, order, _) {
                                final draft = TagOrderDraft(tags, order);
                                final query = _query.trim().toLowerCase();
                                final paths = query.isEmpty
                                    ? draft.childrenOf(currentParent)
                                    : draft.paths
                                          .where(
                                            (path) => path
                                                .toLowerCase()
                                                .contains(query),
                                          )
                                          .toList();
                                if (paths.isEmpty) {
                                  return Center(
                                    child: Text(context.l10n.diary.tagNoMatch),
                                  );
                                }
                                Widget tile(BuildContext context, int index) {
                                  final path = paths[index];
                                  return _TagManagerTile(
                                    key: ValueKey('tag-manager-row:$path'),
                                    path: path,
                                    label: query.isEmpty
                                        ? path.split('/').last
                                        : path,
                                    count: counts?[path],
                                    isDefault: path == defaultTag,
                                    dragIndex: query.isEmpty ? index : null,
                                    onManage: () =>
                                        showTagActions(context, path),
                                    onChildren: draft.hasChildren(path)
                                        ? () => setState(() {
                                            _parent = path;
                                            _query = '';
                                            _searchController.clear();
                                            FocusScope.of(context).unfocus();
                                          })
                                        : null,
                                  );
                                }

                                if (query.isNotEmpty) {
                                  return ListView.builder(
                                    key: const ValueKey(
                                      'tag-manager-search-results',
                                    ),
                                    padding: EdgeInsets.only(
                                      bottom: spacing.sm,
                                    ),
                                    itemCount: paths.length,
                                    itemBuilder: tile,
                                  );
                                }
                                return ReorderableListView.builder(
                                  key: ValueKey(
                                    'tag-manager-list:$currentParent',
                                  ),
                                  padding: EdgeInsets.only(bottom: spacing.sm),
                                  buildDefaultDragHandles: false,
                                  itemCount: paths.length,
                                  onReorderItem: (oldIndex, newIndex) =>
                                      _reorder(
                                        tags,
                                        currentParent,
                                        paths,
                                        oldIndex,
                                        newIndex,
                                      ),
                                  itemBuilder: tile,
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagManagerTile extends StatelessWidget {
  final String path;
  final String label;
  final int? count;
  final bool isDefault;
  final int? dragIndex;
  final VoidCallback onManage;
  final VoidCallback? onChildren;

  const _TagManagerTile({
    super.key,
    required this.path,
    required this.label,
    required this.count,
    required this.isDefault,
    required this.dragIndex,
    required this.onManage,
    required this.onChildren,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final spacing = context.spacing;
    final tagTextStyle = context.theme.typography.bodyLarge.onSurface;
    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size(40, 48),
      maximumSize: const Size(40, 48),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Material(
      color: colors.surface,
      child: MInkWell(
        onTap: onManage,
        onLongPress: onManage,
        child: Padding(
          padding: EdgeInsets.only(left: spacing.sm, right: spacing.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                if (dragIndex case final index?)
                  ReorderableDragStartListener(
                    key: ValueKey('tag-manager-handle:$path'),
                    index: index,
                    child: Container(
                      width: 40,
                      height: 48,
                      color: Colors.transparent,
                      alignment: Alignment.center,
                      child: Icon(
                        LucideIcons.gripHorizontal,
                        size: 20,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  SizedBox(width: spacing.sm),
                Icon(
                  LucideIcons.hash,
                  size: tagTextStyle.fontSize,
                  applyTextScaling: true,
                  color: colors.onSurfaceVariant,
                ),
                SizedBox(width: spacing.sm),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: spacing.xs),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: tagTextStyle,
                    ),
                  ),
                ),
                if (isDefault)
                  Padding(
                    padding: EdgeInsets.only(left: spacing.sm),
                    child: Tooltip(
                      key: ValueKey('tag-manager-default:$path'),
                      message: context.l10n.diary.tagDefaultTitle,
                      child: Icon(
                        LucideIcons.star,
                        size: 16,
                        color: colors.primary,
                      ),
                    ),
                  ),
                if (count != null)
                  Padding(
                    padding: EdgeInsets.only(left: spacing.sm),
                    child: Text(
                      '$count',
                      style:
                          context.theme.typography.labelMedium.onSurfaceVariant,
                    ),
                  ),
                if (onChildren != null)
                  IconButton(
                    key: ValueKey('tag-manager-children:$path'),
                    tooltip: context.l10n.diary.tagChildren,
                    style: buttonStyle,
                    icon: const Icon(LucideIcons.chevronRight, size: 20),
                    onPressed: onChildren,
                  ),
                IconButton(
                  key: ValueKey('tag-manager-more:$path'),
                  tooltip: context.l10n.common.more,
                  style: buttonStyle,
                  icon: const Icon(LucideIcons.ellipsis, size: 20),
                  onPressed: onManage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
