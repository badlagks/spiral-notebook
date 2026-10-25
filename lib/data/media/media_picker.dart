import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../../models/notebook.dart';

/// A photo or video the person chose.
class PickedMedia {
  const PickedMedia({required this.bytes, required this.name, required this.mime});
  final Uint8List bytes;
  final String name;
  final String mime;
}

/// Opens the photo library, the camera, or a file chooser.
class MediaPicker {
  const MediaPicker();

  Future<PickedMedia?> pick(MediaKind kind, {bool camera = false}) async {
    final source = camera ? ImageSource.camera : ImageSource.gallery;
    final picker = ImagePicker();
    final file = kind == MediaKind.photo
        ? await picker.pickImage(source: source, maxWidth: 2400, maxHeight: 2400, imageQuality: 88)
        : await picker.pickVideo(source: source, maxDuration: const Duration(minutes: 5));
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? _guessMime(file.name, kind);
    return PickedMedia(bytes: bytes, name: file.name, mime: mime);
  }

  static String _guessMime(String name, MediaKind kind) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'mp4' || 'm4v' => 'video/mp4',
      _ => kind == MediaKind.photo ? 'image/jpeg' : 'video/mp4',
    };
  }
}

/// The picker this app uses. Tests swap in a fake.
MediaPicker mediaPicker = const MediaPicker();

/// Width over height of a PNG, JPEG or GIF, read from its header, or null.
double? imageAspect(Uint8List b) {
  int u16(int i) => (b[i] << 8) | b[i + 1];
  int u32(int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  double? ratio(int w, int h) => w > 0 && h > 0 ? w / h : null;

  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return ratio(u32(16), u32(20));
  }
  if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return ratio(b[6] | (b[7] << 8), b[8] | (b[9] << 8));
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    int? orientation;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) return null;
      final marker = b[i + 1];
      final len = u16(i + 2);
      // EXIF says whether the camera was held sideways.
      if (marker == 0xE1) orientation ??= _exifOrientation(b, i + 4, len - 2);
      final isFrame = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isFrame) {
        final h = u16(i + 5), w = u16(i + 7);
        final sideways = orientation != null && orientation >= 5;
        return sideways ? ratio(h, w) : ratio(w, h);
      }
      i += 2 + len;
    }
  }
  return null;
}

int? _exifOrientation(Uint8List b, int start, int length) {
  if (start + 14 > b.length || String.fromCharCodes(b.sublist(start, start + 4)) != 'Exif') return null;
  final tiff = start + 6;
  final little = b[tiff] == 0x49;
  int r16(int i) => little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1];
  int r32(int i) => little
      ? b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)
      : (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
  final ifd = tiff + r32(tiff + 4);
  if (ifd + 2 > b.length) return null;
  final count = r16(ifd);
  for (var e = 0; e < count; e++) {
    final at = ifd + 2 + e * 12;
    if (at + 10 > b.length) return null;
    if (r16(at) == 0x0112) return r16(at + 8);
  }
  return null;
}
