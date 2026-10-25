import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_notebook/data/alarms/alarms.dart';
import 'package:spiral_notebook/data/notebook_store.dart';
import 'package:spiral_notebook/data/phone_calendar.dart';
import 'package:spiral_notebook/data/pro.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/main.dart';
import 'package:spiral_notebook/models/notebook.dart';
import 'package:spiral_notebook/ui/ink.dart';
import 'package:spiral_notebook/ui/page_flip.dart';
import 'package:spiral_notebook/ui/paper_page.dart';
import 'package:spiral_notebook/ui/calendar_screen.dart';
import 'package:spiral_notebook/ui/section_lock.dart';
import 'package:spiral_notebook/ui/section_tabs.dart';
import 'package:spiral_notebook/ui/blocks/calculator_view.dart';

Future<NotebookStore> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  deviceUnlock = _FakeDeviceUnlock(hasSensor: false);
  alarms = QuietAlarms();
  phoneCalendar = FakePhoneCalendar();
  purchases = FakePurchases(pro: true);
  final store = NotebookStore.memory(sampleNotebook());
  await tester.pumpWidget(NotebookApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

Finder toolbarButton(String tip) => find.descendant(of: find.byType(DrawToolbar), matching: find.byTooltip(tip));

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
    final item = store.sections.first.pages[1].blocks.whereType<ChecklistBlock>().first.items.firstWhere(
      (i) => i.text == 'Salary',
    );
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

    // Undo puts the whole notebook back, so the page is read again after it.
    await tester.tap(toolbarButton('Undo'));
    await tester.pumpAndSettle();
    expect(store.page.strokes, isEmpty);
    await tester.tap(toolbarButton('Redo'));
    await tester.pumpAndSettle();
    expect(store.page.strokes, hasLength(1));
    expect(find.byType(DrawToolbar), findsOneWidget);

    // The eraser removes a line it touches.
    await tester.tap(find.byTooltip('Eraser: touch a line to remove it'));
    await tester.pump();
    await tester.tapAt(center + const Offset(40, 15));
    await tester.pump();
    expect(store.page.strokes, isEmpty);

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

  testWidgets('the page overview opens pages and keeps favourites', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    expect(find.text('Project Budget'), findsWidgets);
    await tester.tap(find.byTooltip('Add to favourites').last);
    await tester.pumpAndSettle();
    expect(store.section.pages[1].starred, isTrue);

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();
    expect(find.text('Ideas · page 2'), findsOneWidget);
    await tester.tap(find.text('Ideas · page 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PaperPage).last);
    await tester.pumpAndSettle();
    expect(store.pageIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a template fills an empty page, or a new one', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Page options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use a template…'));
    await tester.pumpAndSettle();
    expect(find.text('Habit tracker'), findsOneWidget);
    await tester.tap(find.text('Meeting notes'));
    await tester.pumpAndSettle();
    // The first page already has notes, so the meeting page comes after it.
    expect(store.pageIndex, 1);
    expect(store.page.title, 'Meeting');
    expect(store.page.blocks.whereType<ChecklistBlock>(), hasLength(1));
    expect(store.section.pages[0].title, 'Draft Outline');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lasso moves, recolours and deletes circled lines', (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    final page = store.page;
    await tester.tap(find.byTooltip('Draw on the paper'));
    await tester.pumpAndSettle();
    final c = tester.getCenter(find.byType(PaperPage)) + const Offset(0, 140);
    var g = await tester.startGesture(c, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(c + Offset(i * 5.0, 0));
    }
    await g.up();
    await tester.pump();
    final before = page.strokes.single.points.first.x;

    // Circle it.
    await tester.tap(find.byTooltip('Lasso: circle lines to move, resize or recolour them'));
    await tester.pump();
    g = await tester.startGesture(c + const Offset(-20, -20), kind: PointerDeviceKind.touch);
    for (final o in const [Offset(70, -20), Offset(70, 20), Offset(-20, 20), Offset(-20, -18)]) {
      await g.moveTo(c + o);
    }
    await g.up();
    await tester.pump();
    final ink = InkScope.read(tester.element(find.byType(PaperPage)));
    expect(ink.hasSelection, isTrue);

    // Drag it to the right.
    g = await tester.startGesture(c + const Offset(20, 0), kind: PointerDeviceKind.touch);
    await g.moveTo(c + const Offset(50, 0));
    await g.moveTo(c + const Offset(80, 0));
    await g.up();
    await tester.pump();
    expect(page.strokes.single.points.first.x, greaterThan(before + 30));

    await tester.tap(toolbarButton('Undo'));
    await tester.pumpAndSettle();
    expect(store.page.strokes.single.points.first.x, closeTo(before, 0.01));
  });

  testWidgets('a section can be locked with a PIN, and opens with it', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final ideas = store.sections.first;

    // Lock it from the section editor.
    await tester.longPress(find.text('Ideas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock with a PIN'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'New PIN'), '2468');
    await tester.enterText(find.widgetWithText(TextField, 'Same PIN again'), '2468');
    await tester.tap(find.text('Lock it'));
    await tester.pumpAndSettle();
    expect(ideas.lock, isNotNull);
    expect(ideas.lock, isNot(contains('2468')));
    // Whoever locked it is still in, until the app is put away.
    expect(find.text('Draft Outline'), findsOneWidget);

    store.lockAll();
    await tester.pumpAndSettle();
    expect(find.text('Draft Outline'), findsNothing);
    expect(find.text('This section is locked.'), findsOneWidget);
    expect(store.search('outline'), isEmpty);

    // A wrong PIN, then the right one.
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '1111');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('That PIN is not right. Try again.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'PIN'), '2468');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Draft Outline'), findsOneWidget);
    expect(store.search('outline'), isNotEmpty);

    // The lock is saved with the notebook.
    final copy = Notebook.fromJson(store.notebook.toJson());
    expect(copy.sections.first.lock, ideas.lock);
    final reloaded = NotebookStore.memory(copy);
    expect(reloaded.isLocked(reloaded.sections.first), isTrue);
    expect(reloaded.unlock(reloaded.sections.first, '2468'), isTrue);

    // Removing the lock.
    await tester.longPress(find.text('Ideas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove lock'));
    await tester.pumpAndSettle();
    expect(ideas.lock, isNull);
    store.lockAll();
    await tester.pumpAndSettle();
    expect(find.text('Draft Outline'), findsOneWidget);
  });

  testWidgets('a face or fingerprint opens a locked section, and torn pages stay hidden', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final fake = _FakeDeviceUnlock(hasSensor: true);
    deviceUnlock = fake;
    final ideas = store.sections.first;
    store.tearOut(ideas, ideas.pages.first);
    store.setPin(ideas, '2468');
    store.lockAll();
    await tester.pumpAndSettle();
    expect(store.isArchiveLocked(store.archive.single), isTrue);

    await tester.tap(find.byTooltip('Torn-out pages'));
    await tester.pumpAndSettle();
    expect(find.text('Restore'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use face or fingerprint'));
    await tester.pumpAndSettle();
    expect(fake.asked, 1);
    expect(store.isLocked(ideas), isFalse);
    expect(store.isArchiveLocked(store.archive.single), isFalse);
  });

  testWidgets('reminders set the device alarm, move, stop on torn-out pages, and go to the phone calendar', (
    tester,
  ) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final quiet = alarms as QuietAlarms;
    final cal = phoneCalendar as FakePhoneCalendar;
    final page = store.sections.first.pages.first;
    final sticky = page.blocks.whereType<StickyBlock>().first;
    final id = Reminder.alarmId(sticky.id);
    final at = DateTime.now().add(const Duration(days: 2));

    await store.setReminder(sticky, Reminder(at: at), addToPhoneCalendar: true);
    expect(quiet.scheduled[id], at);
    expect(cal.added.values.single.$1, 'Call Sam about the sketches');

    // Moving it moves the alarm and replaces the calendar event.
    final later = at.add(const Duration(hours: 3));
    await store.setReminder(sticky, Reminder(at: later), addToPhoneCalendar: true);
    expect(quiet.scheduled[id], later);
    expect(cal.added.values.single.$2, later);

    // Saved with the notebook.
    final copy = Notebook.fromJson(store.notebook.toJson());
    final saved = copy.sections.first.pages.first.blocks.whereType<StickyBlock>().first.reminder!;
    expect(saved.at, later);
    expect(saved.calendarEventId, sticky.reminder!.calendarEventId);

    // A torn-out page stops ringing; restoring it brings the alarm back.
    final torn = store.tearOut(store.sections.first, page);
    await store.syncAlarms();
    expect(quiet.scheduled.containsKey(id), isFalse);
    store.restore(torn);
    await store.syncAlarms();
    expect(quiet.scheduled[id], later);

    // Removing it clears everything.
    await store.setReminder(sticky, null);
    expect(quiet.scheduled, isEmpty);
    expect(cal.added, isEmpty);
    expect(sticky.reminder, isNull);
  });

  testWidgets('a reminder is set from the widget menu', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final sticky = store.sections.first.pages.first.blocks.whereType<StickyBlock>().first;
    await tester.tap(find.text('Call Sam about the sketches'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Widget options').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow morning'));
    await tester.pump();
    expect(find.textContaining('Rings Tomorrow'), findsOneWidget);
    await tester.tap(find.text("Also add it to my phone's calendar"));
    await tester.pump();
    await tester.tap(find.text('Set reminder'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(sticky.reminder!.at, DateTime(now.year, now.month, now.day + 1, 9));
    expect(sticky.reminder!.calendarEventId, isNotNull);
    expect((alarms as QuietAlarms).scheduled, hasLength(1));
    // The bell shows on the widget.
    expect(find.textContaining('Tomorrow'), findsOneWidget);
  });

  testWidgets('a due reminder rings and opens its page; the calendar lists it', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final budget = store.sections[2].pages.first;
    final block = budget.blocks.first;
    block.reminder = Reminder(at: DateTime.now().add(const Duration(seconds: 5)));
    store.changed();
    await tester.pumpAndSettle();

    // The calendar shows it today, and tapping it opens the page.
    await tester.tap(find.byTooltip('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Calendar'), findsWidgets);
    expect(find.textContaining('Finances, page 1'), findsOneWidget);
    await tester.tap(find.textContaining('Finances, page 1'));
    await tester.pumpAndSettle();
    expect(store.section.name, 'Finances');

    // Back to the first section, then the clock passes the reminder.
    store.openSection(0);
    await tester.pumpAndSettle();
    block.reminder = Reminder(at: DateTime.now().subtract(const Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Reminder'), findsOneWidget);
    expect((alarms as QuietAlarms).rung, hasLength(1));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(store.section.name, 'Finances');
    expect(block.reminder!.rang, isTrue);

    // It rings only once.
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text('Reminder'), findsNothing);
  });

  testWidgets("the calendar can show the phone's own events", (tester) async {
    final store = await pumpApp(tester, const Size(390, 844));
    final now = DateTime.now();
    (phoneCalendar as FakePhoneCalendar).onPhone.add(
      PhoneEvent(
        title: 'Dentist',
        start: DateTime(now.year, now.month, now.day, 15),
        end: DateTime(now.year, now.month, now.day, 16),
        allDay: false,
      ),
    );
    await showCalendarFrom(tester);
    expect(find.text('Dentist'), findsNothing);
    await tester.tap(find.text("Show my phone's calendar"));
    await tester.pumpAndSettle();
    expect(store.notebook.showPhoneCalendar, isTrue);
    expect(find.text('Dentist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open foldable shows two pages with the coil on the fold', (tester) async {
    tester.view.displayFeatures = [
      const DisplayFeature(
        bounds: Rect.fromLTWH(442, 0, 0, 1104),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    await pumpApp(tester, const Size(884, 1104));
    expect(find.text('Draft Outline'), findsOneWidget);
    expect(find.text('Project Budget'), findsOneWidget);
    final book = tester.getRect(find.byType(FlippingBook));
    expect(book.center.dx, closeTo(442, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a foldable held closed, or a flip phone, keeps one page', (tester) async {
    tester.view.displayFeatures = [
      const DisplayFeature(
        bounds: Rect.fromLTWH(0, 502, 412, 0),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    await pumpApp(tester, const Size(412, 1004));
    expect(find.text('Project Budget'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a widget moves to the next page from its menu, or by dragging past the edge', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final first = store.sections.first.pages[0];
    final second = store.sections.first.pages[1];
    final sticky = first.blocks.whereType<StickyBlock>().first;
    await tester.tap(find.text('Call Sam about the sketches'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Widget options').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to next page'));
    await tester.pumpAndSettle();
    expect(first.blocks, isNot(contains(sticky)));
    expect(second.blocks, contains(sticky));
    expect(find.text('Moved to page 2'), findsOneWidget);

    // Dragged off the left edge of page 2, it goes back to page 1.
    await tester.tap(find.text('Call Sam about the sketches'));
    await tester.pumpAndSettle();
    final handle = find.descendant(
      of: find.byWidgetPredicate((w) => w is AnimatedOpacity && w.opacity == 1),
      matching: find.text('Move'),
    );
    await tester.drag(handle, const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(first.blocks, contains(sticky));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Undo and Redo take back any change, from the top bar or the keyboard', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo)).onPressed, isNull);
    await tester.tap(find.text('Call Sam about the sketches'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Widget options').hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to next page'));
    await tester.pumpAndSettle();
    bool onFirst() => store.sections.first.pages[0].blocks.any((b) => b is StickyBlock && b.text.contains('Call Sam'));
    expect(onFirst(), isFalse);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(onFirst(), isTrue);
    expect(store.pageIndex, 0);
    expect(find.text('Call Sam about the sketches'), findsOneWidget);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(onFirst(), isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(onFirst(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap picks the widget you can see, not a clear one on top of it', (tester) async {
    final store = await pumpApp(tester, const Size(1400, 900));
    final page = store.sections.first.pages[0];
    final sticky = page.blocks.whereType<StickyBlock>().first;
    // A wide, nearly empty text box laid over the sticky note, on top.
    final text = TextBlock(text: 'x', x: sticky.x! - 100, y: sticky.y! - 10, width: 420);
    store.addBlock(page, text);
    await tester.pumpAndSettle();
    expect(page.blocks.last, text);
    final center = tester.getCenter(find.text('Call Sam about the sketches'));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(page.blocks.last, sticky);
  });
}

Future<void> showCalendarFrom(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  showCalendar(context);
  await tester.pumpAndSettle();
}

class _FakeDeviceUnlock implements DeviceUnlock {
  _FakeDeviceUnlock({required this.hasSensor});

  final bool hasSensor;
  int asked = 0;

  @override
  Future<bool> available() async => hasSensor;

  @override
  Future<bool> check(String reason) async {
    asked++;
    return true;
  }
}

class FakePhoneCalendar implements PhoneCalendar {
  final added = <String, (String, DateTime)>{};
  final onPhone = <PhoneEvent>[];
  var _next = 0;

  @override
  bool get available => true;

  @override
  Future<bool> askPermission() async => true;

  @override
  Future<List<PhoneEvent>> events(DateTime from, DateTime to) async => onPhone;

  @override
  Future<String?> add(String title, DateTime at, String note) async {
    final id = 'event-${_next++}';
    added[id] = (title, at);
    return id;
  }

  @override
  Future<void> remove(String id) async => added.remove(id);
}
