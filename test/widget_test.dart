import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_notebook/data/notebook_store.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/main.dart';
import 'package:spiral_notebook/models/notebook.dart';
import 'package:spiral_notebook/ui/blocks/calculator_view.dart';
import 'package:spiral_notebook/ui/paper_page.dart';

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
    await tester.tap(find.byTooltip('Next page'));
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
    await tester.scrollUntilVisible(
      find.text('='),
      200,
      scrollable: find.descendant(of: find.byType(PaperPage).at(1), matching: find.byType(Scrollable)).first,
    );
    for (final k in ['C', '1', '2', '+', '3', '0', '=']) {
      await tester.tap(find.descendant(of: find.byType(CalculatorView), matching: find.text(k)));
      await tester.pump();
    }
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('adding a checklist from the Add menu', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    final before = store.page.blocks.length;
    await tester.scrollUntilVisible(find.text('Add'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist'));
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
}
