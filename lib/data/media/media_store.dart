import 'dart:typed_data';

import 'package:video_player/video_player.dart';

import 'media_store_io.dart' if (dart.library.js_interop) 'media_store_web.dart' as platform;

/// Keeps photo and video files on this device, by id. Nothing is uploaded.
abstract class MediaStore {
  Future<void> put(String id, Uint8List bytes, {required String mime, String name = ''});
  Future<Uint8List?> get(String id);
  Future<void> delete(String id);
  Future<List<String>> ids();

  /// A player for a stored video, or null if it's gone.
  Future<VideoPlayerController?> videoPlayer(String id);

  /// Deletes files no page uses any more, such as photos on erased widgets.
  Future<void> removeAllExcept(Set<String> keep) async {
    for (final id in await ids()) {
      if (!keep.contains(id)) await delete(id);
    }
  }
}

/// The store this app uses. Tests swap in [MemoryMediaStore].
MediaStore mediaStore = platform.createMediaStore();

/// Keeps media in memory only, for tests and as a fallback.
class MemoryMediaStore extends MediaStore {
  final _files = <String, Uint8List>{};

  @override
  Future<void> put(String id, Uint8List bytes, {required String mime, String name = ''}) async => _files[id] = bytes;

  @override
  Future<Uint8List?> get(String id) async => _files[id];

  @override
  Future<void> delete(String id) async => _files.remove(id);

  @override
  Future<List<String>> ids() async => _files.keys.toList();

  @override
  Future<VideoPlayerController?> videoPlayer(String id) async => null;
}

/// File name ending for a media type, so players recognise the file.
String extensionFor(String mime, String name) {
  final dot = name.lastIndexOf('.');
  if (dot > 0 && name.length - dot <= 5) return name.substring(dot + 1).toLowerCase();
  return switch (mime) {
    'image/png' => 'png',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/heic' => 'heic',
    'video/quicktime' => 'mov',
    'video/webm' => 'webm',
    final m when m.startsWith('video/') => 'mp4',
    _ => 'jpg',
  };
}
