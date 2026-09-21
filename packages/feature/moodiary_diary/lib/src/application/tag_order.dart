import 'package:moodiary_utils/moodiary_utils.dart';

/// Applies saved sibling order while keeping every parent before its subtree.
/// Newly discovered tags follow saved siblings in name order.
List<String> orderedTagPaths(Iterable<String> tags, List<String> savedOrder) =>
    TagOrderDraft(tags, savedOrder).paths;

List<String> renameTagOrder(
  List<String> order,
  String oldPath,
  String newPath,
) =>
    {for (final path in order) TagPath.replacePrefix(path, oldPath, newPath)}
        .toList();

List<String> deleteTagOrder(List<String> order, String path) => [
  for (final candidate in order)
    if (!TagPath.matches(candidate, path)) candidate,
];

/// A local edit draft: reordering siblings never changes tag relationships.
class TagOrderDraft {
  final Map<String?, List<String>> _children = {};

  TagOrderDraft(Iterable<String> tags, List<String> savedOrder) {
    final paths = {for (final tag in tags) ...TagPath.ancestors(tag)};
    final rank = <String, int>{};
    for (var i = 0; i < savedOrder.length; i++) {
      rank.putIfAbsent(savedOrder[i], () => i);
    }
    for (final path in paths) {
      (_children[parentOf(path)] ??= []).add(path);
    }
    for (final children in _children.values) {
      children.sort((a, b) {
        final aRank = rank[a];
        final bRank = rank[b];
        if (aRank != null && bRank != null) return aRank.compareTo(bRank);
        if (aRank != null) return -1;
        if (bRank != null) return 1;
        return a.compareTo(b);
      });
    }
  }

  static String? parentOf(String path) {
    final separator = path.lastIndexOf('/');
    return separator < 0 ? null : path.substring(0, separator);
  }

  List<String> childrenOf(String? parent) =>
      List.unmodifiable(_children[parent] ?? const <String>[]);

  bool hasChildren(String path) => _children[path]?.isNotEmpty ?? false;

  void reorder(String? parent, int oldIndex, int newIndex) {
    final children = _children[parent]!;
    if (oldIndex == newIndex) return;
    children.insert(newIndex, children.removeAt(oldIndex));
  }

  List<String> get paths {
    final result = <String>[];
    void visit(String? parent) {
      for (final path in _children[parent] ?? const <String>[]) {
        result.add(path);
        visit(path);
      }
    }

    visit(null);
    return result;
  }
}
