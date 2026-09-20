import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_diary/src/presentation/widget/view_mode_sheet.dart';
import 'package:moodiary_models/moodiary_models.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';
import 'package:mui/mui.dart';

import 'support/pump.dart';

void main() {
  late MemoryKVStorage kv;

  setUp(() {
    kv = MemoryKVStorage();
    getIt.pushNewScope(init: (gi) => gi.registerSingleton<IKVStorage>(kv));
  });

  tearDown(() => getIt.popScope());

  Widget host() {
    return muiTestApp(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => ViewModeSheet.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  int? storedSort() => kv.data[MoodiaryKVs.homeSortMode.name] as int?;

  testWidgets('视图和排序保留适度留白，不重复显示分类大标题', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await open(tester);

    final modes = find.byType(SegmentedButton<ViewModeType>);
    final options = find.byType(MSheetOptionTile<int>);
    final firstOption = tester.getRect(options.first);
    expect(find.byType(MFormSection), findsNothing);
    expect(firstOption.top - tester.getRect(modes).bottom, closeTo(8, 0.01));
    expect(
      tester
          .widget<SegmentedButton<ViewModeType>>(modes)
          .style!
          .textStyle!
          .resolve({})!
          .fontSize,
      16,
    );
    expect(
      tester
          .getSize(
            find.descendant(of: options.first, matching: find.byType(MInkWell)),
          )
          .height,
      48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字号下选项增高，仍可切换模式并保存', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(host());
    await open(tester);

    final firstOption = find.byType(MSheetOptionTile<int>).first;
    expect(
      tester
          .getSize(
            find.descendant(of: firstOption, matching: find.byType(MInkWell)),
          )
          .height,
      greaterThan(48),
    );
    expect(tester.takeException(), isNull);
    await pick(tester, '时间线');
    await pick(tester, '最早在前');
    await pick(tester, '确认');
    expect(storedSort(), DiarySort.timeAsc.number);
    expect(
      kv.data[MoodiaryKVs.homeViewMode.name],
      ViewModeType.timeline.number,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('未设置视图时默认信息流，打开不落盘', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    final modes = tester.widget<SegmentedButton<ViewModeType>>(
      find.byType(SegmentedButton<ViewModeType>),
    );
    expect(modes.selected, {ViewModeType.feed});
    expect(find.text('最近修改在前'), findsOneWidget);
    expect(kv.data[MoodiaryKVs.homeViewMode.name], isNull);
  });

  testWidgets('选中不落盘，按下确定才写', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    await pick(tester, '最早在前');
    expect(storedSort(), isNull, reason: '只是暂存，还没写 KV');

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(storedSort(), DiarySort.timeAsc.number);
  });

  testWidgets('取消是真的取消', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    await pick(tester, '最早在前');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(storedSort(), isNull);
    expect(find.text('最早在前'), findsNothing, reason: '弹窗已关');
  });

  testWidgets('视图模式同样是暂存，确定才落盘', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    await pick(tester, '时间线');
    expect(kv.data[MoodiaryKVs.homeViewMode.name], isNull);

    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(
      kv.data[MoodiaryKVs.homeViewMode.name],
      ViewModeType.timeline.number,
    );
  });

  testWidgets('打开时归一旧组合：时间线 + 最近修改在前 → 最新在前', (tester) async {
    kv.data[MoodiaryKVs.homeViewMode.name] = ViewModeType.timeline.number;
    kv.data[MoodiaryKVs.homeSortMode.name] = DiarySort.lastModifiedDesc.number;

    await tester.pumpWidget(host());
    await open(tester);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(storedSort(), DiarySort.timeDesc.number);
  });

  testWidgets('「最近修改在前」只在信息流下出现', (tester) async {
    kv.data[MoodiaryKVs.homeViewMode.name] = ViewModeType.timeline.number;
    await tester.pumpWidget(host());
    await open(tester);

    expect(find.text('最近修改在前'), findsNothing, reason: '保留已保存的时间线');

    await pick(tester, '信息流');
    expect(find.text('最近修改在前'), findsOneWidget);

    await pick(tester, '时间线');
    expect(find.text('最近修改在前'), findsNothing);
  });

  testWidgets('切回时间线时把只属于信息流的排序退回默认', (tester) async {
    await tester.pumpWidget(host());
    await open(tester);

    await pick(tester, '信息流');
    await pick(tester, '最近修改在前');
    await pick(tester, '时间线');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(storedSort(), DiarySort.timeDesc.number);
  });
}
