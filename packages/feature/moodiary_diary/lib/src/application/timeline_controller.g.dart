// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'timeline_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(timelineMonthCounts)
final timelineMonthCountsProvider = TimelineMonthCountsFamily._();

final class TimelineMonthCountsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<DateTime, int>>,
          Map<DateTime, int>,
          FutureOr<Map<DateTime, int>>
        >
    with
        $FutureModifier<Map<DateTime, int>>,
        $FutureProvider<Map<DateTime, int>> {
  TimelineMonthCountsProvider._({
    required TimelineMonthCountsFamily super.from,
    required ({
      String? tag,
      bool untagged,
      DiaryContentFilter? content,
      DiarySort sort,
    })
    super.argument,
  }) : super(
         retry: null,
         name: r'timelineMonthCountsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$timelineMonthCountsHash();

  @override
  String toString() {
    return r'timelineMonthCountsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<Map<DateTime, int>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<DateTime, int>> create(Ref ref) {
    final argument =
        this.argument
            as ({
              String? tag,
              bool untagged,
              DiaryContentFilter? content,
              DiarySort sort,
            });
    return timelineMonthCounts(
      ref,
      tag: argument.tag,
      untagged: argument.untagged,
      content: argument.content,
      sort: argument.sort,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TimelineMonthCountsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$timelineMonthCountsHash() =>
    r'82b041cfc3d6f6026e400ad695ca4e322bd494cd';

final class TimelineMonthCountsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<Map<DateTime, int>>,
          ({
            String? tag,
            bool untagged,
            DiaryContentFilter? content,
            DiarySort sort,
          })
        > {
  TimelineMonthCountsFamily._()
    : super(
        retry: null,
        name: r'timelineMonthCountsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TimelineMonthCountsProvider call({
    String? tag,
    bool untagged = false,
    DiaryContentFilter? content,
    required DiarySort sort,
  }) => TimelineMonthCountsProvider._(
    argument: (tag: tag, untagged: untagged, content: content, sort: sort),
    from: this,
  );

  @override
  String toString() => r'timelineMonthCountsProvider';
}
