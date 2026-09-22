// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diary_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(DiaryController)
final diaryControllerProvider = DiaryControllerFamily._();

final class DiaryControllerProvider
    extends $AsyncNotifierProvider<DiaryController, List<Diary>> {
  DiaryControllerProvider._({
    required DiaryControllerFamily super.from,
    required ({
      String? categoryId,
      bool uncategorized,
      String? tag,
      bool untagged,
      DiaryContentFilter? content,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'diaryControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$diaryControllerHash();

  @override
  String toString() {
    return r'diaryControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  DiaryController create() => DiaryController();

  @override
  bool operator ==(Object other) {
    return other is DiaryControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$diaryControllerHash() => r'df56374f522945456a1cac53c48f1979bcf55c48';

final class DiaryControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          DiaryController,
          AsyncValue<List<Diary>>,
          List<Diary>,
          FutureOr<List<Diary>>,
          ({
            String? categoryId,
            bool uncategorized,
            String? tag,
            bool untagged,
            DiaryContentFilter? content,
          })
        > {
  DiaryControllerFamily._()
    : super(
        retry: null,
        name: r'diaryControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  DiaryControllerProvider call({
    String? categoryId,
    bool uncategorized = false,
    String? tag,
    bool untagged = false,
    DiaryContentFilter? content,
  }) => DiaryControllerProvider._(
    argument: (
      categoryId: categoryId,
      uncategorized: uncategorized,
      tag: tag,
      untagged: untagged,
      content: content,
    ),
    from: this,
  );

  @override
  String toString() => r'diaryControllerProvider';
}

abstract class _$DiaryController extends $AsyncNotifier<List<Diary>> {
  late final _$args =
      ref.$arg
          as ({
            String? categoryId,
            bool uncategorized,
            String? tag,
            bool untagged,
            DiaryContentFilter? content,
          });
  String? get categoryId => _$args.categoryId;
  bool get uncategorized => _$args.uncategorized;
  String? get tag => _$args.tag;
  bool get untagged => _$args.untagged;
  DiaryContentFilter? get content => _$args.content;

  FutureOr<List<Diary>> build({
    String? categoryId,
    bool uncategorized = false,
    String? tag,
    bool untagged = false,
    DiaryContentFilter? content,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Diary>>, List<Diary>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Diary>>, List<Diary>>,
              AsyncValue<List<Diary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(
        categoryId: _$args.categoryId,
        uncategorized: _$args.uncategorized,
        tag: _$args.tag,
        untagged: _$args.untagged,
        content: _$args.content,
      ),
    );
  }
}

@ProviderFor(RecycleBinDiaries)
final recycleBinDiariesProvider = RecycleBinDiariesProvider._();

final class RecycleBinDiariesProvider
    extends $AsyncNotifierProvider<RecycleBinDiaries, List<Diary>> {
  RecycleBinDiariesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recycleBinDiariesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recycleBinDiariesHash();

  @$internal
  @override
  RecycleBinDiaries create() => RecycleBinDiaries();
}

String _$recycleBinDiariesHash() => r'1da1572e21567036a215095dd7ccea7cb42f7fd6';

abstract class _$RecycleBinDiaries extends $AsyncNotifier<List<Diary>> {
  FutureOr<List<Diary>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Diary>>, List<Diary>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Diary>>, List<Diary>>,
              AsyncValue<List<Diary>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(getDiary)
final getDiaryProvider = GetDiaryFamily._();

final class GetDiaryProvider
    extends $FunctionalProvider<AsyncValue<Diary?>, Diary?, Stream<Diary?>>
    with $FutureModifier<Diary?>, $StreamProvider<Diary?> {
  GetDiaryProvider._({
    required GetDiaryFamily super.from,
    required ({
      String? id,
      DiaryType? defaultType,
      String? defaultCategoryId,
      String? defaultTag,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'getDiaryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$getDiaryHash();

  @override
  String toString() {
    return r'getDiaryProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<Diary?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<Diary?> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String? id,
              DiaryType? defaultType,
              String? defaultCategoryId,
              String? defaultTag,
            });
    return getDiary(
      ref,
      id: argument.id,
      defaultType: argument.defaultType,
      defaultCategoryId: argument.defaultCategoryId,
      defaultTag: argument.defaultTag,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GetDiaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$getDiaryHash() => r'e88c4cd38fae54de4c84201ef7930d06b206b602';

final class GetDiaryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<Diary?>,
          ({
            String? id,
            DiaryType? defaultType,
            String? defaultCategoryId,
            String? defaultTag,
          })
        > {
  GetDiaryFamily._()
    : super(
        retry: null,
        name: r'getDiaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  GetDiaryProvider call({
    String? id,
    DiaryType? defaultType,
    String? defaultCategoryId,
    String? defaultTag,
  }) => GetDiaryProvider._(
    argument: (
      id: id,
      defaultType: defaultType,
      defaultCategoryId: defaultCategoryId,
      defaultTag: defaultTag,
    ),
    from: this,
  );

  @override
  String toString() => r'getDiaryProvider';
}
