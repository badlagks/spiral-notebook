import 'package:shared_preferences/shared_preferences.dart';

import 'doc_store.dart';

DocStore createDocStore() => _BrowserDocStore();

/// Documents in the browser's storage for this site.
class _BrowserDocStore implements DocStore {
  static const _prefix = 'doc.';
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<List<String>> read(String name) async {
    final p = await _p;
    return [?p.getString('$_prefix$name'), ?p.getString('$_prefix$name.prev')];
  }

  @override
  Future<void> write(String name, String text) async {
    final p = await _p;
    final old = p.getString('$_prefix$name');
    if (old != null) await p.setString('$_prefix$name.prev', old);
    if (!await p.setString('$_prefix$name', text)) throw StateError('The browser would not save');
  }

  @override
  Future<void> delete(String name) async {
    final p = await _p;
    await p.remove('$_prefix$name');
    await p.remove('$_prefix$name.prev');
  }

  @override
  Future<List<String>> list(String prefix) async {
    final p = await _p;
    return [
      for (final k in p.getKeys())
        if (k.startsWith('$_prefix$prefix') && !k.endsWith('.prev')) k.substring(_prefix.length),
    ];
  }
}
