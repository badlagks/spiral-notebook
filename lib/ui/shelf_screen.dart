import 'package:flutter/material.dart';

import '../data/pro.dart';
import '../models/library.dart';
import '../models/notebook.dart';
import 'pro_sheet.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Every notebook on this device as a row of covers. Tap one to open it.
Future<void> showShelf(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _Shelf());

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _when(DateTime t) {
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) return 'today';
  return '${t.day} ${_monthNames[t.month - 1]}${t.year != now.year ? ' ${t.year}' : ''}';
}

class _Shelf extends StatelessWidget {
  const _Shelf();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final shelf = store.shelf;
    final deleted = shelf.recentlyDeleted;
    return Dialog.fullscreen(
      backgroundColor: Paper.desk,
      child: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      color: Colors.white70,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        'My notebooks',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid.extent(
                maxCrossAxisExtent: 180,
                childAspectRatio: 0.68,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                children: [
                  for (final e in shelf.notebooks)
                    _CoverTile(
                      entry: e,
                      open: e.id == store.notebook.id,
                      onTap: () async {
                        final nav = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        if (await store.openNotebook(e.id)) {
                          nav.pop();
                        } else {
                          messenger.showSnackBar(
                            SnackBar(content: Text('"${e.title}" could not be opened.')),
                          );
                        }
                      },
                    ),
                  _NewTile(onTap: () => _newNotebook(context)),
                ],
              ),
            ),
            if (deleted.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text(
                    'Recently deleted',
                    style: TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SliverList.list(
                children: [
                  for (final e in deleted)
                    ListTile(
                      leading: Icon(Icons.book, color: Color(e.cover)),
                      title: Text(e.title, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        'Deleted for good in ${_daysLeft(e)}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          if (shelf.notebooks.isNotEmpty &&
                              !await requirePro(
                                context,
                                reason: 'Your first notebook is free. Keeping more than one comes with Pro.',
                              )) {
                            return;
                          }
                          await store.restoreNotebook(e.id);
                        },
                        child: const Text('Restore'),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _daysLeft(ShelfEntry e) {
    final days = e.deletedAt!.add(ShelfEntry.keepDeletedFor).difference(DateTime.now()).inHours / 24;
    final n = days.ceil().clamp(1, 30);
    return n == 1 ? '1 day' : '$n days';
  }

  Future<void> _newNotebook(BuildContext context) async {
    final store = StoreScope.read(context);
    if (store.shelf.notebooks.isNotEmpty &&
        !await requirePro(context, reason: 'Your first notebook is free. More notebooks come with Pro.')) {
      return;
    }
    if (!context.mounted) return;
    final picked = await showNotebookEditor(
      context,
      heading: 'New notebook',
      title: 'Notebook ${store.shelf.notebooks.length + 1}',
      cover: coverColors[store.shelf.notebooks.length % coverColors.length],
      action: 'Create',
    );
    if (picked == null || !context.mounted) return;
    await store.newNotebook(title: picked.title, cover: picked.cover);
    if (context.mounted) Navigator.pop(context);
  }
}

/// One notebook's cover, with its name on a label like a real one.
class _CoverTile extends StatelessWidget {
  const _CoverTile({required this.entry, required this.open, required this.onTap});

  final ShelfEntry entry;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final color = Color(entry.cover);
    return Semantics(
      button: true,
      label: '${entry.title}${open ? ', open now' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Material(
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    elevation: open ? 10 : 4,
                    child: InkWell(
                      onTap: onTap,
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [color, Paper.shade(color)],
                          ),
                          border: open ? Border.all(color: Colors.white, width: 2) : null,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            // The coil down the left edge.
                            SizedBox(
                              width: 14,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  for (var i = 0; i < 9; i++)
                                    Container(
                                      width: 10,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFCFCFCF),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 10),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Paper.cream,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    entry.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: headingHandwriting.copyWith(fontSize: 18, height: 1.1),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: PopupMenuButton<String>(
                    tooltip: 'Notebook options',
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    onSelected: (v) async {
                      switch (v) {
                        case 'edit':
                          final picked = await showNotebookEditor(
                            context,
                            heading: 'Name and cover',
                            title: entry.title,
                            cover: entry.cover,
                            action: 'Save',
                          );
                          if (picked != null) {
                            await store.editNotebook(entry.id, title: picked.title, cover: picked.cover);
                          }
                        case 'delete':
                          await _confirmDelete(context);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Name and cover')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: store.shelf.notebooks.length > 1,
                        child: const ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete')),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            open ? 'Open now' : 'Changed ${_when(entry.updated)}',
            textAlign: TextAlign.center,
            style: TextStyle(color: open ? Colors.white : Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final store = StoreScope.read(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${entry.title}"?'),
        content: const Text(
          'It moves to Recently deleted, where you can bring it back for 30 days. '
          'Its reminders stop ringing.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteNotebook(entry.id);
  }
}

class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: Colors.white.withValues(alpha: 0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.white30, width: 1.5),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, color: Colors.white70, size: 36),
                    SizedBox(height: 6),
                    Text('New notebook', style: TextStyle(color: Colors.white70)),
                    _ProTag(),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text('', style: TextStyle(fontSize: 12)),
      ],
    );
  }
}

/// Asks for a notebook's name and cover colour.
Future<({String title, int cover})?> showNotebookEditor(
  BuildContext context, {
  required String heading,
  required String title,
  required int cover,
  required String action,
}) {
  final name = TextEditingController(text: title);
  var chosen = cover;
  return showDialog<({String title, int cover})>(
    context: context,
    builder: (c0) => StatefulBuilder(
      builder: (c, setDialog) {
        void done() {
          final t = name.text.trim();
          Navigator.pop(c, (title: t.isEmpty ? title : t, cover: chosen));
        }

        return AlertDialog(
          title: Text(heading),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onSubmitted: (_) => done(),
                ),
                const SizedBox(height: 18),
                const Text('Cover', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in coverColors)
                      Semantics(
                        button: true,
                        selected: c == chosen,
                        label: 'Cover colour',
                        child: GestureDetector(
                          onTap: () async {
                            if (c != chosen && !await requirePro(c0, reason: 'Cover colours come with Pro.')) return;
                            setDialog(() => chosen = c);
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: c == chosen ? const Color(0xFF2B2B2B) : Colors.transparent,
                                width: 3,
                              ),
                            ),
                            child: c == chosen
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : purchases.isPro.value
                                ? null
                                : const Icon(Icons.lock_outline, color: Colors.white70, size: 16),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: done, child: Text(action)),
          ],
        );
      },
    ),
  );
}

/// Shown on the New notebook card while only one notebook is free.
class _ProTag extends StatelessWidget {
  const _ProTag();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    if (purchases.isPro.value || store.shelf.notebooks.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFE6B450), borderRadius: BorderRadius.circular(10)),
      child: const Text('Pro', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A2A10))),
    );
  }
}
