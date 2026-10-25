import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

import 'media_store.dart';

MediaStore createMediaStore() => _IndexedDbMediaStore();

/// Media kept in the browser's own database on this computer.
class _IndexedDbMediaStore extends MediaStore {
  static const _table = 'media';
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
        final done = Completer<web.IDBDatabase>();
        final req = web.window.indexedDB.open('spiral_notebook_media', 1);
        req.onupgradeneeded = ((web.Event _) {
          (req.result as web.IDBDatabase).createObjectStore(_table);
        }).toJS;
        req.onsuccess = ((web.Event _) => done.complete(req.result as web.IDBDatabase)).toJS;
        req.onerror = ((web.Event _) => done.completeError('Could not open media storage')).toJS;
        return done.future;
      }();

  Future<web.IDBObjectStore> _store(String mode) async =>
      (await _open()).transaction(_table.toJS, mode).objectStore(_table);

  Future<JSAny?> _wait(web.IDBRequest req) {
    final done = Completer<JSAny?>();
    req.onsuccess = ((web.Event _) => done.complete(req.result)).toJS;
    req.onerror = ((web.Event _) => done.completeError(req.error?.message ?? 'Storage error')).toJS;
    return done.future;
  }

  Future<web.Blob?> _blob(String id) async {
    final result = await _wait((await _store('readonly')).get(id.toJS));
    return result == null || result.isUndefined ? null : result as web.Blob;
  }

  @override
  Future<void> put(String id, Uint8List bytes, {required String mime, String name = ''}) async {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    await _wait((await _store('readwrite')).put(blob, id.toJS));
  }

  @override
  Future<Uint8List?> get(String id) async {
    final blob = await _blob(id);
    if (blob == null) return null;
    final buffer = await blob.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Future<void> delete(String id) async {
    await _wait((await _store('readwrite')).delete(id.toJS));
    final url = _urls.remove(id);
    if (url != null) web.URL.revokeObjectURL(url);
  }

  @override
  Future<List<String>> ids() async {
    final keys = await _wait((await _store('readonly')).getAllKeys());
    return [for (final k in (keys as JSArray<JSString>).toDart) k.toDart];
  }

  final _urls = <String, String>{};

  @override
  Future<VideoPlayerController?> videoPlayer(String id) async {
    var url = _urls[id];
    if (url == null) {
      final blob = await _blob(id);
      if (blob == null) return null;
      url = _urls[id] = web.URL.createObjectURL(blob);
    }
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }
}
