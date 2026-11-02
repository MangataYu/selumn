import 'package:moodiary_storage/moodiary_storage.dart';

/// The stored ids are normalized by the editor against its current tools.
List<String> loadEditorToolbarOrder() =>
    MoodiaryKVs.editorToolbarOrder.get() ?? const [];

/// Reject malformed bridge payloads rather than replacing an existing order.
bool saveEditorToolbarOrder(Object? payload) {
  if (payload is! List || payload.length > 128) return false;
  if (payload.any((id) => id is! String || id.isEmpty || id.length > 80)) {
    return false;
  }
  MoodiaryKVs.editorToolbarOrder.set(payload.cast<String>().toList());
  return true;
}
