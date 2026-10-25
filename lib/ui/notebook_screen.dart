import 'dart:ui' show DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/notebook_store.dart';
import '../models/notebook.dart';
import 'archive_dialog.dart';
import 'calendar_screen.dart';
import 'ink.dart';
import 'look_picker.dart';
import 'notebook_actions.dart';
import 'page_overview.dart';
import 'template_picker.dart';
import 'page_flip.dart';
import 'paper_page.dart';
import 'reminders_ui.dart';
import 'search_dialog.dart';
import 'section_lock.dart';
import 'section_tabs.dart';
import 'shelf_screen.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Whether the screen shows two pages with the coil in the middle: laptops,
/// tablets in landscape and phones held sideways. Upright phones and
/// tablets show one page with the coil down its left edge.
bool showsSpread(Size size) => (size.width > size.height && size.width >= 560) || size.width >= 1100;

/// Where a book-style foldable (Galaxy Z Fold, Pixel Fold) folds, as an x
/// position on screen, while it is open with the fold running top to bottom.
/// Null on other screens, and on a flip phone, whose fold runs across.
double? verticalFoldX(MediaQueryData mq) {
  for (final f in mq.displayFeatures) {
    if (f.type == DisplayFeatureType.cutout) continue;
    final b = f.bounds;
    if (b.height >= b.width && b.height > mq.size.height / 2 && b.center.dx > 0 && b.center.dx < mq.size.width) {
      return b.center.dx;
    }
  }
  return null;
}

/// The leather cover's margin around the pages, in paper units.
const _coverMargin = 8.0;

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key});

  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  final _flip = FlipController();

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        // An open foldable shows two pages with the coil down the fold, like a real notebook.
        final foldX = Paper.plain ? null : verticalFoldX(mq);
        final spread = showsSpread(constraints.biggest) || foldX != null;
        final store = StoreScope.read(context);
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => showNotebookSearch(context),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => showNotebookSearch(context),
            const SingleActivator(LogicalKeyboardKey.pageDown): () => _flip.flip(1),
            const SingleActivator(LogicalKeyboardKey.pageUp): () => _flip.flip(-1),
            // A text box being typed in handles these itself, letter by letter.
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): store.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): store.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true): store.redo,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): store.redo,
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): store.redo,
          },
          child: Focus(
            autofocus: true,
            child: ReminderWatcher(
              child: Scaffold(
                body: DecoratedBox(
                  decoration: Paper.plain
                      ? BoxDecoration(color: Paper.sheet)
                      : const BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment(0, -0.3),
                            radius: 1.2,
                            colors: [Color(0xFF4A4540), Paper.desk],
                          ),
                        ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        _TopBar(spread: spread, flip: _flip),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _Book(
                                  spread: spread,
                                  flip: _flip,
                                  foldX: foldX == null ? null : foldX - mq.padding.left,
                                ),
                              ),
                              if (InkScope.of(context).drawing)
                                const Positioned(left: 8, right: 8, bottom: 8, child: Center(child: DrawToolbar())),
                            ],
                          ),
                        ),
                        if (!spread) _PageBar(flip: _flip),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.spread, required this.flip});
  final bool spread;
  final FlipController flip;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final section = store.section;
    final narrow = MediaQuery.sizeOf(context).width < 520;
    final left = store.pageIndex - store.pageIndex % 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          _iconButton(Icons.collections_bookmark_outlined, 'All notebooks', () => showShelf(context)),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: Color(section.color), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              section.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Chrome.strong, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (spread) ...[
            const SizedBox(width: 8),
            _iconButton(Icons.chevron_left, 'Previous pages', left > 0 ? () => flip.flip(-1) : null),
            Text('Pages ${left + 1}–${left + 2}', style: TextStyle(color: Chrome.normal, fontSize: 13)),
            _iconButton(Icons.chevron_right, 'Next pages', () => flip.flip(1)),
          ],
          const Spacer(),
          const _SaveBadge(),
          const SizedBox(width: 4),
          _UndoButtons(withRedo: !narrow),
          _iconButton(Icons.grid_view_outlined, 'All pages', () => showPageOverview(context)),
          _iconButton(Icons.calendar_month_outlined, 'Calendar', () => showCalendar(context)),
          const _MoreMenu(),
          const _DrawButton(),
          const SizedBox(width: 4),
          _ArchiveButton(count: store.archive.where((a) => !store.isArchiveLocked(a)).length),
          if (spread && !narrow)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 200,
                height: 32,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Chrome.normal,
                    side: BorderSide(color: Chrome.faint),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: () => showNotebookSearch(context),
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Search'),
                ),
              ),
            )
          else
            _iconButton(Icons.search, 'Search', () => showNotebookSearch(context)),
        ],
      ),
    );
  }
}

Widget _iconButton(IconData icon, String tip, VoidCallback? onTap) => IconButton(
  tooltip: tip,
  visualDensity: VisualDensity.compact,
  color: Chrome.normal,
  disabledColor: Chrome.faint,
  onPressed: onTap,
  icon: Icon(icon),
);

/// Settings and things done to the whole notebook.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.menu, color: Chrome.normal),
      onSelected: (v) => switch (v) {
        'redo' => StoreScope.read(context).redo(),
        'look' => showLookPicker(context),
        'backup' => backUpNotebook(context),
        'restore' => restoreNotebook(context),
        'pdf' => importPdf(context),
        _ => null,
      },
      itemBuilder: (_) => [
        if (MediaQuery.sizeOf(context).width < 520) ...[
          PopupMenuItem(
            value: 'redo',
            enabled: StoreScope.read(context).canRedo,
            child: const ListTile(leading: Icon(Icons.redo), title: Text('Redo')),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: 'look',
          child: ListTile(leading: Icon(Icons.palette_outlined), title: Text('Look and paper colour')),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'backup',
          child: ListTile(leading: Icon(Icons.save_alt), title: Text('Back up notebook')),
        ),
        const PopupMenuItem(
          value: 'restore',
          child: ListTile(leading: Icon(Icons.restore), title: Text('Restore from a backup')),
        ),
        const PopupMenuItem(
          value: 'pdf',
          child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Import a PDF to write on')),
        ),
      ],
    );
  }
}

/// Takes back the last change, whatever it was, or puts it back again.
class _UndoButtons extends StatelessWidget {
  const _UndoButtons({required this.withRedo});
  final bool withRedo;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    return ValueListenableBuilder(
      valueListenable: store.history,
      builder: (context, _, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconButton(Icons.undo, 'Undo', store.canUndo ? store.undo : null),
          if (withRedo) _iconButton(Icons.redo, 'Redo', store.canRedo ? store.redo : null),
        ],
      ),
    );
  }
}

/// Switches between writing (tap widgets, type) and drawing on the paper.
class _DrawButton extends StatelessWidget {
  const _DrawButton();

  @override
  Widget build(BuildContext context) {
    final ink = InkScope.of(context);
    return IconButton(
      tooltip: ink.drawing ? 'Stop drawing' : 'Draw on the paper',
      visualDensity: VisualDensity.compact,
      isSelected: ink.drawing,
      style: IconButton.styleFrom(
        backgroundColor: ink.drawing ? (Paper.plain ? const Color(0xFFE3ECF8) : Colors.white) : null,
        foregroundColor: ink.drawing ? const Color(0xFF1F3A73) : Chrome.normal,
      ),
      onPressed: () {
        FocusScope.of(context).unfocus();
        ink.drawing = !ink.drawing;
      },
      icon: const Icon(Icons.draw_outlined),
    );
  }
}

class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Torn-out pages',
      visualDensity: VisualDensity.compact,
      color: Chrome.normal,
      onPressed: () => showArchive(context),
      icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.inventory_2_outlined)),
    );
  }
}

/// Shows that notes are saved on this device. The app works fully offline.
class _SaveBadge extends StatelessWidget {
  const _SaveBadge();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    return ValueListenableBuilder(
      valueListenable: store.saveState,
      builder: (context, state, _) {
        final (icon, label) = switch (state) {
          SaveState.saved => (Icons.check_circle_outline, 'Saved on this device'),
          SaveState.saving => (Icons.sync, 'Saving…'),
          SaveState.failed => (Icons.error_outline, 'Not saved'),
        };
        return Tooltip(
          message: label,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: state == SaveState.failed ? Colors.redAccent : Chrome.quiet),
              if (MediaQuery.sizeOf(context).width > 1000) ...[
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: Chrome.quiet, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The notebook itself: the cover, the pages (scaled to fit) and the tabs.
class _Book extends StatelessWidget {
  const _Book({required this.spread, required this.flip, this.foldX});
  final bool spread;

  /// Where the screen folds, measured from the book's left edge.
  final double? foldX;
  final FlipController flip;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final section = store.section;

    Widget buildPage(int index, {required bool bindingOnLeft, required bool interactive}) {
      if (index < 0) return const SizedBox.shrink();
      if (index >= section.pages.length) {
        return BlankSheet(
          bindingOnLeft: bindingOnLeft,
          onStart: interactive ? () => store.ensurePage(index) : null,
          onTemplate: interactive
              ? () async {
                  final template = await showTemplatePicker(context);
                  if (template == null) return;
                  store.ensurePage(index);
                  store.openPage(store.sectionIndex, index);
                  store.useTemplate(template);
                }
              : null,
        );
      }
      final page = section.pages[index];
      return PaperPage(
        key: ValueKey(page.id),
        section: section,
        page: page,
        pageNumber: index + 1,
        bindingOnLeft: bindingOnLeft,
        interactive: interactive,
      );
    }

    // A locked section shows one closed sheet until its PIN is typed.
    final Widget pages = store.isLocked(section)
        ? Builder(
            builder: (_) => SizedBox(
              width: spread ? pageWidth * 2 + spineWidth : pageWidth,
              height: pageHeight,
              child: LockedSheet(section: section),
            ),
          )
        : FlippingBook(spread: spread, controller: flip, buildPage: buildPage);

    // Plain paper: the pages fill the screen, with the sections along the top.
    if (Paper.plain) {
      return Column(
        children: [
          const SectionChips(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 4),
              child: LayoutBuilder(
                builder: (context, c) {
                  fitPaper(c.biggest, spread: spread, gutter: spineWidth, content: contentExtent(store.notebook));
                  return FittedBox(alignment: Alignment.topCenter, child: pages);
                },
              ),
            ),
          ),
        ],
      );
    }

    final book = Container(
      padding: const EdgeInsets.all(_coverMargin),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(store.notebook.cover), Paper.shade(Color(store.notebook.cover))],
        ),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(1, 2))],
        ),
        child: pages,
      ),
    );

    const tabsWidth = 48.0;
    final padLeft = spread ? 20.0 : 8.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(padLeft, 6, 0, spread ? 16 : 4),
      child: LayoutBuilder(
        builder: (context, box) {
          // On a foldable, shift the book so its coil sits right on the fold.
          var leftGap = 0.0, rightGap = 0.0;
          if (foldX != null) {
            final shift = 2 * (foldX! - padLeft) - (box.maxWidth - tabsWidth);
            if (shift > 0) {
              leftGap = shift;
            } else {
              rightGap = -shift;
            }
          }
          // The paper takes the shape of the room it has.
          fitPaper(
            Size(box.maxWidth - tabsWidth - leftGap - rightGap, box.maxHeight),
            spread: spread,
            gutter: spineWidth,
            frame: _coverMargin * 2,
            content: contentExtent(store.notebook),
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: leftGap),
              Expanded(child: FittedBox(child: book)),
              SizedBox(width: rightGap),
              // Short screens (a phone held sideways) get shorter tabs so they all fit.
              SizedBox(
                width: tabsWidth,
                child: LayoutBuilder(
                  builder: (context, c) => SectionTabs(
                    tabWidth: spread ? 34 : 28,
                    tabHeight: ((c.maxHeight - 80) / (store.sections.length + 0.5)).clamp(48.0, spread ? 92.0 : 78.0),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Page controls under the single page on an upright phone.
class _PageBar extends StatelessWidget {
  const _PageBar({required this.flip});
  final FlipController flip;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (store.isLocked(store.section)) return const SizedBox(height: 48);
    final first = store.pageIndex == 0;
    final last = store.pageIndex == store.section.pages.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Chrome.normal, disabledForegroundColor: Chrome.faint),
            onPressed: first ? null : () => flip.flip(-1),
            icon: const Icon(Icons.chevron_left),
            label: const Text('Back'),
          ),
          // Tapping the page count shows all the pages.
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Chrome.normal),
            onPressed: () => showPageOverview(context),
            child: Text('${store.pageIndex + 1} / ${store.section.pages.length}', style: const TextStyle(fontSize: 13)),
          ),
          Directionality(
            textDirection: TextDirection.rtl,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Chrome.normal),
              onPressed: () => flip.flip(1),
              icon: Icon(last ? Icons.note_add_outlined : Icons.chevron_left),
              label: Text(last ? 'New page' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}
