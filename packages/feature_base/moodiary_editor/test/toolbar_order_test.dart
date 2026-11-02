import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_di/moodiary_di.dart';
import 'package:moodiary_editor/src/toolbar_order.dart';
import 'package:moodiary_storage/moodiary_storage.dart';
import 'package:moodiary_storage/testing.dart';

void main() {
  setUp(() => getIt.registerSingleton<IKVStorage>(MemoryKVStorage()));
  tearDown(() async => getIt.reset());

  test('empty by default; saves and reloads the bridge order', () {
    expect(loadEditorToolbarOrder(), isEmpty);
    final payload = jsonDecode('["tag","image","futureTool"]');

    expect(saveEditorToolbarOrder(payload), isTrue);
    expect(loadEditorToolbarOrder(), ['tag', 'image', 'futureTool']);
    expect(MoodiaryKVs.editorToolbarOrder.get(), [
      'tag',
      'image',
      'futureTool',
    ]);
  });

  test('malformed bridge messages do not overwrite saved order', () {
    expect(saveEditorToolbarOrder(['image', 'tag']), isTrue);

    for (final payload in [
      null,
      'image',
      ['image', 3],
      ['image', ''],
      ['x' * 81],
      List.filled(129, 'image'),
    ]) {
      expect(saveEditorToolbarOrder(payload), isFalse);
      expect(loadEditorToolbarOrder(), ['image', 'tag']);
    }
  });

  test('empty order is stored so the editor can restore its defaults', () {
    expect(saveEditorToolbarOrder(['tag']), isTrue);
    expect(saveEditorToolbarOrder([]), isTrue);
    expect(loadEditorToolbarOrder(), isEmpty);
  });
}
