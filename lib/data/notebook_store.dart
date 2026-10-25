import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notebook.dart';
import 'media/media_store.dart';
import 'sample_notebook.dart';

enum SaveState { saved, saving, failed }

/// Holds the notebook in memory and saves it on the device a moment after
/// each change. Widgets edit the models directly, then call [changed].
class NotebookStore extends ChangeNotifier {
  NotebookStore._(this.notebook, this._prefs);

  static const _key = 'notebook.v1';
  static const _saveDelay = Duration(milliseconds: 600);

  final Notebook notebook;
  final SharedPreferences? _prefs;
  Timer? _saveTimer;

  /// Kept separate from the notebook so the save badge can update
  /// without rebuilding the pages.
  final saveState = ValueNotifier(SaveState.saved);

  /// The chosen look and paper colour. The app rebuilds its screen on change.
  late final appearance = ValueNotifier((notebook.look, notebook.tone));

  void setAppearance({Look? look, PaperTone? tone}) {
    notebook.look = look ?? notebook.look;
    notebook.tone = tone ?? notebook.tone;
    appearance.value = (notebook.look, notebook.tone);
    changed();
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

  static Future<NotebookStore> load() async {
    SharedPreferences? prefs;
    Notebook? nb;
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        nb = Notebook.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
      nb?.sections.expand((s) => s.pages).forEach((p) => p.placeUnplaced());
    } catch (e) {
      debugPrint('Could not load notebook, starting fresh: $e');
    }
    final store = NotebookStore._(nb ?? sampleNotebook(), prefs);
    store.purgeArchive(DateTime.now());
    // Photos and videos from erased widgets or long-gone pages. Only once
    // the notebook loaded, so a damaged save never costs anyone their photos.
    if (nb != null) {
      unawaited(
        mediaStore.removeAllExcept(store.notebook.mediaIds).catchError((Object e) {
          debugPrint('Could not tidy media: $e');
        }),
      );
    }
    return store;
  }

  /// An in-memory store for tests and previews.
  @visibleForTesting
  factory NotebookStore.memory(Notebook nb) => NotebookStore._(nb, null);

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
      ..look = nb.look
      ..tone = nb.tone;
    notebook.sections
      ..clear()
      ..addAll(nb.sections);
    notebook.archive
      ..clear()
      ..addAll(nb.archive);
    _sectionIndex = 0;
    _pageIndex = 0;
    _unlocked.clear();
    appearance.value = (notebook.look, notebook.tone);
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

  /// Moves a block above the others on its page.
  void bringToFront(NotePage page, Block block) {
    if (page.blocks.last == block) return;
    page.blocks
      ..remove(block)
      ..add(block);
    changed();
  }

  /// Call after editing any model so the change is shown and saved.
  void changed() {
    notifyListeners();
    _scheduleSave();
  }

  /// Like [changed], but without rebuilding listeners. Used while typing,
  /// where the text field already shows the new text.
  void changedQuietly() => _scheduleSave();

  void _scheduleSave() {
    if (_prefs == null) return;
    _saveTimer?.cancel();
    saveState.value = SaveState.saving;
    _saveTimer = Timer(_saveDelay, saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final ok = await prefs.setString(_key, jsonEncode(notebook.toJson()));
      saveState.value = ok ? SaveState.saved : SaveState.failed;
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
    super.dispose();
  }
}

class SearchHit {
  SearchHit({required this.sectionIndex, required this.pageIndex, required this.snippet});
  final int sectionIndex;
  final int pageIndex;
  final String snippet;
}
