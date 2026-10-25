import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A file the person opened.
class OpenedFile {
  const OpenedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Saving and opening files the person chooses: a save dialog or download,
/// and an open dialog. Tests swap in a fake.
class FileIO {
  const FileIO();

  /// Returns false if the person cancelled.
  Future<bool> save(String fileName, Uint8List bytes, {String mime = 'application/octet-stream'}) async =>
      await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mime) != null;

  Future<OpenedFile?> open({required List<String> extensions}) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: extensions);
    if (file == null) return null;
    return OpenedFile(file.name, await file.xFile.readAsBytes());
  }
}

FileIO fileIO = const FileIO();
