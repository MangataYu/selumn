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
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(diaryTagsProvider);
    final counts = ref.watch(tagDiaryCountsProvider).value?.byTag;
    final spacing = context.spacing;
    final tagTextStyle = context.theme.typography.bodyMedium.onSurface;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.diary.tagManagerTitle),
        actions: [
          IconButton(
            key: const ValueKey('tag-manager-sort'),
            tooltip: context.l10n.diary.tagSortTitle,
            icon: const Icon(LucideIcons.slidersHorizontal),
            onPressed:
                tagsAsync.hasError || !(tagsAsync.value?.isNotEmpty ?? false)
                ? null
                : () => showTagSorting(context, tagsAsync.requireValue),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder(
          valueListenable: MoodiaryKVs.defaultTag.getNotifier(),
          builder: (context, defaultTag, _) => Column(
            children: [
              ListTile(
                title: Text(context.l10n.diary.tagDefaultTitle),
                subtitle: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      defaultTag.isEmpty
                          ? context.l10n.diary.tagDefaultNone
                          : '#$defaultTag',
                    ),
                    Text(context.l10n.diary.tagDefaultHint),
                  ],
                ),
                trailing: defaultTag.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey('tag-manager-clear-default'),
                        tooltip: context.l10n.diary.tagClearDefault,
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () {
                          try {
                            ref.read(tagManagementProvider).setDefaultTag('');
                          } catch (_) {
                            toast.error(message: l10n.diary.saveFailed);
                          }
                        },
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
                          padding: .fromLTRB(
                            spacing.md,
                            spacing.sm,
                            spacing.md,
                            spacing.sm,
                          ),
                          child: SearchBar(
                            hintText: context.l10n.diary.tagSearchHint,
                            leading: const Icon(LucideIcons.search, size: 20),
                            constraints: const BoxConstraints(minHeight: 40),
                            elevation: const WidgetStatePropertyAll(0),
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                        ),
                        Expanded(
                          child: ValueListenableBuilder(
                            valueListenable: MoodiaryKVs.tagOrder.getNotifier(),
                            builder: (context, order, _) {
                              final query = _query.trim().toLowerCase();
                              final paths = orderedTagPaths(tags, order)
                                  .where(
                                    (path) =>
                                        path.toLowerCase().contains(query),
                                  )
                                  .toList();
                              if (paths.isEmpty) {
                                return Center(
                                  child: Text(context.l10n.diary.tagNoMatch),
                                );
                              }
                              return ListView.builder(
                                padding: .only(bottom: spacing.sm),
                                itemCount: paths.length,
                                itemBuilder: (context, index) {
                                  final path = paths[index];
                                  final depth = query.isEmpty
                                      ? path.split('/').length - 1
                                      : 0;
                                  final count = counts?[path];
                                  void manage() =>
                                      showTagActions(context, path);
                                  return ListTile(
                                    key: ValueKey('tag-manager-row:$path'),
                                    minTileHeight: 48,
                                    minVerticalPadding: 0,
                                    contentPadding: .only(
                                      left:
                                          spacing.lg +
                                          depth.clamp(0, 4) * spacing.md,
                                      right: spacing.sm,
                                    ),
                                    leading: Icon(
                                      LucideIcons.hash,
                                      size: tagTextStyle.fontSize,
                                      applyTextScaling: true,
                                    ),
                                    minLeadingWidth: 0,
                                    horizontalTitleGap: spacing.sm,
                                    title: Text(
                                      query.isEmpty
                                          ? path.split('/').last
                                          : path,
                                      maxLines: 1,
                                      overflow: .ellipsis,
                                      style: tagTextStyle,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: .min,
                                      children: [
                                        if (path == defaultTag)
                                          Padding(
                                            padding: .only(right: spacing.sm),
                                            child: Tooltip(
                                              key: ValueKey(
                                                'tag-manager-default:$path',
                                              ),
                                              message: context
                                                  .l10n
                                                  .diary
                                                  .tagDefaultTitle,
                                              child: Icon(
                                                LucideIcons.star,
                                                size: 16,
                                                color: context
                                                    .theme
                                                    .colors
                                                    .primary,
                                              ),
                                            ),
                                          ),
                                        if (count != null)
                                          Text(
                                            '$count',
                                            style: context
                                                .theme
                                                .typography
                                                .labelMedium
                                                .onSurfaceVariant,
                                          ),
                                        IconButton(
                                          key: ValueKey(
                                            'tag-manager-more:$path',
                                          ),
                                          tooltip: context.l10n.common.more,
                                          icon: const Icon(
                                            LucideIcons.ellipsis,
                                            size: 20,
                                          ),
                                          onPressed: manage,
                                        ),
                                      ],
                                    ),
                                    onTap: manage,
                                    onLongPress: manage,
                                  );
                                },
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
    );
  }
}
