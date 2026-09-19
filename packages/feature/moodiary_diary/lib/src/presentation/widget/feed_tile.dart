import 'package:fast_image/fast_image.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_diary/src/application/diary_stamp.dart';
import 'package:moodiary_diary/src/presentation/widget/diary_tile_frame.dart';
import 'package:moodiary_files/moodiary_files.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_utils/moodiary_utils.dart';
import 'package:mui/mui.dart';

const int _kMaxCells = 3;
const double _kCellGap = 6.0;

class _Cell {
  final String name;
  final bool isVideo;

  const _Cell(this.name, {this.isVideo = false});

  String get path =>
      AppFiles.getRealPath(isVideo ? 'thumbnail' : 'image', name);
}

List<_Cell> _cellsOf(Diary diary) => [
  for (final n in diary.videoName) _Cell(n, isVideo: true),
  for (final n in diary.imageName) _Cell(n),
];

class DiaryFeedTile extends StatelessWidget {
  final Diary diary;

  final DiarySort sort;
  final Category? category;
  final Place? place;
  final bool showCategoryLabel;
  final DiaryCardSyncState syncState;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;

  const DiaryFeedTile({
    super.key,
    required this.diary,
    this.sort = .timeDesc,
    this.category,
    this.place,
    this.showCategoryLabel = true,
    this.syncState = .none,
    this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final cells = _cellsOf(diary);
    final stamp = diaryStampOf(diary, sort);
    final title = diary.title.trim();
    // Keep paragraphs while bounding work for unusually long imported notes.
    final bodyRunes = diary.contentText.trim().runes.take(1601).toList();
    final body = bodyRunes.length > 1600
        ? '${String.fromCharCodes(bodyRunes.take(1600)).trimRight()}…'
        : String.fromCharCodes(bodyRunes);

    return DiaryTileFrame(
      selecting: selecting,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      card: true,
      borderRadius: AppBorderRadius.largeBorderRadius,
      margin: const .symmetric(horizontal: 16),
      padding: const .all(16),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Padding(
            padding: .only(right: selecting ? 20 : 0),
            child: _MetaLine(
              diary: diary,
              stamp: stamp,
              category: category,
              place: place,
              showCategoryLabel: showCategoryLabel,
              syncState: syncState,
            ),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: .ellipsis,
              style: context.theme.typography.titleSmall.emphasized.onSurface
                  .copyWith(height: 1.4),
            ),
          ],
          if (body.isNotEmpty) ...[
            SizedBox(height: title.isEmpty ? 10 : 6),
            Text(
              body,
              maxLines: 8,
              overflow: .ellipsis,
              style: context.theme.typography.bodyMedium.onSurface.copyWith(
                height: 1.65,
              ),
            ),
          ],
          if (cells.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Strip(
              cells: cells,
              aspect: diary.aspect,
              pending: syncState == .syncing,
            ),
          ],
          if (diary.audioName.isNotEmpty) ...[
            const SizedBox(height: 12),
            _AudioBar(count: diary.audioName.length),
          ],
          if (diary.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [for (final tag in diary.tags) _TagChip(label: tag)],
            ),
          ],
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  final List<_Cell> cells;
  final double? aspect;
  final bool pending;

  const _Strip({
    required this.cells,
    required this.aspect,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final show = cells.length > _kMaxCells ? _kMaxCells : cells.length;
    final extra = cells.length - show;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) return const SizedBox.shrink();
        if (show == 1) {
          final ratio = (aspect ?? 16 / 10).clamp(0.7, 2.0).toDouble();
          final boxWidth = (ratio < 1 ? 160.0 : 224.0)
              .clamp(0.0, width)
              .toDouble();
          return SizedBox(
            width: boxWidth,
            height: boxWidth / ratio,
            child: _Thumb(
              cell: cells.first,
              decodeWidth: (boxWidth * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              radius: AppBorderRadius.mediumBorderRadius,
              pending: pending,
            ),
          );
        }
        final cell = (width - _kCellGap * (_kMaxCells - 1)) / _kMaxCells;
        return SizedBox(
          height: cell,
          child: Row(
            children: [
              for (var i = 0; i < show; i++) ...[
                if (i > 0) const SizedBox(width: _kCellGap),
                SizedBox(
                  width: cell,
                  child: _Thumb(
                    cell: cells[i],
                    radius: const .all(.circular(10)),
                    moreCount: i == show - 1 && extra > 0 ? extra : 0,
                    pending: pending,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Thumb extends StatelessWidget {
  final _Cell cell;

  final int? decodeWidth;
  final BorderRadius radius;
  final int moreCount;

  final bool pending;

  const _Thumb({
    required this.cell,
    this.decodeWidth,
    required this.radius,
    this.moreCount = 0,
    this.pending = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: .expand,
        children: [
          ColoredBox(color: colors.surfaceContainerHighest),
          Image(
            // key 需含 pending：gaplessPlayback 下 Element 复用会先画上一篇的照片
            key: ValueKey('${cell.path}#$pending'),
            // 视频封面不走派生档位，派生物只给原件算
            image: FastImage(
              cell.path,
              tier: cell.isVideo
                  ? null
                  : FastImageTier.fit(decodeWidth ?? FastImageTier.s.width),
              decodeWidth: decodeWidth,
            ),
            fit: .cover,
            gaplessPlayback: true,
            // 重装后媒体文件会被清空而日记还在，没有 errorBuilder 就是一片空白
            errorBuilder: (context, _, _) => pending
                ? const SizedBox.shrink()
                : Icon(LucideIcons.imageOff, color: colors.onSurfaceVariant),
          ),
          if (cell.isVideo) const _VideoScrim(),
          if (moreCount > 0) _MoreOverlay(count: moreCount),
        ],
      ),
    );
  }
}

class _VideoScrim extends StatelessWidget {
  const _VideoScrim();

  @override
  Widget build(BuildContext context) {
    final scrim = context.theme.colors.scrim;
    return Stack(
      fit: .expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: .bottomCenter,
              end: .topCenter,
              colors: [scrim.withValues(alpha: 0.54), Colors.transparent],
              stops: const [0, 0.58],
            ),
          ),
        ),
        Positioned(
          left: 4,
          bottom: 3,
          child: Icon(
            LucideIcons.circlePlay,
            size: 14,
            color: context.theme.onMedia,
          ),
        ),
      ],
    );
  }
}

class _MoreOverlay extends StatelessWidget {
  final int count;

  const _MoreOverlay({required this.count});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.theme.colors.scrim.withValues(alpha: 0.44),
      ),
      child: Center(
        child: Text(
          '+$count',
          style: context.theme.typography.labelLarge.emphasized.onMedia,
        ),
      ),
    );
  }
}

class _AudioBar extends StatelessWidget {
  final int count;

  const _AudioBar({required this.count});

  static const List<double> _pattern = [
    4,
    6,
    8,
    12,
    6,
    4,
    8,
    10,
    5,
    12,
    7,
    4,
    9,
    6,
    11,
    5,
    8,
    4,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return Container(
      height: 22,
      width: 188,
      padding: const .symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: const .all(.circular(11)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.mic, size: 12, color: colors.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Row(
              mainAxisAlignment: .spaceBetween,
              crossAxisAlignment: .center,
              children: [
                for (final h in _pattern)
                  Container(
                    width: 2,
                    height: h,
                    decoration: BoxDecoration(
                      color: .lerp(colors.outlineVariant, colors.primary, 0.52),
                      borderRadius: const .all(.circular(1)),
                    ),
                  ),
              ],
            ),
          ),
          if (count > 1) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: context.theme.typography.labelSmall.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final Diary diary;
  final DateTime stamp;
  final Category? category;
  final Place? place;
  final bool showCategoryLabel;
  final DiaryCardSyncState syncState;

  const _MetaLine({
    required this.diary,
    required this.stamp,
    required this.category,
    required this.place,
    required this.showCategoryLabel,
    required this.syncState,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final onVariant = colors.onSurfaceVariant;
    final style = context.theme.typography.labelMedium.onSurfaceVariant;
    final weather = diary.weather;
    final placeName = place?.name.trim() ?? '';

    InlineSpan icon(IconData data) => WidgetSpan(
      alignment: .middle,
      child: Padding(
        padding: const .only(right: 3),
        child: Icon(data, size: 11.5, color: onVariant),
      ),
    );
    const dot = TextSpan(text: '  ·  ');

    final spans = <InlineSpan>[
      WidgetSpan(
        alignment: .middle,
        child: Padding(
          padding: const .only(right: 7),
          child: Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: diaryMoodColor(diary.mood),
              shape: .circle,
            ),
          ),
        ),
      ),
      TextSpan(text: TimeFormat.compactDateTime(stamp)),
      if (showCategoryLabel && category != null) ...[
        dot,
        WidgetSpan(
          alignment: .middle,
          child: Padding(
            padding: const .only(right: 4),
            child: _CategoryDot(category: category!),
          ),
        ),
        TextSpan(text: category!.categoryName),
      ],
      if (weather != null) ...[
        dot,
        icon(qweatherIcon(weather.icon) ?? LucideIcons.cloud),
        TextSpan(text: weather.compactText),
      ],
      if (placeName.isNotEmpty) ...[
        dot,
        icon(LucideIcons.mapPin),
        TextSpan(text: placeName),
      ],
    ];

    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(children: spans),
            maxLines: 2,
            overflow: .ellipsis,
            style: style,
          ),
        ),
        if (syncState != .none) ...[
          const SizedBox(width: 6),
          DiarySyncBadge(state: syncState),
        ],
      ],
    );
  }
}

class _CategoryDot extends StatelessWidget {
  final Category category;

  const _CategoryDot({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: categoryColorOf(colorValue: category.color, id: category.id),
        shape: .circle,
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;

  const _TagChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text('#$label', style: context.theme.typography.labelMedium.primary);
  }
}
