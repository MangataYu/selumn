import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_models/moodiary_models.dart';

class MoodIconComponent extends StatelessWidget {
  const MoodIconComponent({
    super.key,
    required this.mood,
    this.size = 24.0,
    this.excludeFromSemantics = false,
  });

  final DiaryMood mood;

  final double size;

  /// Use when an adjacent label already describes the mood.
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final emoji = mood.emoji;
    final visual = ExcludeSemantics(
      child: emoji == null
          ? Icon(mood.icon, color: mood.color, size: size)
          : SizedBox.square(
              dimension: size,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Text(
                  emoji,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    inherit: false,
                    fontFamily: 'NotoEmoji',
                    package: 'mui',
                    fontWeight: FontWeight.w400,
                    color: mood.color,
                    fontSize: size,
                  ),
                ),
              ),
            ),
    );
    if (excludeFromSemantics) return visual;
    return Semantics(label: mood.label(context), image: true, child: visual);
  }
}
