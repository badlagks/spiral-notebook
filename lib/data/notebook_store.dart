import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/library.dart';
import '../models/notebook.dart';
import 'alarms/alarms.dart';
import 'docs/doc_store.dart';
import 'media/media_store.dart';
import 'phone_calendar.dart';
import 'sample_notebook.dart';

enum SaveState { saved, saving, failed }

/// Holds the notebook in memory and saves it on the device a moment after
/// each change. Widgets edit the models directly, then call [changed].
class NotebookStore extends ChangeNotifier {
  NotebookStore._(this._notebook, this.shelf, this._docs) : _committed = jsonEncode(_notebook.toJson());

  /// Where the single notebook was kept before there was a shelf.
  static const _oldKey = 'notebook.v1';
  static const _shelfDoc = 'library';
  static String _doc(String id) => 'notebook-$id';
  static const _saveDelay = Duration(milliseconds: 600);

  Notebook _notebook;

  /// The open notebook. Changes when another one is opened from the shelf.
  Notebook get notebook => _notebook;

  /// Every notebook on this device.
  final Shelf shelf;
  final DocStore? _docs;
  Timer? _saveTimer;

  /// Kept separate from the notebook so the save badge can update
  /// without rebuilding the pages.
  final saveState = ValueNotifier(SaveState.saved);

  /// The chosen look and paper colour, which notebook is open, and how many
  /// times it was put back by Undo. The app redraws its screen on change.
  late final appearance = ValueNotifier((notebook.look, notebook.tone, notebook.id, 0));

  void _redraw() => appearance.value = (notebook.look, notebook.tone, notebook.id, appearance.value.$4 + 1);

  void setAppearance({Look? look, PaperTone? tone}) {
    notebook.look = look ?? notebook.look;
    notebook.tone = tone ?? notebook.tone;
    _redraw();
    changed();
  }

  // Undo and redo for everything, kept as copies of the whole notebook.
  // A step ends at each save, a moment after the last change, and after
  // each line drawn.
  static const _historyLimit = 30;
  final _undoSteps = <String>[];
  final _redoSteps = <String>[];
  String _committed;
  bool _dirty = false;

  /// Bumps when Undo or Redo may have become possible or impossible.
  final history = ValueNotifier(0);

  bool get canUndo => _dirty || _undoSteps.isNotEmpty;
  bool get canRedo => !_dirty && _redoSteps.isNotEmpty;

  /// Ends the current step, so the next change can be undone on its own.
  /// Returns the notebook as saved text.
  String checkpoint() {
    final now = jsonEncode(notebook.toJson());
    _dirty = false;
    if (now != _committed) {
      _undoSteps.add(_committed);
      if (_undoSteps.length > _historyLimit) _undoSteps.removeAt(0);
      _redoSteps.clear();
      _committed = now;
    }
    history.value++;
    return now;
  }

  void undo() {
    checkpoint();
    if (_undoSteps.isEmpty) return;
    _redoSteps.add(_committed);
    _putBack(_undoSteps.removeLast());
  }

  void redo() {
    if (_dirty || _redoSteps.isEmpty) return;
    _undoSteps.add(_committed);
    _putBack(_redoSteps.removeLast());
  }

  void _resetHistory() {
    _undoSteps.clear();
    _redoSteps.clear();
    _committed = jsonEncode(notebook.toJson());
    _dirty = false;
    history.value++;
  }

  static Iterable<Block> _blocks(Notebook nb) => nb.sections.expand((s) => s.pages).expand((p) => p.blocks);

  /// Puts the notebook back as it was in [raw], then shows the page that changed.
  void _putBack(String raw) {
    final nb = Notebook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    // A reminder that already rang doesn't ring again because of Undo.
    final rang = {
      for (final b in _blocks(notebook))
        if (b.reminder?.rang ?? false) b.id,
    };
    for (final b in _blocks(nb)) {
      if (rang.contains(b.id)) b.reminder?.rang = true;
    }
    final pagesBefore = {for (final p in notebook.sections.expand((s) => s.pages)) p.id: jsonEncode(p.toJson())};
    _notebook = nb;
    _committed = raw;
    _dirty = false;
    var shown = false;
    for (var si = 0; si < nb.sections.length && !shown; si++) {
      final pages = nb.sections[si].pages;
      for (var pi = 0; pi < pages.length; pi++) {
        if (pagesBefore[pages[pi].id] != jsonEncode(pages[pi].toJson())) {
          _sectionIndex = si;
          _pageIndex = pi;
          shown = true;
          break;
        }
      }
    }
    _sectionIndex = _sectionIndex.clamp(0, nb.sections.length - 1);
    _pageIndex = _pageIndex.clamp(0, section.pages.length - 1);
    history.value++;
    _redraw();
    notifyListeners();
    _scheduleSave();
  }

  int _sectionIndex = 0;
  int _pageIndex = 0;

  /// Locked sections opened since the app was last put away. Never saved.
  final _unlocked = <String>{};

  static String _hash(String sectionId, String pin) =>
      sha256.convert(utf8.encode('spiral-notebook:$sectionId:$pin')).toString();

  bool _lockedId(String sectionId, String? lock) => lock != null && !_unlocked.contains(sectionId);

  /// Whether [s] has a PIN and hasn't been opened with it yet.
  bool isLocked(Section s) => _lockedId(s.id, s.lock);

  /// Whether a torn-out page belongs to a section that is still locked.
  bool isArchiveLocked(ArchivedPage a) {
    final s = sections.where((s) => s.id == a.sectionId).firstOrNull;
    return s != null ? isLocked(s) : _lockedId(a.sectionId, a.sectionLock);
  }

  /// Opens a locked section if [pin] is right.
  bool unlock(Section s, String pin) {
    if (s.lock != _hash(s.id, pin)) return false;
    unlockTrusted(s);
    return true;
  }

  /// Opens a locked section after the device checked a face or fingerprint.
  void unlockTrusted(Section s) {
    _unlocked.add(s.id);
    notifyListeners();
  }

  /// Sets the section's PIN, or removes the lock when [pin] is null.
  void setPin(Section s, String? pin) {
    s.lock = pin == null ? null : _hash(s.id, pin);
    // Whoever just set it stays in until the app is put away.
    _unlocked.add(s.id);
    changed();
  }

  /// Locks every locked section again, as when the app goes to the background.
  void lockAll() {
    if (_unlocked.isEmpty) return;
    _unlocked.clear();
    notifyListeners();
  }

  static Notebook? _parse(List<String> copies) {
    for (final raw in copies) {
      try {
        final nb = Notebook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        nb.sections.expand((s) => s.pages).forEach((p) => p.placeUnplaced());
        return nb;
      } catch (e) {
        debugPrint('A saved copy could not be read, trying the one before: $e');
      }
    }
    return null;
  }

  static Future<Notebook?> _readNotebook(DocStore docs, String id) async => _parse(await docs.read(_doc(id)));

  static ShelfEntry _entryFor(Notebook nb) =>
      ShelfEntry(id: nb.id, title: nb.title, cover: nb.cover, updated: DateTime.now());

  /// Opens the shelf and the notebook that was open last. The first time,
  /// moves the notebook from where older versions of the app kept it.
  static Future<NotebookStore> load({DocStore? docs}) async {
    final store = docs ?? createDocStore();
    Shelf? shelf;
    Notebook? nb;
    var allRead = true;
    try {
      for (final raw in await store.read(_shelfDoc)) {
        try {
          shelf = Shelf.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          break;
        } catch (e) {
          debugPrint('The shelf could not be read, trying the one before: $e');
        }
      }
      if (shelf == null) {
        // First start on this version: bring over the old single notebook.
        final prefs = await SharedPreferences.getInstance();
        final old = prefs.getString(_oldKey);
        nb = old == null ? null : _parse([old]);
        if (old != null && nb == null) allRead = false;
        nb ??= sampleNotebook();
        shelf = Shelf(entries: [_entryFor(nb)], openId: nb.id);
        await store.write(_doc(nb.id), jsonEncode(nb.toJson()));
        await store.write(_shelfDoc, jsonEncode(shelf.toJson()));
        // Kept until the new copy is safely written, then removed.
        if (old != null && allRead) await prefs.remove(_oldKey);
      } else {
        nb = await _readNotebook(store, shelf.openId);
        if (nb == null) {
          allRead = false;
          // The open one is unreadable: open another rather than lose data.
          for (final e in shelf.notebooks) {
            if (e.id == shelf.openId) continue;
            nb = await _readNotebook(store, e.id);
            if (nb != null) {
              shelf.openId = nb.id;
              break;
            }
          }
        }
        if (nb == null) {
          nb = sampleNotebook();
          shelf.entries.add(_entryFor(nb));
          shelf.openId = nb.id;
        }
      }
    } catch (e) {
      debugPrint('Could not load the notebooks, starting fresh: $e');
      allRead = false;
      nb ??= sampleNotebook();
      shelf ??= Shelf(entries: [_entryFor(nb)], openId: nb.id);
    }
    final s = NotebookStore._(nb, shelf, store);
    s.purgeArchive(DateTime.now());
    await s._purgeShelf(DateTime.now());
    unawaited(alarms.init().then((_) => s.syncAlarms()));
    // Photos and videos from erased widgets or long-gone pages. Only when
    // every notebook read correctly, so a damaged save never costs anyone
    // their photos.
    if (allRead) unawaited(s._tidyMedia());
    return s;
  }

  Future<void> _tidyMedia() async {
    final docs = _docs;
    if (docs == null) return;
    try {
      final keep = <String>{...notebook.mediaIds};
      for (final e in shelf.entries) {
        if (e.id == notebook.id) continue;
        final nb = await _readNotebook(docs, e.id);
        if (nb == null) return;
        keep.addAll(nb.mediaIds);
      }
      await mediaStore.removeAllExcept(keep);
    } catch (e) {
      debugPrint('Could not tidy media: $e');
    }
  }

  /// Deletes for good the notebooks deleted more than 30 days ago.
  Future<void> _purgeShelf(DateTime now) async {
    final gone = [
      for (final e in shelf.recentlyDeleted)
        if (!now.isBefore(e.deletedAt!.add(ShelfEntry.keepDeletedFor))) e,
    ];
    if (gone.isEmpty) return;
    for (final e in gone) {
      shelf.entries.remove(e);
      await _docs?.delete(_doc(e.id));
    }
    await _writeShelf();
  }

  Future<void> _writeShelf() async => _docs?.write(_shelfDoc, jsonEncode(shelf.toJson()));

  /// An in-memory store for tests and previews.
  @visibleForTesting
  factory NotebookStore.memory(Notebook nb, {DocStore? docs}) =>
      NotebookStore._(nb, Shelf(entries: [_entryFor(nb)], openId: nb.id), docs);

  /// Opens another notebook from the shelf.
  Future<bool> openNotebook(String id) async {
    if (id == notebook.id) return true;
    await saveNow();
    final docs = _docs;
    final nb = docs == null ? null : await _readNotebook(docs, id);
    if (nb == null) return false;
    _switchTo(nb);
    await _writeShelf();
    return true;
  }

  void _switchTo(Notebook nb) {
    _notebook = nb;
    shelf.openId = nb.id;
    _sectionIndex = 0;
    _pageIndex = 0;
    _unlocked.clear();
    // Other notebooks' alarms stay set on the device; this one's are added.
    _scheduled.clear();
    purgeArchive(DateTime.now());
    _redraw();
    _resetHistory();
    notifyListeners();
    unawaited(syncAlarms());
  }

  /// Puts a new notebook on the shelf and opens it.
  Future<void> newNotebook({required String title, required int cover, Notebook? from}) async {
    await saveNow();
    final nb = from ?? Notebook(title: title, cover: cover, sections: [Section(name: 'Notes', color: 0xFFE57373)]);
    nb
      ..title = title
      ..cover = cover;
    shelf.entries.insert(0, _entryFor(nb));
    await _docs?.write(_doc(nb.id), jsonEncode(nb.toJson()));
    _switchTo(nb);
    await _writeShelf();
  }

  /// Renames a notebook or changes its cover, open or not.
  Future<void> editNotebook(String id, {String? title, int? cover}) async {
    final e = shelf.find(id);
    if (e == null) return;
    if (id == notebook.id) {
      notebook.title = title ?? notebook.title;
      notebook.cover = cover ?? notebook.cover;
      changed();
      await saveNow();
      return;
    }
    final docs = _docs;
    final nb = docs == null ? null : await _readNotebook(docs, id);
    if (nb == null) return;
    nb.title = title ?? nb.title;
    nb.cover = cover ?? nb.cover;
    e
      ..title = nb.title
      ..cover = nb.cover;
    await docs!.write(_doc(id), jsonEncode(nb.toJson()));
    await _writeShelf();
    notifyListeners();
  }

  /// Moves a notebook to "Recently deleted". The last one can't be deleted.
  Future<bool> deleteNotebook(String id) async {
    final e = shelf.find(id);
    if (e == null || shelf.notebooks.length <= 1) return false;
    e.deletedAt = DateTime.now();
    if (id == notebook.id) {
      await saveNow();
      final next = shelf.notebooks.first;
      final docs = _docs;
      final nb = docs == null ? null : await _readNotebook(docs, next.id);
      if (nb == null) {
        e.deletedAt = null;
        return false;
      }
      // Its reminders stop ringing while it's deleted.
      for (final id in _scheduled.keys) {
        await alarms.cancel(id);
      }
      _switchTo(nb);
    } else if (_docs case final docs?) {
      final nb = await _readNotebook(docs, id);
      for (final b in nb?.sections.expand((s) => s.pages).expand((p) => p.blocks) ?? const <Block>[]) {
        if (b.reminder != null) await alarms.cancel(Reminder.alarmId(b.id));
      }
    }
    await _writeShelf();
    notifyListeners();
    return true;
  }

  /// Brings a notebook back from "Recently deleted".
  Future<void> restoreNotebook(String id) async {
    shelf.find(id)?.deletedAt = null;
    await _writeShelf();
    notifyListeners();
  }

  List<Section> get sections => notebook.sections;
  int get sectionIndex => _sectionIndex;
  Section get section => sections[_sectionIndex];
  int get pageIndex => _pageIndex;
  NotePage get page => section.pages[_pageIndex];

  void openSection(int index) {
    _sectionIndex = index.clamp(0, sections.length - 1);
    _pageIndex = 0;
    notifyListeners();
  }

  void openPage(int sectionIndex, int pageIndex) {
    _sectionIndex = sectionIndex.clamp(0, sections.length - 1);
    _pageIndex = pageIndex.clamp(0, section.pages.length - 1);
    notifyListeners();
  }

  /// Moves by [delta] pages, adding a fresh page when turning past the last one.
  /// Makes sure [section] has a page at [index], adding blank ones if needed.
  void ensurePage(int index) {
    var added = false;
    while (index >= section.pages.length) {
      section.pages.add(NotePage(paper: page.paper));
      added = true;
    }
    if (added) changed();
  }

  void turnPage(int delta) {
    final target = _pageIndex + delta;
    if (target < 0) return;
    while (target >= section.pages.length) {
      section.pages.add(NotePage(paper: page.paper));
      _scheduleSave();
    }
    _pageIndex = target;
    notifyListeners();
  }

  void addSection(String name, int color) {
    sections.add(Section(name: name, color: color));
    _sectionIndex = sections.length - 1;
    _pageIndex = 0;
    changed();
  }

  void renameSection(Section s, String name, int color) {
    s.name = name;
    s.color = color;
    changed();
  }

  /// Removes a section. Its pages go to the archive, so they can be restored.
  void deleteSection(Section s, {DateTime? now}) {
    if (sections.length <= 1) return;
    final when = now ?? DateTime.now();
    for (final p in s.pages.where((p) => p.blocks.isNotEmpty || p.title.isNotEmpty)) {
      _archive(s, p, when);
    }
    sections.remove(s);
    _sectionIndex = _sectionIndex.clamp(0, sections.length - 1);
    _pageIndex = 0;
    changed();
  }

  /// Tears a page out into the archive. A section always keeps one page.
  ArchivedPage tearOut(Section s, NotePage p, {DateTime? now}) {
    final archived = _archive(s, p, now ?? DateTime.now());
    final at = s.pages.indexOf(p);
    s.pages.remove(p);
    if (s.pages.isEmpty) s.pages.add(NotePage(paper: p.paper));
    if (s == section && at < _pageIndex) _pageIndex--;
    _pageIndex = _pageIndex.clamp(0, section.pages.length - 1);
    changed();
    return archived;
  }

  ArchivedPage _archive(Section s, NotePage p, DateTime when) {
    final a = ArchivedPage(
      page: p,
      sectionId: s.id,
      sectionName: s.name,
      sectionColor: s.color,
      tornAt: when,
      sectionLock: s.lock,
    );
    notebook.archive.insert(0, a);
    return a;
  }

  List<ArchivedPage> get archive => notebook.archive;

  /// Puts a torn-out page back at the end of its section (recreating the
  /// section if it was deleted) and opens it.
  void restore(ArchivedPage a) {
    notebook.archive.remove(a);
    var target = sections.where((s) => s.id == a.sectionId).firstOrNull;
    if (target == null) {
      target = Section(id: a.sectionId, name: a.sectionName, color: a.sectionColor, pages: [], lock: a.sectionLock);
      sections.add(target);
    }
    // A blank placeholder page is replaced rather than kept in front.
    if (target.pages.length == 1 && target.pages.first.blocks.isEmpty && target.pages.first.title.isEmpty) {
      target.pages.clear();
    }
    target.pages.add(a.page);
    _sectionIndex = sections.indexOf(target);
    _pageIndex = target.pages.length - 1;
    changed();
  }

  void deleteForever(ArchivedPage a) {
    notebook.archive.remove(a);
    changed();
  }

  /// Deletes torn-out pages older than 30 days.
  void purgeArchive(DateTime now) {
    final before = notebook.archive.length;
    notebook.archive.removeWhere((a) => !now.isBefore(a.deleteAt));
    if (notebook.archive.length != before) _scheduleSave();
  }

  /// Swaps in a notebook restored from a backup, opening its first page.
  void replaceWith(Notebook nb) {
    notebook
      ..title = nb.title
      ..cover = nb.cover
      ..look = nb.look
      ..tone = nb.tone
      ..showPhoneCalendar = nb.showPhoneCalendar;
    notebook.sections
      ..clear()
      ..addAll(nb.sections);
    notebook.archive
      ..clear()
      ..addAll(nb.archive);
    _sectionIndex = 0;
    _pageIndex = 0;
    _unlocked.clear();
    _redraw();
    changed();
  }

  /// Adds [pages] after the last page of the open section and opens the first.
  void addPages(List<NotePage> pages) {
    if (pages.isEmpty) return;
    // A blank last page is replaced rather than left behind.
    final last = section.pages.last;
    if (last.blocks.isEmpty && last.strokes.isEmpty && last.title.isEmpty && last.background == null) {
      section.pages.removeLast();
    }
    _pageIndex = section.pages.length;
    section.pages.addAll(pages);
    changed();
  }

  /// Lays a template onto the open page if it's still empty, otherwise onto
  /// a new page right after it, and opens that page.
  void useTemplate(NotePage template) {
    final current = page;
    if (current.blocks.isEmpty && current.strokes.isEmpty && current.title.isEmpty && current.background == null) {
      current
        ..title = template.title
        ..paper = template.paper
        ..blocks.addAll(template.blocks);
    } else {
      _pageIndex++;
      section.pages.insert(_pageIndex, template);
    }
    changed();
  }

  /// Puts a new block on [page] in a free spot and saves.
  void addBlock(NotePage page, Block block) {
    if (!block.isPlaced) page.placeNew(block);
    page.blocks.add(block);
    changed();
  }

  /// Moves [block] from [page] to the page before (-1) or after (+1) it,
  /// adding a page at the end if needed. Null if there's no page before.
  ({int sectionIndex, int pageIndex})? moveBlockToNeighbour(NotePage page, Block block, int delta) {
    for (var s = 0; s < sections.length; s++) {
      final pages = sections[s].pages;
      final at = pages.indexOf(page);
      if (at < 0) continue;
      final to = at + delta;
      if (to < 0) return null;
      if (to >= pages.length) pages.add(NotePage(paper: page.paper));
      page.blocks.remove(block);
      pages[to].blocks.add(block);
      changed();
      return (sectionIndex: s, pageIndex: to);
    }
    return null;
  }

  /// Moves a block above the others on its page.
  void bringToFront(NotePage page, Block block) {
    if (page.blocks.last == block) return;
    page.blocks
      ..remove(block)
      ..add(block);
    changed();
  }

  /// Every reminder in the notebook, soonest first. Torn-out pages don't ring.
  List<SetReminder> get reminders {
    final all = <SetReminder>[];
    for (var s = 0; s < sections.length; s++) {
      final sec = sections[s];
      for (var p = 0; p < sec.pages.length; p++) {
        for (final b in sec.pages[p].blocks) {
          if (b.reminder != null) all.add(SetReminder(sec, sec.pages[p], b, s, p));
        }
      }
    }
    return all..sort((a, b) => a.reminder.at.compareTo(b.reminder.at));
  }

  /// Sets, moves or (with null) removes a block's reminder. Its event in the
  /// phone's calendar is replaced too, or removed.
  Future<void> setReminder(Block block, Reminder? reminder, {bool addToPhoneCalendar = false}) async {
    final oldEvent = block.reminder?.calendarEventId;
    if (oldEvent != null) await phoneCalendar.remove(oldEvent);
    block.reminder = reminder;
    if (reminder != null && addToPhoneCalendar) {
      final where = reminders.where((r) => r.block == block).firstOrNull;
      reminder.calendarEventId = await phoneCalendar.add(
        reminderLabel(block),
        reminder.at,
        where == null ? 'From your notebook' : 'From your notebook: ${where.section.name}, page ${where.pageIndex + 1}',
      );
    }
    changed();
    await syncAlarms();
  }

  final _scheduled = <int, DateTime>{};

  /// Brings the device's alarms in line with the notebook: one for each
  /// reminder still to come, none for erased widgets or torn-out pages.
  Future<void> syncAlarms({DateTime? now}) async {
    final when = now ?? DateTime.now();
    final wanted = <int, SetReminder>{
      for (final r in reminders)
        if (!r.reminder.rang && r.reminder.at.isAfter(when)) Reminder.alarmId(r.block.id): r,
    };
    for (final id in _scheduled.keys.toList()) {
      if (wanted[id]?.reminder.at != _scheduled[id]) {
        _scheduled.remove(id);
        await alarms.cancel(id);
      }
    }
    for (final MapEntry(key: id, value: r) in wanted.entries) {
      if (_scheduled[id] == r.reminder.at) continue;
      _scheduled[id] = r.reminder.at;
      // A locked section's reminder doesn't show its words on the lock screen.
      await alarms.schedule(
        id,
        r.reminder.at,
        r.section.lock != null ? 'Notebook reminder' : r.section.name,
        r.section.lock != null ? 'A reminder in a locked section' : reminderLabel(r.block),
      );
    }
  }

  /// Reminders whose time has come but which haven't rung in the app yet.
  /// Marks them as rung.
  List<SetReminder> takeDue(DateTime now) {
    final due = [
      for (final r in reminders)
        if (!r.reminder.rang && !r.reminder.at.isAfter(now)) r,
    ];
    if (due.isEmpty) return due;
    for (final r in due) {
      r.reminder.rang = true;
    }
    changed();
    return due;
  }

  /// Call after editing any model so the change is shown and saved.
  void changed() {
    notifyListeners();
    _markDirty();
    _scheduleSave();
  }

  /// Like [changed], but without rebuilding listeners. Used while typing,
  /// where the text field already shows the new text.
  void changedQuietly() {
    _markDirty();
    _scheduleSave();
  }

  void _markDirty() {
    if (_dirty) return;
    _dirty = true;
    history.value++;
  }

  void _scheduleSave() {
    if (_docs == null) return;
    _saveTimer?.cancel();
    saveState.value = SaveState.saving;
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final docs = _docs;
    if (docs == null) return;
    try {
      await docs.write(_doc(notebook.id), checkpoint());
      var e = shelf.find(notebook.id);
      if (e == null) shelf.entries.add(e = _entryFor(notebook));
      e
        ..title = notebook.title
        ..cover = notebook.cover
        ..updated = DateTime.now();
      await _writeShelf();
      // Erased widgets and torn-out pages stop ringing.
      unawaited(syncAlarms());
      saveState.value = SaveState.saved;
    } catch (e) {
      debugPrint('Save failed: $e');
      saveState.value = SaveState.failed;
    }
  }

  /// Every page whose text contains [query], newest section order first.
  List<SearchHit> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final hits = <SearchHit>[];
    for (var s = 0; s < sections.length; s++) {
      final sec = sections[s];
      if (isLocked(sec)) continue;
      for (var p = 0; p < sec.pages.length; p++) {
        final text = sec.pages[p].searchableText;
        final at = text.toLowerCase().indexOf(q);
        if (at < 0) continue;
        final start = (at - 30).clamp(0, text.length);
        final end = (at + q.length + 40).clamp(0, text.length);
        hits.add(SearchHit(sectionIndex: s, pageIndex: p, snippet: text.substring(start, end).replaceAll('\n', ' · ')));
      }
    }
    return hits;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    saveState.dispose();
    appearance.dispose();
    history.dispose();
    super.dispose();
  }
}

/// A reminder and where it lives.
class SetReminder {
  SetReminder(this.section, this.page, this.block, this.sectionIndex, this.pageIndex);
  final Section section;
  final NotePage page;
  final Block block;
  final int sectionIndex;
  final int pageIndex;
  Reminder get reminder => block.reminder!;
}

/// A few words saying what a reminder is about.
String reminderLabel(Block b) {
  String firstLine(String t) => t
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s'), '').trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  final text = switch (b) {
    TextBlock(:final text) => firstLine(text),
    StickyBlock(:final text) => firstLine(text),
    ChecklistBlock(:final items) => items.map((i) => i.text.trim()).where((t) => t.isNotEmpty).take(2).join(', '),
    SheetBlock() => 'Your spreadsheet',
    CalculatorBlock() => 'Your calculator',
    MediaBlock(:final note, :final name) => firstLine(note).isNotEmpty ? firstLine(note) : name,
  };
  final fallback = switch (b) {
    ChecklistBlock() => 'Your checklist',
    StickyBlock() => 'Your sticky note',
    MediaBlock(:final kind) => kind == MediaKind.video ? 'Your video' : 'Your photo',
    _ => 'Your note',
  };
  final label = text.isEmpty ? fallback : text;
  return label.length > 80 ? '${label.substring(0, 79)}…' : label;
}

class SearchHit {
  SearchHit({required this.sectionIndex, required this.pageIndex, required this.snippet});
  final int sectionIndex;
  final int pageIndex;
  final String snippet;
}
