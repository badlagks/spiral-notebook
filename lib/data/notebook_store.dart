import 'dart:async';
import 'dart:convert';

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
      unawaited(mediaStore.removeAllExcept(store.notebook.mediaIds).catchError((Object e) {
        debugPrint('Could not tidy media: $e');
      }));
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
      target = Section(id: a.sectionId, name: a.sectionName, color: a.sectionColor, pages: []);
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
      for (var p = 0; p < sec.pages.length; p++) {
        final text = sec.pages[p].searchableText;
        final at = text.toLowerCase().indexOf(q);
        if (at < 0) continue;
        final start = (at - 30).clamp(0, text.length);
        final end = (at + q.length + 40).clamp(0, text.length);
        hits.add(SearchHit(
          sectionIndex: s,
          pageIndex: p,
          snippet: text.substring(start, end).replaceAll('\n', ' · '),
        ));
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
