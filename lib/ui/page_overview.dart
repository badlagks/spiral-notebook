import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'paper_page.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Every page of a section as small pictures, or every favourite page in the
/// notebook. Tap one to open it; tap its star to make it a favourite.
Future<void> showPageOverview(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _Overview(),
    );

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  bool _favourites = false;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final entries = _favourites
        ? [
            for (var s = 0; s < store.sections.length; s++)
              for (var p = 0; p < store.sections[s].pages.length; p++)
                if (store.sections[s].pages[p].starred) (s, p),
          ]
        : [for (var p = 0; p < store.section.pages.length; p++) (store.sectionIndex, p)];

    return Dialog.fullscreen(
      backgroundColor: const Color(0xFFF3EEE2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text('All pages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE0A100)),
                    label: const Text('Favourites'),
                    selected: _favourites,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _favourites = true),
                  ),
                ),
                for (var i = 0; i < store.sections.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      avatar: CircleAvatar(backgroundColor: Color(store.sections[i].color), radius: 6),
                      label: Text(store.sections[i].name),
                      selected: !_favourites && i == store.sectionIndex,
                      showCheckmark: false,
                      onSelected: (_) {
                        setState(() => _favourites = false);
                        store.openSection(i);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      _favourites ? 'No favourites yet. Tap the star on a page to add it.' : 'No pages yet.',
                      style: const TextStyle(color: Color(0xFF666666)),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final (s, p) = entries[i];
                      final section = store.sections[s];
                      return _Thumb(
                        section: section,
                        page: section.pages[p],
                        number: p + 1,
                        showSection: _favourites,
                        current: s == store.sectionIndex && p == store.pageIndex,
                        onOpen: () {
                          Navigator.pop(context);
                          store.openPage(s, p);
                        },
                        onStar: () {
                          section.pages[p].starred = !section.pages[p].starred;
                          store.changed();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.section,
    required this.page,
    required this.number,
    required this.showSection,
    required this.current,
    required this.onOpen,
    required this.onStar,
  });

  final Section section;
  final NotePage page;
  final int number;
  final bool showSection;
  final bool current;
  final VoidCallback onOpen;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final title = page.title.trim().isEmpty ? 'Page $number' : page.title.trim();
    return Semantics(
      button: true,
      label: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: current ? Pen.blue : const Color(0x22000000), width: current ? 2.5 : 1),
                        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: ClipRect(
                        child: FittedBox(
                          child: PaperPage(
                            section: section,
                            page: page,
                            pageNumber: number,
                            bindingOnLeft: true,
                            interactive: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: page.starred ? 'Remove from favourites' : 'Add to favourites',
                      visualDensity: VisualDensity.compact,
                      onPressed: onStar,
                      icon: Icon(
                        page.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: page.starred ? const Color(0xFFE0A100) : const Color(0x88000000),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(
            showSection ? '${section.name} · page $number' : 'Page $number',
            style: const TextStyle(fontSize: 12, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }
}
