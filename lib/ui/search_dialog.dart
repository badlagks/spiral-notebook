import 'package:flutter/material.dart';

import '../data/notebook_store.dart';
import 'store_scope.dart';

/// Finds pages across every section and jumps to the one picked.
Future<void> showNotebookSearch(BuildContext context) {
  final store = StoreScope.read(context);
  return showDialog<void>(
    context: context,
    builder: (_) => _SearchDialog(store: store),
  );
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({required this.store});
  final NotebookStore store;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hits = widget.store.search(_query);
    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search your notebook',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (q) => setState(() => _query = q),
                onSubmitted: (_) {
                  if (hits.isNotEmpty) _open(hits.first);
                },
              ),
            ),
            if (_query.trim().isNotEmpty && hits.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Nothing found on any page.'),
              ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: hits.length,
                itemBuilder: (context, i) {
                  final hit = hits[i];
                  final section = widget.store.sections[hit.sectionIndex];
                  final page = section.pages[hit.pageIndex];
                  return ListTile(
                    leading: CircleAvatar(radius: 6, backgroundColor: Color(section.color)),
                    title: Text(
                      '${section.name} · ${page.title.isEmpty ? 'Page ${hit.pageIndex + 1}' : page.title}',
                    ),
                    subtitle: Text(hit.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _open(hit),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(SearchHit hit) {
    widget.store.openPage(hit.sectionIndex, hit.pageIndex);
    Navigator.pop(context);
  }
}
