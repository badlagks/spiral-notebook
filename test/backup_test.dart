import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_notebook/data/backup.dart';
import 'package:spiral_notebook/data/files.dart';
import 'package:spiral_notebook/data/media/media_store.dart';
import 'package:spiral_notebook/data/notebook_store.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/main.dart';
import 'package:spiral_notebook/models/notebook.dart';

final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGP43+AARwzIHAC7qg35WYGkRwAAAABJRU5ErkJggg==',
);

/// Keeps "saved" files in memory and hands back [toOpen] when asked to open one.
class FakeFiles extends FileIO {
  final saved = <String, Uint8List>{};
  OpenedFile? toOpen;

  @override
  Future<bool> save(String fileName, Uint8List bytes, {String mime = ''}) async {
    saved[fileName] = bytes;
    return true;
  }

  @override
  Future<OpenedFile?> open({required List<String> extensions}) async => toOpen;
}

void main() {
  setUp(() => mediaStore = MemoryMediaStore());

  test('a backup brings back pages, photos and settings', () async {
    final nb = sampleNotebook()
      ..look = Look.plain
      ..tone = PaperTone.white;
    nb.sections.first.pages.first.blocks.add(MediaBlock(mediaId: 'p1', note: 'Lake'));
    await mediaStore.put('p1', tinyPng, mime: 'image/png');

    final file = await makeBackup(nb);
    mediaStore = MemoryMediaStore(); // a new phone
    final back = await readBackup(file);

    expect(back.look, Look.plain);
    expect(back.tone, PaperTone.white);
    expect(back.sections.map((s) => s.name), nb.sections.map((s) => s.name));
    final photo = back.sections.first.pages.first.blocks.whereType<MediaBlock>().single;
    expect(photo.note, 'Lake');
    expect(await mediaStore.get('p1'), tinyPng);
  });

  test('other files are refused, not half-read', () async {
    expect(() => readBackup(utf8.encode('hello')), throwsFormatException);
    expect(() => readBackup(utf8.encode('{"a":1}')), throwsFormatException);
  });

  test('file types are recognised from their first bytes', () {
    expect(sniffMime(tinyPng), 'image/png');
    expect(sniffMime(Uint8List.fromList([0xFF, 0xD8, 0xFF])), 'image/jpeg');
    expect(sniffMime(Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0])), 'video/webm');
  });

  test('page favourites and PDF backgrounds are saved', () {
    final p = NotePage(background: 'bg1', starred: true);
    final back = NotePage.fromJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
    expect(back.background, 'bg1');
    expect(back.starred, isTrue);
    final nb = Notebook(
      title: 't',
      sections: [
        Section(name: 'A', color: 0, pages: [p]),
      ],
    );
    expect(nb.mediaIds, contains('bg1'));
  });

  testWidgets('backing up and restoring from the menu', (tester) async {
    final files = FakeFiles();
    fileIO = files;
    addTearDown(() => fileIO = const FileIO());
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = NotebookStore.memory(sampleNotebook());
    await tester.pumpWidget(NotebookApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back up notebook'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(files.saved.keys.single, endsWith('.$backupExtension'));

    // Change something, then restore the backup over it.
    store.sections.first.pages.first.title = 'Changed';
    files.toOpen = OpenedFile('backup.notebook', files.saved.values.single);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore from a backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(store.sections.first.pages.first.title, 'Draft Outline');
    expect(find.text('Notebook restored.'), findsOneWidget);
  });
}
