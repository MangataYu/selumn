/// Legacy Isar data remains authoritative until migration to SQLite finishes.
/// The old 2.6.3 cleanup only inspected diary attachment indexes; it did not
/// account for chat images, unsaved work, or references in the new database.
///
/// Do not delete or queue any candidates here. Once migration has completed,
/// the normal media cleanup can safely inspect all current references instead.
Future<void> cleanOrphanMediaIn(String dir) => Future<void>.value();
