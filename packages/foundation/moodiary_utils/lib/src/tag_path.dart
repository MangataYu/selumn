/// Tags use a case-sensitive slash-separated path. Existing names containing
/// spaces remain readable; the editor restricts new inline tags separately.
class TagPath {
  const TagPath._();

  static final _inline = RegExp(
    r'^[\p{L}\p{M}\p{N}_-]+(?:/[\p{L}\p{M}\p{N}_-]+)*$',
    unicode: true,
  );

  static bool isInline(String value) => _inline.hasMatch(value);

  static String? normalize(String value) {
    var path = value.trim();
    if (path.startsWith('#')) path = path.substring(1);
    final parts = path.split('/').map((part) => part.trim()).toList();
    if (parts.any(
      (part) => part.isEmpty || part.contains(RegExp(r'[\r\n\t]')),
    )) {
      return null;
    }
    return parts.join('/');
  }

  static List<String> normalizeAll(Iterable<String> values) => {
    for (final value in values)
      if (value.trim().isNotEmpty) normalize(value) ?? value.trim(),
  }.toList();

  static bool matches(String candidate, String parent) =>
      candidate == parent || candidate.startsWith('$parent/');

  static List<String> ancestors(String path) {
    final parts = path.split('/');
    return [for (var i = 1; i <= parts.length; i++) parts.take(i).join('/')];
  }

  static String replacePrefix(String tag, String from, String to) =>
      matches(tag, from) ? '$to${tag.substring(from.length)}' : tag;
}
