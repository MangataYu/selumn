import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:moodiary_http/moodiary_http.dart';
import 'package:moodiary_ml/moodiary_ml.dart';

class _UnusedHttp extends Fake implements IHttpClient {}

void main() {
  test(
    'operations are exclusive and publish shared progress until completion',
    () async {
      final manager = EmbeddingModelManager(_UnusedHttp());
      final gate = Completer<void>();
      final first = manager.runOperation(
        kind: EmbeddingModelOperationKind.activate,
        modelId: 'model',
        action: (progress) async {
          progress(0.25);
          await gate.future;
        },
      );
      expect(manager.operation.value?.progress, 0.25);
      var called = false;
      expect(
        await manager.runOperation(
          kind: EmbeddingModelOperationKind.delete,
          modelId: 'model',
          action: (_) async {
            called = true;
          },
        ),
        isFalse,
      );
      expect(called, isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(manager.operation.value, isNull);
    },
  );

  test('failure releases busy state and late progress cannot corrupt a later operation', () async {
    final manager = EmbeddingModelManager(_UnusedHttp());
    late void Function(double) oldProgress;
    await expectLater(
      manager.runOperation(
        kind: EmbeddingModelOperationKind.activate,
        modelId: 'model',
        action: (progress) async {
          oldProgress = progress;
          throw StateError('failed');
        },
      ),
      throwsStateError,
    );
    expect(manager.operation.value, isNull);

    final gate = Completer<void>();
    final next = manager.runOperation(
      kind: EmbeddingModelOperationKind.delete,
      modelId: 'model',
      action: (_) => gate.future,
    );
    oldProgress(0.8);
    expect(manager.operation.value?.kind, EmbeddingModelOperationKind.delete);
    expect(manager.operation.value?.progress, 0);
    gate.complete();
    expect(await next, isTrue);
    expect(manager.operation.value, isNull);
  });
}
