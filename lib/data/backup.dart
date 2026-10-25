import 'dart:convert';
import 'dart:typed_data';

import '../models/notebook.dart';
import 'media/media_store.dart';

/// The ending of backup files, so they're easy to spot.
const backupExtension = 'notebook';

/// Everything in the notebook, photos and videos included, as one file.
Future<Uint8List> makeBackup(Notebook nb, {DateTime? now}) async {
  final media = <String, Object>{};
  for (final id in nb.mediaIds) {
    final bytes = await mediaStore.get(id);
    if (bytes != null) media[id] = {'mime': sniffMime(bytes), 'data': base64Encode(bytes)};
  }
  return utf8.encode(
    jsonEncode({
      'app': 'spiral_notebook',
      'backup': 1,
      'created': (now ?? DateTime.now()).toIso8601String(),
      'notebook': nb.toJson(),
      'media': media,
    }),
  );
}

/// Reads a backup file, puts its photos and videos back on the device,
/// and returns its notebook. Throws [FormatException] for other files.
Future<Notebook> readBackup(Uint8List bytes) async {
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } catch (_) {
    throw const FormatException('This file is not a notebook backup.');
  }
  if (j['app'] != 'spiral_notebook' || j['notebook'] is! Map) {
    throw const FormatException('This file is not a notebook backup.');
  }
  final nb = Notebook.fromJson(j['notebook'] as Map<String, dynamic>);
  final media = (j['media'] as Map?) ?? const {};
  for (final MapEntry(:key, :value) in media.entries) {
    final m = value as Map;
    await mediaStore.put(key as String, base64Decode(m['data'] as String), mime: m['mime'] as String? ?? '');
  }
  return nb;
}

/// The kind of photo or video in [b], from its first bytes.
String sniffMime(Uint8List b) {
  bool at(int i, List<int> sig) =>
      b.length >= i + sig.length && [for (var k = 0; k < sig.length; k++) b[i + k]].join(',') == sig.join(',');
  if (at(0, [0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (at(0, [0xFF, 0xD8])) return 'image/jpeg';
  if (at(0, [0x47, 0x49, 0x46])) return 'image/gif';
  if (at(8, [0x57, 0x45, 0x42, 0x50])) return 'image/webp';
  if (at(0, [0x1A, 0x45, 0xDF, 0xA3])) return 'video/webm';
  if (at(4, [0x66, 0x74, 0x79, 0x70])) {
    final brand = String.fromCharCodes(b.sublist(8, 12));
    if (brand.startsWith('hei') || brand.startsWith('mif')) return 'image/heic';
    return brand == 'qt  ' ? 'video/quicktime' : 'video/mp4';
  }
  return 'application/octet-stream';
}
