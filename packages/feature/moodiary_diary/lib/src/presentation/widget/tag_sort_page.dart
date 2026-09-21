import 'package:flutter/services.dart';
import 'package:moodiary_diary/src/application/tag_order.dart';
import 'package:moodiary_i18n/moodiary_i18n.dart';
import 'package:mui/mui.dart';

Future<List<String>?> showTagSortPage(
  BuildContext context, {
  required List<String> tags,
  required List<String> initialOrder,
}) => Navigator.of(context).push<List<String>>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _TagSortPage(tags: tags, initialOrder: initialOrder),
  ),
);

class _TagSortPage extends StatefulWidget {
  final List<String> tags;
  final List<String> initialOrder;

  const _TagSortPage({required this.tags, required this.initialOrder});

  @override
  State<_TagSortPage> createState() => _TagSortPageState();
}

class _TagSortPageState extends State<_TagSortPage> {
  late final _draft = TagOrderDraft(widget.tags, widget.initialOrder);
  String? _parent;

  void _back() {
    if (_parent == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _parent = TagOrderDraft.parentOf(_parent!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final spacing = context.spacing;
    final children = _draft.childrenOf(_parent);
    return PopScope<List<String>>(
      canPop: _parent == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            key: const ValueKey('tag-sort-back'),
            onPressed: _back,
          ),
          title: Text(context.l10n.diary.tagSortTitle),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: spacing.md),
              child: FilledButton(
                key: const ValueKey('tag-sort-save'),
                onPressed: () => Navigator.of(context).pop(_draft.paths),
                child: Text(context.l10n.common.save),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              if (_parent != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.lg,
                    spacing.sm,
                    spacing.lg,
                    spacing.sm,
                  ),
                  child: Text(
                    '#$_parent',
                    key: const ValueKey('tag-sort-parent'),
                    style: context.theme.typography.bodyMedium.onSurfaceVariant,
                  ),
                ),
              Expanded(
                child: children.isEmpty
                    ? Center(child: Text(context.l10n.diary.tagSortEmpty))
                    : ReorderableListView.builder(
                        key: ValueKey('tag-sort-list:$_parent'),
                        padding: EdgeInsets.symmetric(vertical: spacing.sm),
                        buildDefaultDragHandles: false,
                        itemCount: children.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setState(
                            () => _draft.reorder(_parent, oldIndex, newIndex),
                          );
                          HapticFeedback.mediumImpact();
                        },
                        itemBuilder: (context, index) {
                          final path = children[index];
                          final hasChildren = _draft.hasChildren(path);
                          return ListTile(
                            key: ValueKey('tag-sort-row:$path'),
                            contentPadding: EdgeInsets.only(
                              left: spacing.sm,
                              right: spacing.md,
                            ),
                            leading: ReorderableDragStartListener(
                              key: ValueKey('tag-sort-handle:$path'),
                              index: index,
                              child: Container(
                                width: 48,
                                height: 48,
                                color: Colors.transparent,
                                alignment: Alignment.center,
                                child: Icon(
                                  LucideIcons.gripHorizontal,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Icon(
                                  LucideIcons.hash,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                                SizedBox(width: spacing.md),
                                Expanded(
                                  child: Text(
                                    path.split('/').last,
                                    maxLines: 1,
                                    overflow: .ellipsis,
                                    style: context
                                        .theme
                                        .typography
                                        .bodyLarge
                                        .onSurface,
                                  ),
                                ),
                              ],
                            ),
                            trailing: hasChildren
                                ? Icon(
                                    LucideIcons.chevronRight,
                                    size: 20,
                                    color: colors.onSurfaceVariant,
                                  )
                                : null,
                            onTap: hasChildren
                                ? () => setState(() => _parent = path)
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
