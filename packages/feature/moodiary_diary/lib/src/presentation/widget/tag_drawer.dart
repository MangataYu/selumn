import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:moodiary_data/moodiary_data.dart';
import 'package:moodiary_diary/src/application/diary_filter.dart';
import 'package:moodiary_diary/src/application/diary_selection.dart';
import 'package:moodiary_diary/src/application/tag_order.dart';
import 'package:moodiary_diary/src/presentation/widget/tag_actions.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:moodiary_router/moodiary_router.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

const _maxTagIndentDepth = 4;
const _tagRowHeight = 40.0;
const _tagIconSize = 16.0;

class TagDrawer extends ConsumerStatefulWidget {
  final Widget? overview;
  final Widget? navigation;
  final Widget? afterDiary;
  final VoidCallback? onFilterSelected;
  final bool isDiarySelected;

  const TagDrawer({
    super.key,
    this.overview,
    this.navigation,
    this.afterDiary,
    this.onFilterSelected,
    this.isDiarySelected = true,
  });

  @override
  ConsumerState<TagDrawer> createState() => _TagDrawerState();
}

class _TagDrawerState extends ConsumerState<TagDrawer> {
  String _query = '';
  bool _searchVisible = false;
  late bool _filtersExpanded = MoodiaryKVs.diaryFiltersExpanded.get()!;
  late bool _tagsExpanded = MoodiaryKVs.tagTreeExpanded.get()!;
  late final _tagOrderListenable = MoodiaryKVs.tagOrder.getNotifier();
  late final _expandedPathsListenable = MoodiaryKVs.expandedTagPaths
      .getNotifier();

  List<String> get _tagOrder => _tagOrderListenable.value;
  Set<String> get _expandedPaths => _expandedPathsListenable.value.toSet();

  @override
  void initState() {
    super.initState();
    _tagOrderListenable.addListener(_onTagPreferencesChanged);
    _expandedPathsListenable.addListener(_onTagPreferencesChanged);
  }

  @override
  void dispose() {
    _tagOrderListenable.removeListener(_onTagPreferencesChanged);
    _expandedPathsListenable.removeListener(_onTagPreferencesChanged);
    super.dispose();
  }

  void _onTagPreferencesChanged() => setState(() {});

  void _toggleFilters() {
    final expanded = !_filtersExpanded;
    MoodiaryKVs.diaryFiltersExpanded.set(expanded);
    setState(() => _filtersExpanded = expanded);
  }

  void _toggleTags() {
    final expanded = !_tagsExpanded;
    MoodiaryKVs.tagTreeExpanded.set(expanded);
    if (!expanded) FocusScope.of(context).unfocus();
    setState(() {
      _tagsExpanded = expanded;
      if (!expanded) {
        _searchVisible = false;
        _query = '';
      }
    });
  }

  void _saveExpandedPaths(Set<String> paths) {
    MoodiaryKVs.expandedTagPaths.set(paths.toList()..sort());
  }

  void _toggleExpanded(String path) {
    final paths = {..._expandedPaths};
    // Keep descendant states so reopening a parent restores its subtree.
    if (!paths.remove(path)) paths.add(path);
    _saveExpandedPaths(paths);
  }

  void _pick(DiaryFilter filter) {
    ref.read(diarySelectionProvider.notifier).clear();
    ref.read(homeDiaryFilterProvider.notifier).select(filter);
    Navigator.of(context).pop();
    widget.onFilterSelected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final spacing = context.spacing;
    final filter = ref.watch(homeDiaryFilterProvider);
    final tagsAsync = ref.watch(diaryTagsProvider);
    final tags = tagsAsync.value ?? const <String>[];
    final paths = orderedTagPaths(tags, _tagOrder);
    final ancestorsByPath = {
      for (final path in paths) path: TagPath.ancestors(path)..removeLast(),
    };
    final parentPaths = ancestorsByPath.values.expand((paths) => paths).toSet();
    final counts = ref.watch(tagDiaryCountsProvider).value;
    final query = _query.trim().toLowerCase();
    final visible = paths
        .where(
          (path) => query.isEmpty
              ? ancestorsByPath[path]!.every(_expandedPaths.contains)
              : path.toLowerCase().contains(query),
        )
        .toList();
    final localizations = MaterialLocalizations.of(context);
    final compactButtonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(_tagRowHeight),
      fixedSize: const Size.square(_tagRowHeight),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );

    Widget expandButton({
      required Key key,
      required bool expanded,
      required bool selected,
      required VoidCallback onPressed,
    }) => Semantics(
      expanded: expanded,
      child: IconButton(
        key: key,
        tooltip: expanded
            ? localizations.expandedIconTapHint
            : localizations.collapsedIconTapHint,
        padding: EdgeInsets.zero,
        style: compactButtonStyle,
        icon: Icon(
          expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
          size: _tagIconSize,
          color: selected
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
        onPressed: onPressed,
      ),
    );

    Widget tagTile(int index) {
      final path = visible[index];
      final ancestors = ancestorsByPath[path]!;
      final next = index + 1 < visible.length ? visible[index + 1] : null;
      final expandable = query.isEmpty && parentPaths.contains(path);
      final expanded = _expandedPaths.contains(path);
      final selected = widget.isDiarySelected && filter.tagPath == path;
      return _TagTile(
        key: ValueKey('tag-row:$path'),
        label: query.isEmpty ? path.split('/').last : path,
        count: counts == null ? null : counts.byTag[path] ?? 0,
        depth: query.isEmpty ? ancestors.length : 0,
        guideEnds: query.isEmpty
            ? [
                for (final ancestor in ancestors.take(_maxTagIndentDepth))
                  next == null || !TagPath.matches(next, ancestor),
              ]
            : const [],
        showChildGuide: expandable && expanded,
        selected: selected,
        icon: LucideIcons.hash,
        onTap: () => _pick(.tag(path)),
        onLongPress: () => showTagActions(context, path),
        trailing: expandable
            ? expandButton(
                key: ValueKey('tag-expand:$path'),
                expanded: expanded,
                selected: selected,
                onPressed: () => _toggleExpanded(path),
              )
            : null,
      );
    }

    Widget filterTile({
      required String key,
      required String label,
      required IconData icon,
      required DiaryFilter value,
      int? count,
      bool last = false,
    }) => _TagTile(
      key: ValueKey(key),
      label: label,
      count: count,
      depth: 1,
      guideEnds: [last],
      selected: widget.isDiarySelected && filter == value,
      icon: icon,
      onTap: () => _pick(value),
    );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: .only(
            bottom: spacing.sm + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            Padding(
              key: const ValueKey('tag-drawer-header'),
              padding: .fromLTRB(spacing.lg, spacing.xs, 8, spacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          context.l10n.common.appName,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: context
                              .theme
                              .typography
                              .titleMedium
                              .emphasized
                              .onSurface,
                        ),
                        if (counts != null && widget.overview == null)
                          Text(
                            context.l10n.diary.searchResult(
                              count: counts.total,
                            ),
                            style: context
                                .theme
                                .typography
                                .labelMedium
                                .onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('tag-drawer-settings'),
                    tooltip: context.l10n.app.homeNavigatorSetting,
                    style: compactButtonStyle,
                    icon: const Icon(LucideIcons.settings, size: 18),
                    onPressed: () {
                      Navigator.of(context).pop();
                      const SettingRoute().push(context);
                    },
                  ),
                ],
              ),
            ),
            if (widget.overview != null) widget.overview!,
            if (widget.navigation != null) widget.navigation!,
            _TagTile(
              key: const ValueKey('all-diaries-row'),
              label: context.l10n.app.homeNavigatorDiary,
              count: counts?.total,
              selected: widget.isDiarySelected && filter.isAll,
              icon: LucideIcons.notebookPen,
              onTap: () => _pick(const .all()),
              showChildGuide: _filtersExpanded,
              trailing: expandButton(
                key: const ValueKey('all-diaries-expand'),
                expanded: _filtersExpanded,
                selected: widget.isDiarySelected && filter.isAll,
                onPressed: _toggleFilters,
              ),
            ),
            if (_filtersExpanded) ...[
              filterTile(
                key: 'filter-untagged',
                label: context.l10n.diary.tagNoTag,
                count: counts?.untagged,
                icon: LucideIcons.tag,
                value: const .untagged(),
              ),
              filterTile(
                key: 'filter-images',
                label: context.l10n.diary.filterImages,
                icon: LucideIcons.image,
                value: const .images(),
              ),
              filterTile(
                key: 'filter-links',
                label: context.l10n.diary.filterLinks,
                icon: LucideIcons.link,
                value: const .links(),
              ),
              filterTile(
                key: 'filter-audio',
                label: context.l10n.diary.filterAudio,
                icon: LucideIcons.audioLines,
                value: const .audio(),
                last: true,
              ),
            ],
            if (widget.afterDiary != null) widget.afterDiary!,
            Padding(
              padding: .symmetric(vertical: spacing.xs),
              child: Divider(
                height: 1,
                indent: spacing.lg,
                endIndent: 8,
                color: colors.outlineVariant,
              ),
            ),
            Semantics(
              expanded: _tagsExpanded,
              child: _TagTile(
                key: const ValueKey('tags-row'),
                label: context.l10n.common.tag,
                count: null,
                selected: widget.isDiarySelected && filter.tagPath != null,
                icon: LucideIcons.tags,
                onTap: _toggleTags,
                trailing: expandButton(
                  key: const ValueKey('tags-expand'),
                  expanded: _tagsExpanded,
                  selected: widget.isDiarySelected && filter.tagPath != null,
                  onPressed: _toggleTags,
                ),
              ),
            ),
            if (_tagsExpanded) ...[
              Padding(
                padding: .only(left: spacing.lg, right: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.common.tagCount(count: tags.length),
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: context
                              .theme
                              .typography
                              .labelMedium
                              .onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('tag-manager-button'),
                        tooltip: context.l10n.diary.tagManagerTitle,
                        style: compactButtonStyle,
                        icon: const Icon(
                          LucideIcons.slidersHorizontal,
                          size: _tagIconSize,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          const TagManagerRoute().push(context);
                        },
                      ),
                      SizedBox(
                        width: _tagRowHeight,
                        child: paths.length >= 8 || _searchVisible
                            ? Semantics(
                                expanded: _searchVisible,
                                child: IconButton(
                                  key: const ValueKey('tag-search-toggle'),
                                  tooltip: _searchVisible
                                      ? context.l10n.common.cancel
                                      : context.l10n.diary.tagSearchHint,
                                  style: compactButtonStyle,
                                  icon: Icon(
                                    _searchVisible
                                        ? LucideIcons.x
                                        : LucideIcons.search,
                                    size: _tagIconSize,
                                  ),
                                  onPressed: () {
                                    if (_searchVisible) {
                                      FocusScope.of(context).unfocus();
                                    }
                                    setState(() {
                                      _searchVisible = !_searchVisible;
                                      if (!_searchVisible) _query = '';
                                    });
                                  },
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              if (_searchVisible)
                Padding(
                  padding: .fromLTRB(spacing.sm, 0, 8, spacing.xs),
                  child: SearchBar(
                    autoFocus: true,
                    hintText: context.l10n.diary.tagSearchHint,
                    leading: const Icon(LucideIcons.search, size: _tagIconSize),
                    constraints: const BoxConstraints(minHeight: _tagRowHeight),
                    textStyle: WidgetStatePropertyAll(
                      context.theme.typography.bodyMedium.onSurface,
                    ),
                    elevation: const WidgetStatePropertyAll(0),
                    backgroundColor: WidgetStatePropertyAll(
                      colors.surfaceContainerHigh,
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              for (var i = 0; i < visible.length; i++) tagTile(i),
              if (visible.isEmpty && query.isNotEmpty)
                Padding(
                  padding: .all(spacing.md),
                  child: Text(context.l10n.diary.tagNoMatch),
                ),
              if (tagsAsync.hasError)
                Padding(
                  padding: .all(spacing.md),
                  child: Text(context.l10n.diary.tagUpdateFailed),
                ),
            ],
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
  final Widget? trailing;
  final List<bool> guideEnds;
  final bool showChildGuide;

  const _TagTile({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.depth = 0,
    this.onLongPress,
    this.trailing,
    this.guideEnds = const [],
    this.showChildGuide = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final spacing = context.spacing;
    return CustomPaint(
      foregroundPainter: guideEnds.isNotEmpty || showChildGuide
          ? _TagGuidesPainter(
              depth: depth,
              guideEnds: guideEnds,
              showChildGuide: showChildGuide,
              color: colors.outlineVariant,
              iconCenter: spacing.sm * 2 + _tagIconSize / 2,
              indent: spacing.lg,
            )
          : null,
      child: Semantics(
        selected: selected,
        child: Padding(
          padding: .only(left: spacing.sm, right: 8),
          child: Material(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: MuiRadius.sm,
            clipBehavior: .antiAlias,
            child: MInkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: .only(
                  left:
                      spacing.sm +
                      depth.clamp(0, _maxTagIndentDepth) * spacing.lg,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: _tagRowHeight),
                  child: Row(
                    children: [
                      Icon(
                        icon,
                        size: _tagIconSize,
                        color: selected
                            ? colors.onSecondaryContainer
                            : colors.onSurfaceVariant,
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: Padding(
                          padding: .symmetric(vertical: spacing.xs),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: selected
                                ? context
                                      .theme
                                      .typography
                                      .bodyMedium
                                      .onSecondaryContainer
                                : context.theme.typography.bodyMedium.onSurface,
                          ),
                        ),
                      ),
                      if (count != null) ...[
                        SizedBox(width: spacing.sm),
                        Text(
                          '$count',
                          textAlign: .right,
                          style: selected
                              ? context
                                    .theme
                                    .typography
                                    .labelMedium
                                    .onSecondaryContainer
                              : context
                                    .theme
                                    .typography
                                    .labelMedium
                                    .onSurfaceVariant,
                        ),
                      ],
                      SizedBox(width: _tagRowHeight, child: trailing),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagGuidesPainter extends CustomPainter {
  final int depth;
  final List<bool> guideEnds;
  final bool showChildGuide;
  final Color color;
  final double iconCenter;
  final double indent;

  const _TagGuidesPainter({
    required this.depth,
    required this.guideEnds,
    required this.showChildGuide,
    required this.color,
    required this.iconCenter,
    required this.indent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 0; level < guideEnds.length; level++) {
      final x = iconCenter + level * indent;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, guideEnds[level] ? size.height / 2 : size.height),
        paint,
      );
    }
    if (showChildGuide && depth < _maxTagIndentDepth) {
      final x = iconCenter + depth * indent;
      canvas.drawLine(
        Offset(x, size.height / 2 + _tagIconSize / 2 + 2),
        Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TagGuidesPainter oldDelegate) =>
      depth != oldDelegate.depth ||
      showChildGuide != oldDelegate.showChildGuide ||
      color != oldDelegate.color ||
      iconCenter != oldDelegate.iconCenter ||
      indent != oldDelegate.indent ||
      !listEquals(guideEnds, oldDelegate.guideEnds);
}
