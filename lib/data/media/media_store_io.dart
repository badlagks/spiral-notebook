import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'media_store.dart';

MediaStore createMediaStore() => _FileMediaStore();

/// Media files in the app's private folder on the device.
class _FileMediaStore extends MediaStore {
  Directory? _dir;

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    return _dir = await Directory('${base.path}/media').create(recursive: true);
  }

  Future<File?> _find(String id) async {
    final dir = await _folder();
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && (name == id || name.startsWith('$id.'))) return f;
    }
    return null;
  }

  @override
  Future<void> put(String id, Uint8List bytes, {required String mime, String name = ''}) async {
    final dir = await _folder();
    await File('${dir.path}/$id.${extensionFor(mime, name)}').writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> get(String id) async => (await _find(id))?.readAsBytes();

  @override
  Future<void> delete(String id) async => (await _find(id))?.delete();

  @override
  Future<List<String>> ids() async {
    final dir = await _folder();
    return [
      await for (final f in dir.list())
        if (f is File) f.uri.pathSegments.last.split('.').first,
    ];
  }

  @override
  Future<VideoPlayerController?> videoPlayer(String id) async {
    final f = await _find(id);
    return f == null ? null : VideoPlayerController.file(f);
  }
}
