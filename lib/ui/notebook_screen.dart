import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/notebook_store.dart';
import '../models/notebook.dart';
import 'paper_page.dart';
import 'paper_painters.dart';
import 'search_dialog.dart';
import 'section_tabs.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Widths at or above this show an open two-page spread (Mac, Chromebook,
/// tablets); narrower screens show one page at a time (phones).
const spreadBreakpoint = 860.0;

class NotebookScreen extends StatelessWidget {
  const NotebookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final spread = constraints.maxWidth >= spreadBreakpoint;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => showNotebookSearch(context),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => showNotebookSearch(context),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => store.turnPage(spread ? 2 : 1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => store.turnPage(spread ? -2 : -1),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.3),
                  radius: 1.2,
                  colors: [Color(0xFF4A4540), Paper.desk],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    _TopBar(spread: spread),
                    Expanded(child: spread ? const _Spread() : const _SinglePage()),
                    if (!spread) const _PageBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.spread});
  final bool spread;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final section = store.section;
    final left = spread ? store.pageIndex - store.pageIndex % 2 : store.pageIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
      child: Row(
        children: [
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
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          if (spread) ...[
            const SizedBox(width: 12),
            _turnButton(context, Icons.chevron_left, 'Previous pages', left > 0 ? () => store.turnPage(-2) : null),
            Text(
              'Pages ${left + 1}–${left + 2}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            _turnButton(context, Icons.chevron_right, 'Next pages', () => store.turnPage(2)),
          ],
          const Spacer(),
          const _SaveBadge(),
          const SizedBox(width: 8),
          spread
              ? SizedBox(
                  width: 220,
                  height: 32,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white60,
                      side: const BorderSide(color: Colors.white24),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed: () => showNotebookSearch(context),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search'),
                  ),
                )
              : IconButton(
                  tooltip: 'Search',
                  color: Colors.white70,
                  onPressed: () => showNotebookSearch(context),
                  icon: const Icon(Icons.search),
                ),
        ],
      ),
    );
  }

  Widget _turnButton(BuildContext context, IconData icon, String tip, VoidCallback? onTap) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        color: Colors.white70,
        disabledColor: Colors.white24,
        onPressed: onTap,
        icon: Icon(icon),
      );
}

/// Shows that notes are saved on this device (sync between devices comes later).
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
              Icon(icon, size: 16, color: state == SaveState.failed ? Colors.redAccent : Colors.white54),
              if (MediaQuery.sizeOf(context).width > 520) ...[
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// A leather cover with pages laid on it.
class _Cover extends StatelessWidget {
  const _Cover({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Paper.cover, Paper.coverDark],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: DecoratedBox(
        // A few page edges peeking out under the top sheet.
        decoration: const BoxDecoration(
          color: Paper.sheetEdge,
          borderRadius: BorderRadius.all(Radius.circular(3)),
          boxShadow: [BoxShadow(color: Color(0x44000000), blurRadius: 3, offset: Offset(1, 2))],
        ),
        child: Padding(
          padding: const EdgeInsets.only(right: 2, bottom: 2),
          child: ClipRRect(borderRadius: BorderRadius.circular(3), child: child),
        ),
      ),
    );
  }
}

class _Spread extends StatelessWidget {
  const _Spread();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final section = store.section;
    final left = store.pageIndex - store.pageIndex % 2;
    final right = left + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 8, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Cover(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Row(
                  key: ValueKey('${section.id}-$left'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: PaperPage(
                        key: ValueKey(section.pages[left].id),
                        section: section,
                        page: section.pages[left],
                        pageNumber: left + 1,
                        bindingOnLeft: false,
                      ),
                    ),
                    const SizedBox(
                      width: 34,
                      child: ColoredBox(
                        color: Color(0xFFE9DFC8),
                        child: CustomPaint(painter: SpiralPainter()),
                      ),
                    ),
                    Expanded(
                      child: right < section.pages.length
                          ? PaperPage(
                              key: ValueKey(section.pages[right].id),
                              section: section,
                              page: section.pages[right],
                              pageNumber: right + 1,
                              bindingOnLeft: true,
                            )
                          : _BlankPage(onStart: () => store.ensurePage(right)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SectionTabs(),
        ],
      ),
    );
  }
}

class _SinglePage extends StatelessWidget {
  const _SinglePage();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final section = store.section;
    final page = store.page;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 0, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Cover(
              child: GestureDetector(
                // Swipe sideways to turn the page.
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -300) store.turnPage(1);
                  if (v > 300) store.turnPage(-1);
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: PaperPage(
                          key: ValueKey(page.id),
                          section: section,
                          page: page,
                          pageNumber: store.pageIndex + 1,
                          bindingOnLeft: true,
                        ),
                      ),
                    ),
                    const Positioned(
                      left: -6,
                      top: 0,
                      bottom: 0,
                      width: 30,
                      child: IgnorePointer(child: CustomPaint(painter: SpiralPainter())),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SectionTabs(tabWidth: 28, tabHeight: 78),
        ],
      ),
    );
  }
}

class _BlankPage extends StatelessWidget {
  const _BlankPage({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PaperPainter(style: PaperStyle.ruled, bindingOnLeft: true),
      child: Center(
        child: TextButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.edit_outlined, color: Pen.pencil),
          label: Text('Start a new page', style: handwriting.copyWith(color: Pen.pencil)),
        ),
      ),
    );
  }
}

class _PageBar extends StatelessWidget {
  const _PageBar();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final last = store.pageIndex == store.section.pages.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            color: Colors.white70,
            disabledColor: Colors.white24,
            onPressed: store.pageIndex > 0 ? () => store.turnPage(-1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            'Page ${store.pageIndex + 1} of ${store.section.pages.length}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          IconButton(
            tooltip: last ? 'New page' : 'Next page',
            color: Colors.white70,
            onPressed: () => store.turnPage(1),
            icon: Icon(last ? Icons.note_add_outlined : Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
