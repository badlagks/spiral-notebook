import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'paper_page.dart';
import 'store_scope.dart';

/// Torn-out pages: restore them, or delete them for good. Each one is
/// deleted by itself 30 days after it was torn out.
Future<void> showArchive(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ArchiveDialog());

class _ArchiveDialog extends StatelessWidget {
  const _ArchiveDialog();

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final now = DateTime.now();
    // Pages from locked sections stay out of sight until it's opened.
    final pages = store.archive.where((a) => !store.isArchiveLocked(a)).toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFFF6F1E4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Torn-out pages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Pages you tear out wait here for 30 days, then they are deleted for good.',
                style: TextStyle(color: Color(0xFF555555)),
              ),
            ),
            if (pages.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Text(
                  'Nothing here. To tear out a page, use the ⋮ menu at the top of the page.',
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: pages.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = pages[i];
                    final days = a.daysLeft(now);
                    final torn = '${_months.elementAt(a.tornAt.month - 1)} ${a.tornAt.day}';
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            _Thumbnail(page: a.page),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.page.title.isEmpty ? 'Untitled page' : a.page.title,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      CircleAvatar(radius: 5, backgroundColor: Color(a.sectionColor)),
                                      const SizedBox(width: 6),
                                      Flexible(child: Text(a.sectionName, overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Torn out $torn · deleted in $days ${days == 1 ? 'day' : 'days'}',
                                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF666666)),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      FilledButton.tonalIcon(
                                        onPressed: () {
                                          store.restore(a);
                                          Navigator.pop(context);
                                        },
                                        icon: const Icon(Icons.restore, size: 18),
                                        label: const Text('Restore'),
                                      ),
                                      TextButton.icon(
                                        onPressed: () => _confirmDelete(context, a),
                                        icon: const Icon(Icons.delete_outline, size: 18),
                                        label: const Text('Delete now'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, ArchivedPage a) async {
    final store = StoreScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this page for good?'),
        content: const Text('It can’t be brought back after this.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) store.deleteForever(a);
  }
}

/// A small picture of the page as it looked when torn out.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.page});
  final NotePage page;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      height: 84 * pageHeight / pageWidth,
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: FittedBox(
        child: PaperPage(
          section: Section(name: '', color: 0, pages: [page]),
          page: page,
          pageNumber: 0,
          bindingOnLeft: true,
          interactive: false,
        ),
      ),
    );
  }
}
