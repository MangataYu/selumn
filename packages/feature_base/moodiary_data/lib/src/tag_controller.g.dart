// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(diaryTags)
final diaryTagsProvider = DiaryTagsProvider._();

final class DiaryTagsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<String>>,
          List<String>,
          FutureOr<List<String>>
        >
    with $FutureModifier<List<String>>, $FutureProvider<List<String>> {
  DiaryTagsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diaryTagsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diaryTagsHash();

  @$internal
  @override
  $FutureProviderElement<List<String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<String>> create(Ref ref) {
    return diaryTags(ref);
  }
}

String _$diaryTagsHash() => r'8de0730ad65bed46f4ebc874dd2e1c9264fffc29';

@ProviderFor(tagDiaryCounts)
final tagDiaryCountsProvider = TagDiaryCountsProvider._();

final class TagDiaryCountsProvider
    extends
        $FunctionalProvider<
          AsyncValue<({Map<String, int> byTag, int total, int untagged})>,
          ({Map<String, int> byTag, int total, int untagged}),
          FutureOr<({Map<String, int> byTag, int total, int untagged})>
        >
    with
        $FutureModifier<({Map<String, int> byTag, int total, int untagged})>,
        $FutureProvider<({Map<String, int> byTag, int total, int untagged})> {
  TagDiaryCountsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tagDiaryCountsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tagDiaryCountsHash();

  @$internal
  @override
  $FutureProviderElement<({Map<String, int> byTag, int total, int untagged})>
  $createElement($ProviderPointer pointer) => $FutureProviderElement(pointer);

  @override
  FutureOr<({Map<String, int> byTag, int total, int untagged})> create(
    Ref ref,
  ) {
    return tagDiaryCounts(ref);
  }
}

String _$tagDiaryCountsHash() => r'ca38fcd9b1d77c8400895ff66f533c2cf69a0b7d';
