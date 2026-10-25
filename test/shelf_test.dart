import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spiral_notebook/data/alarms/alarms.dart';
import 'package:spiral_notebook/data/docs/doc_store.dart';
import 'package:spiral_notebook/data/media/media_store.dart';
import 'package:spiral_notebook/data/notebook_store.dart';
import 'package:spiral_notebook/data/phone_calendar.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/main.dart';
import 'package:spiral_notebook/models/notebook.dart';

import 'widget_test.dart' show FakePhoneCalendar;

void main() {
  setUp(() {
    alarms = QuietAlarms();
    mediaStore = MemoryMediaStore();
    phoneCalendar = FakePhoneCalendar();
  });

  test('the notebook from before the shelf is moved over and kept', () async {
    final old = sampleNotebook()..title = 'Grocery plans';
    SharedPreferences.setMockInitialValues({'notebook.v1': jsonEncode(old.toJson())});
    final docs = MemoryDocStore();
    final store = await NotebookStore.load(docs: docs);
    expect(store.notebook.title, 'Grocery plans');
    expect(store.shelf.notebooks.map((e) => e.title), ['Grocery plans']);
    expect(docs.docs.keys, containsAll(['library', 'notebook-${store.notebook.id}']));
    expect((await SharedPreferences.getInstance()).getString('notebook.v1'), isNull);

    // Opens the same notebook next time.
    final again = await NotebookStore.load(docs: docs);
    expect(again.notebook.id, store.notebook.id);
  });

  test('a damaged save falls back to the copy before it', () async {
    SharedPreferences.setMockInitialValues({});
    final docs = MemoryDocStore();
    final store = await NotebookStore.load(docs: docs);
    store.notebook.title = 'Good';
    await store.saveNow();
    store.notebook.title = 'Newest';
    await store.saveNow();
    // The newest file is damaged, as if the phone died while writing it.
    docs.docs['notebook-${store.notebook.id}'] = '{"broken';
    final again = await NotebookStore.load(docs: docs);
    expect(again.notebook.id, store.notebook.id);
    expect(again.notebook.title, 'Good');
  });

  test('notebooks can be added, switched, deleted and brought back', () async {
    SharedPreferences.setMockInitialValues({});
    final docs = MemoryDocStore();
    final store = await NotebookStore.load(docs: docs);
    final first = store.notebook.id;
    await store.newNotebook(title: 'Recipes', cover: coverColors[2]);
    expect(store.notebook.title, 'Recipes');
    expect(store.notebook.cover, coverColors[2]);
    expect(store.shelf.notebooks.length, 2);

    store.section.pages.first.blocks.add(TextBlock(x: 10, y: 10, width: 100, text: 'Pancakes'));
    await store.saveNow();
    expect(await store.openNotebook(first), isTrue);
    expect(store.notebook.id, first);

    final recipes = store.shelf.notebooks.firstWhere((e) => e.title == 'Recipes').id;
    expect(await store.openNotebook(recipes), isTrue);
    expect(store.search('pancakes'), hasLength(1));

    // Deleting the open notebook opens another.
    expect(await store.deleteNotebook(recipes), isTrue);
    expect(store.notebook.id, first);
    expect(store.shelf.recentlyDeleted.single.title, 'Recipes');
    // The last one can't go.
    expect(await store.deleteNotebook(first), isFalse);

    await store.restoreNotebook(recipes);
    expect(store.shelf.notebooks.length, 2);

    await store.editNotebook(recipes, title: 'Family recipes');
    final again = await NotebookStore.load(docs: docs);
    expect(again.shelf.find(recipes)!.title, 'Family recipes');
    expect(await again.openNotebook(recipes), isTrue);
    expect(again.notebook.title, 'Family recipes');
  });

  test('deleted notebooks go for good after 30 days', () async {
    SharedPreferences.setMockInitialValues({});
    final docs = MemoryDocStore();
    final store = await NotebookStore.load(docs: docs);
    await store.newNotebook(title: 'Old', cover: coverColors[1]);
    final old = store.notebook.id;
    await store.deleteNotebook(old);
    store.shelf.find(old)!.deletedAt = DateTime.now().subtract(const Duration(days: 31));
    await store.saveNow();
    final again = await NotebookStore.load(docs: docs);
    expect(again.shelf.find(old), isNull);
    expect(docs.docs.containsKey('notebook-$old'), isFalse);
  });

  testWidgets('the shelf makes a new notebook and switches back', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = NotebookStore.memory(sampleNotebook(), docs: MemoryDocStore());
    await tester.runAsync(store.saveNow);
    await tester.pumpWidget(NotebookApp(store: store));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('All notebooks'));
    await tester.pumpAndSettle();
    expect(find.text('My notebooks'), findsOneWidget);
    await tester.tap(find.text('New notebook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Garden');
    await tester.tap(find.text('Create'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(store.notebook.title, 'Garden');
    expect(find.text('My notebooks'), findsNothing);
    expect(find.text('Notes'), findsWidgets);

    await tester.tap(find.byTooltip('All notebooks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Notebook'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(store.notebook.title, 'My Notebook');
    expect(find.text('Draft Outline'), findsOneWidget);
    await tester.runAsync(store.saveNow);
  });
}
