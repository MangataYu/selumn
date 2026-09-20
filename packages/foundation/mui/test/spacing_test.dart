import 'package:flutter_test/flutter_test.dart';
import 'package:mui/mui.dart';

void main() {
  test('responsive spacing stays bounded while touch targets stay fixed', () {
    const base = MuiSpacing();
    final widths = <double>[240, 320, 390, 430, 768, 1920];
    double previous = 0;
    for (final width in widths) {
      final spacing = base.forWidth(width);
      expect(spacing.pagePadding.left, inInclusiveRange(10, 16));
      expect(spacing.pagePadding.left, greaterThanOrEqualTo(previous));
      expect(spacing.minTapTarget, 48);
      previous = spacing.pagePadding.left;
    }
    expect(base.forWidth(390), base);
    expect(base.forWidth(768), base.forWidth(1920));
  });

  test('custom theme spacing is scaled without changing its touch target', () {
    const base = MuiSpacing(
      md: 18,
      pagePadding: EdgeInsets.fromLTRB(12, 6, 24, 9),
      minTapTarget: 56,
    );
    final compact = base.forWidth(320);
    expect(compact.md, closeTo(15, 0.001));
    expect(compact.pagePadding, const EdgeInsets.fromLTRB(10, 5, 20, 7.5));
    expect(compact.minTapTarget, 56);
    expect(base.md, 18);
    expect(base.pagePadding.left, 12);
  });

  testWidgets('spacing updates on window resize without scaling typography', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    late MuiSpacing spacing;
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildMuiTheme(brightness: Brightness.light),
        home: Builder(
          builder: (context) {
            spacing = context.spacing;
            style = context.theme.typography.bodyMedium.onSurface;
            return const SizedBox();
          },
        ),
      ),
    );
    final phoneStyle = style;
    expect(spacing.pagePadding.left, 12);

    tester.view.physicalSize = const Size(768, 1024);
    await tester.pump();
    expect(spacing.pagePadding.left, 16);
    expect(style, phoneStyle);

    tester.view.physicalSize = const Size(320, 640);
    await tester.pump();
    expect(spacing.pagePadding.left, 10);
    expect(style, phoneStyle);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    expect(spacing.pagePadding.left, 10);
    expect(tester.takeException(), isNull);
  });
}
