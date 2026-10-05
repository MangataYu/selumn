import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_components/moodiary_components.dart';
import 'package:moodiary_models/moodiary_models.dart';

import 'support/pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('packages/mui/NotoEmoji')
      ..addFont(rootBundle.load('packages/mui/assets/fonts/NotoEmoji.ttf'));
    await loader.load();
  });

  testWidgets(
    'all selectable moods use the bundled Noto Emoji font and mood colors',
    (tester) async {
      await tester.pumpWidget(
        muiTestApp(
          Wrap(
            children: [
              for (final mood in DiaryMood.selectableValues)
                MoodIconComponent(mood: mood),
            ],
          ),
        ),
      );

      for (final mood in DiaryMood.selectableValues) {
        expect(mood.emoji, isNotNull, reason: mood.name);
        expect(find.text(mood.emoji!), findsOneWidget);
        final text = tester.widget<Text>(find.text(mood.emoji!));
        expect(text.style!.fontFamily, 'packages/mui/NotoEmoji');
        expect(text.style!.fontFamilyFallback, isNull);
        expect(text.style!.fontWeight, FontWeight.w400);
        expect(text.style!.color, mood.color);
      }
      expect(find.byType(Icon), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the full font advance fits inside each fixed mood icon slot', (
    tester,
  ) async {
    const iconSize = 18.0;
    await tester.pumpWidget(
      muiTestApp(
        Wrap(
          children: [
            for (final mood in DiaryMood.selectableValues)
              MoodIconComponent(
                key: ValueKey(mood),
                mood: mood,
                size: iconSize,
              ),
          ],
        ),
      ),
    );

    final faceAdvances = <DiaryMood, double>{};
    for (final mood in DiaryMood.selectableValues) {
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: mood.emoji,
          style: const TextStyle(
            fontFamily: 'NotoEmoji',
            package: 'mui',
            fontWeight: FontWeight.w400,
            fontSize: iconSize,
          ),
        ),
      )..layout();
      try {
        faceAdvances[mood] = painter.width;
        // The bundled font's advance exceeds its nominal font size. Laying
        // the paragraph out at iconSize would clip the right side of the face.
        expect(painter.width, greaterThan(iconSize), reason: mood.name);
        final icon = find.byKey(ValueKey(mood));
        final slot = tester.renderObject<RenderBox>(icon);
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: icon, matching: find.byType(RichText)),
        );
        expect(slot.size, const Size.square(iconSize));
        expect(paragraph.size.width, closeTo(painter.width, 0.01));
        expect(paragraph.size.height, closeTo(painter.height, 0.01));

        final topLeft = paragraph.localToGlobal(Offset.zero, ancestor: slot);
        final bottomRight = paragraph.localToGlobal(
          paragraph.size.bottomRight(Offset.zero),
          ancestor: slot,
        );
        expect(topLeft.dx, greaterThanOrEqualTo(-0.01));
        expect(topLeft.dy, greaterThanOrEqualTo(-0.01));
        expect(bottomRight.dx, lessThanOrEqualTo(iconSize + 0.01));
        expect(bottomRight.dy, lessThanOrEqualTo(iconSize + 0.01));
      } finally {
        painter.dispose();
      }
    }
    // The ZWJ sequence must shape as one face rather than a face plus a puff.
    expect(
      faceAdvances[DiaryMood.relieved],
      closeTo(faceAdvances[DiaryMood.neutral]!, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy activities retain their colored Lucide icons', (
    tester,
  ) async {
    for (final mood in DiaryMood.values.where((mood) => !mood.isSelectable)) {
      expect(mood.emoji, isNull, reason: mood.name);
    }
    await tester.pumpWidget(
      muiTestApp(const MoodIconComponent(mood: .work, size: 18)),
    );

    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.briefcase));
    expect(icon.color, DiaryMood.work.color);
    expect(icon.size, 18);
  });

  testWidgets(
    'emoji keep their size, font and mood color under custom styles',
    (tester) async {
      await tester.pumpWidget(
        muiTestApp(
          const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: DefaultTextStyle(
              style: TextStyle(
                fontFamily: 'DiaryCustomFont',
                fontSize: 48,
                color: Color(0xFFFF0000),
                fontWeight: FontWeight.w900,
                fontVariations: [FontVariation('wght', 900)],
                height: 2,
                letterSpacing: 8,
              ),
              child: Center(
                child: MoodIconComponent(mood: .positive, size: 18),
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(MoodIconComponent)),
        const Size.square(18),
      );
      final paragraph = tester.widget<RichText>(
        find.descendant(
          of: find.byType(MoodIconComponent),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.text.style!.fontFamily, 'packages/mui/NotoEmoji');
      expect(paragraph.text.style!.fontWeight, FontWeight.w400);
      expect(paragraph.text.style!.fontVariations, const [
        FontVariation('wght', 400),
      ]);
      expect(paragraph.text.style!.height, isNull);
      expect(paragraph.text.style!.letterSpacing, isNull);
      expect(paragraph.text.style!.color, DiaryMood.positive.color);
      expect(paragraph.textScaler.scale(18), 18);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'emoji semantics use the localized mood rather than Unicode names',
    (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          muiTestApp(const MoodIconComponent(mood: .positive)),
        );

        expect(find.bySemanticsLabel('开心'), findsOneWidget);
        expect(find.bySemanticsLabel('😊'), findsNothing);
      } finally {
        handle.dispose();
      }
    },
  );

  testWidgets('decorative mood emoji render without a localization provider', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.noScaling),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: MoodIconComponent(
                mood: .relieved,
                size: 18,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('😮‍💨'), findsOneWidget);
      final text = tester.widget<Text>(find.text('😮‍💨'));
      expect(text.style!.fontFamily, 'packages/mui/NotoEmoji');
      expect(text.style!.color, DiaryMood.relieved.color);
      expect(find.bySemanticsLabel('😮‍💨'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });
}
