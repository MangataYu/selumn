import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_assistant/src/data/assistant_defs.dart';
import 'package:moodiary_assistant/src/data/assistant_tools.dart';

void main() {
  group('AssistantToolRegistry.specsFor', () {
    test('null = 全部当前工具，旧分类工具只保留历史显示', () {
      final tools = AssistantToolRegistry.specsFor(null)
          .map((spec) => spec.tool);
      expect(tools, activeAssistantTools);
      expect(tools.toSet().intersection(retiredAssistantTools), isEmpty);
      for (final tool in retiredAssistantTools) {
        expect(AssistantToolRegistry.byId(tool.id), isNotNull);
      }
    });

    test('显式允许旧分类工具也不会重新挂载', () {
      expect(
        AssistantToolRegistry.specsFor([
          for (final tool in retiredAssistantTools) tool.id,
        ]),
        isEmpty,
      );
      expect(
        toolIdsWithoutMemory(),
        isNot(contains(AssistantTool.createCategory.id)),
      );
    });

    test('空列表 = 一个都不挂', () {
      expect(AssistantToolRegistry.specsFor(const []), isEmpty);
    });

    test('子集按 specs 原顺序过滤，与传入顺序无关', () {
      final allowed = [
        AssistantTool.rememberFact.id,
        AssistantTool.searchDiaries.id,
      ];
      final ids = [
        for (final s in AssistantToolRegistry.specsFor(allowed)) s.id,
      ];
      expect(ids, [
        AssistantTool.searchDiaries.id,
        AssistantTool.rememberFact.id,
      ]);
    });

    test('未知 id 静默忽略', () {
      final specs = AssistantToolRegistry.specsFor([
        'gone-tool',
        AssistantTool.getDiary.id,
      ]);
      expect(specs.single.id, AssistantTool.getDiary.id);
    });
  });
}
