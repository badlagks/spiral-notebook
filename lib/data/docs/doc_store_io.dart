import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'doc_store.dart';

DocStore createDocStore() => _FileDocStore();

/// Documents as files in the app's own folder, which the phone's or Mac's
/// regular backup includes.
class _FileDocStore implements DocStore {
  Directory? _dir;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    return _dir = await Directory('${base.path}/notebooks').create(recursive: true);
  }

  Future<File> _file(String name, [String ext = 'json']) async => File('${(await _folder()).path}/$name.$ext');

  @override
  Future<List<String>> read(String name) async {
    final out = <String>[];
    for (final ext in ['json', 'prev']) {
      final f = await _file(name, ext);
      try {
        if (await f.exists()) out.add(await f.readAsString());
      } catch (_) {
        // A damaged file: the spare is tried next.
      }
    }
    return out;
  }

  @override
  Future<void> write(String name, String text) async {
    final main = await _file(name);
    final tmp = await _file(name, 'tmp');
    await tmp.writeAsString(text, flush: true);
    if (await main.exists()) await main.rename((await _file(name, 'prev')).path);
    await tmp.rename(main.path);
  }

  @override
  Future<void> delete(String name) async {
    for (final ext in ['json', 'prev', 'tmp']) {
      final f = await _file(name, ext);
      if (await f.exists()) await f.delete();
    }
  }

  @override
  Future<List<String>> list(String prefix) async {
    final dir = await _folder();
    return [
      await for (final f in dir.list())
        if (f is File && f.path.endsWith('.json'))
          if (f.uri.pathSegments.last case final n when n.startsWith(prefix)) n.substring(0, n.length - 5),
    ];
  }
}
