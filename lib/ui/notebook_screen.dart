import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/notebook_store.dart';
import 'archive_dialog.dart';
import 'page_flip.dart';
import 'paper_page.dart';
import 'search_dialog.dart';
import 'section_tabs.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Whether the screen shows two pages with the coil in the middle: laptops,
/// tablets in landscape and phones held sideways. Upright phones and
/// tablets show one page with the coil down its left edge.
bool showsSpread(Size size) => (size.width > size.height && size.width >= 560) || size.width >= 1100;

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
    return LayoutBuilder(builder: (context, constraints) {
      final spread = showsSpread(constraints.biggest);
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => showNotebookSearch(context),
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => showNotebookSearch(context),
          const SingleActivator(LogicalKeyboardKey.pageDown): () => _flip.flip(1),
          const SingleActivator(LogicalKeyboardKey.pageUp): () => _flip.flip(-1),
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
                    _TopBar(spread: spread, flip: _flip),
                    Expanded(child: _Book(spread: spread, flip: _flip)),
                    if (!spread) _PageBar(flip: _flip),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
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
            const SizedBox(width: 8),
            _iconButton(Icons.chevron_left, 'Previous pages', left > 0 ? () => flip.flip(-1) : null),
            Text('Pages ${left + 1}–${left + 2}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            _iconButton(Icons.chevron_right, 'Next pages', () => flip.flip(1)),
          ],
          const Spacer(),
          const _SaveBadge(),
          const SizedBox(width: 4),
          _ArchiveButton(count: store.archive.length),
          if (spread && !narrow)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: SizedBox(
                width: 200,
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
      color: Colors.white70,
      disabledColor: Colors.white24,
      onPressed: onTap,
      icon: Icon(icon),
    );

class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Torn-out pages',
      visualDensity: VisualDensity.compact,
      color: Colors.white70,
      onPressed: () => showArchive(context),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.inventory_2_outlined),
      ),
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
              Icon(icon, size: 16, color: state == SaveState.failed ? Colors.redAccent : Colors.white54),
              if (MediaQuery.sizeOf(context).width > 700) ...[
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

/// The notebook itself: the cover, the pages (scaled to fit) and the tabs.
class _Book extends StatelessWidget {
  const _Book({required this.spread, required this.flip});
  final bool spread;
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

    final book = Container(
      padding: const EdgeInsets.all(_coverMargin),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Paper.cover, Paper.coverDark],
        ),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(1, 2))],
        ),
        child: FlippingBook(spread: spread, controller: flip, buildPage: buildPage),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(spread ? 20 : 8, 6, 0, spread ? 16 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: FittedBox(child: book)),
          // Short screens (a phone held sideways) get shorter tabs so they all fit.
          LayoutBuilder(
            builder: (context, c) => SectionTabs(
              tabWidth: spread ? 34 : 28,
              tabHeight: ((c.maxHeight - 80) / (store.sections.length + 0.5)).clamp(48.0, spread ? 92.0 : 78.0),
            ),
          ),
        ],
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
    final first = store.pageIndex == 0;
    final last = store.pageIndex == store.section.pages.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white70, disabledForegroundColor: Colors.white24),
            onPressed: first ? null : () => flip.flip(-1),
            icon: const Icon(Icons.chevron_left),
            label: const Text('Back'),
          ),
          Text(
            '${store.pageIndex + 1} / ${store.section.pages.length}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Directionality(
            textDirection: TextDirection.rtl,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
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
