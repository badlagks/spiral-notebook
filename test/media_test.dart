import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_notebook/data/media/media_picker.dart';
import 'package:spiral_notebook/data/media/media_store.dart';
import 'package:spiral_notebook/data/notebook_store.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/main.dart';
import 'package:spiral_notebook/models/notebook.dart';
import 'package:spiral_notebook/ui/blocks/media_view.dart';

/// A 4×2 pixel PNG.
final tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGP43+AARwzIHAC7qg35WYGkRwAAAABJRU5ErkJggg==');

class FakePicker extends MediaPicker {
  const FakePicker();

  @override
  Future<PickedMedia?> pick(MediaKind kind, {bool camera = false}) async =>
      PickedMedia(bytes: tinyPng, name: 'lake.png', mime: 'image/png');
}

void main() {
  setUp(() {
    mediaStore = MemoryMediaStore();
    mediaPicker = const FakePicker();
  });

  test('a photo widget saves its note, place and to-dos', () {
    final b = MediaBlock(
      mediaId: 'm1',
      aspect: 1.5,
      note: 'Cabin',
      place: 'Tahoe',
      todos: ChecklistBlock(items: [ChecklistItem(text: 'Print it', done: true)]),
    )
      ..x = 10
      ..y = 20;
    final back = Block.fromJson(jsonDecode(jsonEncode(b.toJson())) as Map<String, dynamic>) as MediaBlock;
    expect(back.mediaId, 'm1');
    expect(back.aspect, 1.5);
    expect(back.place, 'Tahoe');
    expect(back.todos.items.single.done, isTrue);
    expect(back.searchableText, contains('Print it'));
  });

  test('photo shape is read from the file header', () {
    expect(imageAspect(tinyPng), 2);
    expect(imageAspect(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('unused photos are tidied away, photos on torn-out pages are kept', () async {
    final nb = sampleNotebook();
    nb.sections.first.pages.first.blocks.add(MediaBlock(mediaId: 'kept'));
    nb.archive.add(ArchivedPage(
      page: NotePage(blocks: [MediaBlock(mediaId: 'torn')]),
      sectionId: 's',
      sectionName: 'Ideas',
      sectionColor: 0,
      tornAt: DateTime.now(),
    ));
    for (final id in ['kept', 'torn', 'gone']) {
      await mediaStore.put(id, tinyPng, mime: 'image/png');
    }
    await mediaStore.removeAllExcept(nb.mediaIds);
    expect((await mediaStore.ids())..sort(), ['kept', 'torn']);
  });

  testWidgets('a photo is previewed, then added to the page', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = NotebookStore.memory(sampleNotebook());
    await tester.pumpWidget(NotebookApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    // An example first, then the chosen photo.
    expect(find.text('Choose a photo'), findsNothing);
    expect(find.text('Choose photo'), findsOneWidget);
    expect(find.text('Add to page'), findsNothing);
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(Dialog), matching: find.byType(TextField)).first, 'Our cabin');
    await tester.tap(find.text('Add to page'));
    await tester.pumpAndSettle();

    final photo = store.page.blocks.last as MediaBlock;
    expect(photo.note, 'Our cabin');
    expect(photo.aspect, 2);
    expect(await mediaStore.get(photo.mediaId), isNotNull);
    expect(find.byType(MediaView), findsOneWidget);

    await tester.tap(find.text('Add a to-do'));
    await tester.pump();
    expect(photo.todos.items, hasLength(1));
  });
}
