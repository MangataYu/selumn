import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_mobile/app/build_badge.dart';

// appFlavor is a compile-time constant. Run this file with no flavor and with
// --flavor production / alpha to cover each channel.
void main() {
  const child = SizedBox.expand(key: ValueKey('app'));

  testWidgets('Alpha 在应用根部无需主题或文字方向祖先即可显示角标', (tester) async {
    await tester.pumpWidget(const BuildBadge(child: child));

    expect(tester.takeException(), isNull);
    expect(find.byWidget(child), findsOneWidget);
    final banner = tester.widget<Banner>(find.byType(Banner));
    expect(banner.message, 'ALPHA');
    expect(banner.location, BannerLocation.topStart);
  }, skip: appFlavor != 'alpha');

  testWidgets('Production 保留应用且不显示 Alpha 角标', (tester) async {
    await tester.pumpWidget(const BuildBadge(child: child));

    expect(tester.takeException(), isNull);
    expect(find.byWidget(child), findsOneWidget);
    expect(find.byType(Banner), findsNothing);
  }, skip: appFlavor != 'production');

  testWidgets('未指定渠道时保留应用且不显示 Alpha 角标', (tester) async {
    await tester.pumpWidget(const BuildBadge(child: child));

    expect(tester.takeException(), isNull);
    expect(find.byWidget(child), findsOneWidget);
    expect(find.byType(Banner), findsNothing);
  }, skip: appFlavor != null);

  testWidgets('角标不改变应用尺寸或拦截角标区域和内容区域的点击', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      BuildBadge(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: child,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final app = find.byWidget(child);
    expect(
      tester.getSize(app),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    await tester.tapAt(tester.getTopLeft(app) + const Offset(20, 20));
    await tester.tap(find.byType(GestureDetector));
    expect(taps, 2);
  });
}
