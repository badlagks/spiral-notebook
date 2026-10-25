import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_notebook/data/notebook_store.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/main.dart';
import 'package:spiral_notebook/models/notebook.dart';
import 'package:spiral_notebook/ui/ink.dart';
import 'package:spiral_notebook/ui/page_flip.dart';
import 'package:spiral_notebook/ui/paper_page.dart';
import 'package:spiral_notebook/ui/section_tabs.dart';
import 'package:spiral_notebook/ui/blocks/calculator_view.dart';

Future<NotebookStore> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = NotebookStore.memory(sampleNotebook());
  await tester.pumpWidget(NotebookApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('a wide screen shows a two-page spread with tabs', (tester) async {
    await pumpApp(tester, const Size(1400, 900));
    expect(find.text('Draft Outline'), findsOneWidget);
    expect(find.text('Project Budget'), findsOneWidget);
    for (final tab in ['Ideas', 'Daily', 'Finances', 'Tasks']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Pages 1–2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone shows one page and turns pages', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    expect(find.text('Draft Outline'), findsOneWidget);
    expect(find.text('Project Budget'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(store.pageIndex, 1);
    expect(find.text('Project Budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tabs switch sections', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    await tester.tap(find.text('Finances').last);
    await tester.pumpAndSettle();
    expect(store.section.name, 'Finances');
    expect(find.text('Monthly budget'), findsOneWidget);
    // The budget sheet's grand total: 1750 - 1600.50.
    expect(find.text('\$149.50'), findsOneWidget);
  });

  testWidgets('ticking a checklist item updates the notebook', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final item = store.sections.first.pages[1].blocks
        .whereType<ChecklistBlock>()
        .first
        .items
        .firstWhere((i) => i.text == 'Salary');
    expect(item.done, isFalse);
    await tester.tap(find.bySemanticsLabel('Salary'));
    await tester.pump();
    expect(item.done, isTrue);
  });

  testWidgets('the calculator adds up', (tester) async {
    await pumpApp(tester, const Size(1400, 1100));
    for (final k in ['C', '1', '2', '+', '3', '0', '=']) {
      await tester.tap(find.descendant(of: find.byType(CalculatorView), matching: find.text(k)));
      await tester.pump();
    }
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('adding a checklist from the Add menu', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    final before = store.page.blocks.length;
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist'));
    await tester.pumpAndSettle();
    // The preview shows a sample checklist before anything is added.
    expect(find.text('Send invoice'), findsOneWidget);
    await tester.tap(find.text('Add to page'));
    await tester.pumpAndSettle();
    expect(store.page.blocks.length, before + 1);
    expect(store.page.blocks.last, isA<ChecklistBlock>());
  });

  testWidgets('search jumps to the page', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'dentist');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Tasks ·'));
    await tester.pumpAndSettle();
    expect(store.section.name, 'Tasks');
  });

  testWidgets('a widget can be picked up and dragged to a new spot', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final sticky = store.sections.first.pages.first.blocks.whereType<StickyBlock>().first;
    final before = Offset(sticky.x!, sticky.y!);
    await tester.tap(find.text('Call Sam about the sketches'));
    await tester.pumpAndSettle();
    final handle = find.descendant(
      of: find.byWidgetPredicate((w) => w is AnimatedOpacity && w.opacity == 1),
      matching: find.text('Move'),
    );
    await tester.drag(handle, const Offset(-120, 200));
    await tester.pumpAndSettle();
    expect(sticky.x, lessThan(before.dx - 50));
    expect(sticky.y, greaterThan(before.dy + 100));
  });

  testWidgets('dragging the page edge flips to the next spread', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final edge = tester.getRect(find.byType(FlippingBook)).centerRight - const Offset(12, 0);
    await tester.dragFrom(edge, const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(store.pageIndex, 2);
    expect(find.text('Pages 3–4'), findsOneWidget);
  });

  testWidgets('the page curls back when you drag from the coil, or lets go early', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(store.pageIndex, 1);

    final book = tester.getRect(find.byType(FlippingBook));
    // A short pull from the right edge springs back.
    await tester.dragFrom(book.bottomRight - const Offset(12, 60), const Offset(-30, -10));
    await tester.pumpAndSettle();
    expect(store.pageIndex, 1);

    // Pulling the previous page over from the coil turns back.
    await tester.dragFrom(book.centerLeft + const Offset(26, 0), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(store.pageIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone held sideways shows two pages', (tester) async {
    await pumpApp(tester, const Size(844, 390));
    expect(find.text('Draft Outline'), findsOneWidget);
    expect(find.text('Project Budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a torn-out page goes to the archive and can be restored', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tear out this page'));
    await tester.pumpAndSettle();
    expect(store.archive.single.page.title, 'Draft Outline');
    expect(store.section.pages.first.title, 'Project Budget');

    await tester.tap(find.byTooltip('Torn-out pages'));
    await tester.pumpAndSettle();
    expect(find.textContaining('deleted in 30 days'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(store.archive, isEmpty);
    expect(store.page.title, 'Draft Outline');
  });

  testWidgets('drawing mode draws with a finger, and undo takes it back', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    final page = store.page;
    await tester.tap(find.byTooltip('Draw on the paper'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawToolbar), findsOneWidget);

    final center = tester.getCenter(find.byType(PaperPage));
    final g = await tester.startGesture(center, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(center + Offset(i * 8.0, i * 3.0));
    }
    await g.up();
    await tester.pump();
    expect(page.strokes, hasLength(1));
    expect(page.strokes.single.points.length, greaterThan(5));

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(page.strokes, isEmpty);
    await tester.tap(find.byTooltip('Redo'));
    await tester.pump();
    expect(page.strokes, hasLength(1));

    // The eraser removes a line it touches.
    await tester.tap(find.byTooltip('Eraser: touch a line to remove it'));
    await tester.pump();
    await tester.tapAt(center + const Offset(40, 15));
    await tester.pump();
    expect(page.strokes, isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawToolbar), findsNothing);
  });

  testWidgets('a stylus draws without drawing mode, then fingers stop drawing', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    final page = store.page;
    final at = tester.getCenter(find.byType(PaperPage)) + const Offset(0, 120);
    var g = await tester.startGesture(at, kind: PointerDeviceKind.stylus);
    await g.moveTo(at + const Offset(30, 0));
    await g.moveTo(at + const Offset(60, 5));
    await g.up();
    await tester.pump();
    expect(page.strokes, hasLength(1));

    await tester.tap(find.byTooltip('Draw on the paper'));
    await tester.pumpAndSettle();
    g = await tester.startGesture(at + const Offset(0, 40), kind: PointerDeviceKind.touch);
    await g.moveTo(at + const Offset(50, 40));
    await g.up();
    await tester.pump();
    expect(page.strokes, hasLength(1), reason: 'a palm or finger leaves no marks once a pen is used');
  });

  testWidgets('plain white paper can be chosen instead of the notebook', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    expect(find.byType(SectionTabs), findsOneWidget);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look and paper colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain paper'));
    await tester.tap(find.text('White'));
    await tester.tap(find.text('Use this look'));
    await tester.pumpAndSettle();

    expect(store.notebook.look, Look.plain);
    expect(store.notebook.tone, PaperTone.white);
    expect(find.byType(SectionTabs), findsNothing);
    expect(find.byType(SectionChips), findsOneWidget);
    expect(find.text('Draft Outline'), findsOneWidget);
    await tester.tap(find.text('Finances'));
    await tester.pumpAndSettle();
    expect(store.section.name, 'Finances');

    final again = Notebook.fromJson(store.notebook.toJson());
    expect(again.look, Look.plain);
    expect(again.tone, PaperTone.white);
    expect(tester.takeException(), isNull);
  });
}
