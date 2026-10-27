import 'package:medito/services/library/library_store.dart';

/// The session contexts a view writes, kept in memory. A real database
/// would never answer inside a widget test's fake-async zone; any other
/// store call fails loudly.
class MemorySessionStore implements LibraryStore {
  final contexts = <String, String>{};

  @override
  Future<void> noteSessionContext(String trackId, String courseId) async =>
      contexts[trackId] = courseId;

  @override
  Future<void> clearSessionContext(String trackId) async =>
      contexts.remove(trackId);

  @override
  Future<void> noteSessionOrigin(String trackId, String? courseId) =>
      courseId == null
      ? clearSessionContext(trackId)
      : noteSessionContext(trackId, courseId);

  @override
  Future<String?> sessionContext(String trackId) async => contexts[trackId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
