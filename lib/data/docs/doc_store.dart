import 'doc_store_io.dart' if (dart.library.js_interop) 'doc_store_web.dart' as platform;

/// Named text documents kept on the device: the list of notebooks, each
/// notebook, and its daily copies. Writes never leave a half-written file:
/// the new text goes to a temporary file that then replaces the old one,
/// and the version before is kept as a spare in case the newest is damaged.
abstract class DocStore {
  /// The document's text, newest first, then the spare from before it.
  /// Callers try each in turn until one reads correctly.
  Future<List<String>> read(String name);

  Future<void> write(String name, String text);

  Future<void> delete(String name);

  /// Names of the stored documents that start with [prefix].
  Future<List<String>> list(String prefix);
}

/// Keeps documents in memory, for tests.
class MemoryDocStore implements DocStore {
  final docs = <String, String>{};
  final _spares = <String, String>{};

  @override
  Future<List<String>> read(String name) async => [?docs[name], ?_spares[name]];

  @override
  Future<void> write(String name, String text) async {
    if (docs[name] case final old?) _spares[name] = old;
    docs[name] = text;
  }

  @override
  Future<void> delete(String name) async {
    docs.remove(name);
    _spares.remove(name);
  }

  @override
  Future<List<String>> list(String prefix) async => [for (final n in docs.keys) if (n.startsWith(prefix)) n];
}

DocStore createDocStore() => platform.createDocStore();
