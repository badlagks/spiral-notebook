import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/files.dart';
import '../data/media/media_store.dart';
import '../data/notebook_store.dart';
import '../data/pdf_tools.dart';
import '../models/notebook.dart';
import 'store_scope.dart';

/// Saves the whole notebook, photos and videos included, to one file.
Future<void> backUpNotebook(BuildContext context) async {
  final store = StoreScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await makeBackup(store.notebook);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'Notebook backup ${now.year}-${two(now.month)}-${two(now.day)}.$backupExtension';
    if (await fileIO.save(name, bytes)) {
      messenger.showSnackBar(SnackBar(content: Text('Backed up to "$name". Keep it somewhere safe.')));
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not make the backup: $e')));
  }
}

/// Replaces the notebook with one from a backup file, after asking.
Future<void> restoreNotebook(BuildContext context) async {
  final store = StoreScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final file = await fileIO.open(extensions: [backupExtension, 'json']);
  if (file == null || !context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        'Everything in the notebook now will be replaced by "${file.name}". '
        'Back up first if you might want today\'s notes again.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
      ],
    ),
  );
  if (ok != true) return;
  try {
    store.replaceWith(await readBackup(file.bytes));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Notebook restored.')));
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not restore: $e')));
  }
}

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Lists the copies the notebook keeps of itself each day, and puts one back.
Future<void> showEarlierVersions(BuildContext context) async {
  final store = StoreScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final copies = await store.dailyCopies();
  if (!context.mounted) return;
  final now = DateTime.now();
  String label(DateTime d) {
    final days = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
    return switch (days) {
      0 => 'Earlier today',
      1 => 'Yesterday',
      _ => '${d.day} ${_months[d.month - 1]}',
    };
  }

  String summary(Notebook nb) {
    final pages = nb.sections.fold(
      0,
      (n, s) => n + s.pages.where((p) => p.blocks.isNotEmpty || p.strokes.isNotEmpty).length,
    );
    return '${nb.sections.length} ${nb.sections.length == 1 ? 'section' : 'sections'}, '
        '$pages ${pages == 1 ? 'page' : 'pages'} with notes';
  }

  final picked = await showDialog<DailyCopy>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.history),
      title: const Text('Earlier versions'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The notebook keeps a copy of itself from each of the last 7 days you used it. '
              'They stay on this device, and your phone\'s own backup includes them.',
              style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
            const SizedBox(height: 8),
            if (copies.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No earlier versions yet. The first one is kept tomorrow.'),
              ),
            for (final copy in copies)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_note_outlined),
                title: Text(label(copy.day)),
                subtitle: Text(summary(copy.notebook)),
                trailing: TextButton(onPressed: () => Navigator.pop(c, copy), child: const Text('Put back')),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
    ),
  );
  if (picked == null) return;
  store.replaceWith(picked.notebook);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('The notebook is back as it was ${label(picked.day).toLowerCase()}.'),
        action: SnackBarAction(label: 'Undo', onPressed: store.undo),
      ),
    );
}

/// Turns each page of a PDF into a notebook page to write and draw on.
Future<void> importPdf(BuildContext context) async {
  final store = StoreScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final file = await fileIO.open(extensions: ['pdf']);
  if (file == null) return;
  messenger.showSnackBar(const SnackBar(content: Text('Opening the PDF…')));
  try {
    final pictures = await pdfToPictures(file.bytes);
    final title = file.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final pages = <NotePage>[];
    for (var i = 0; i < pictures.length; i++) {
      final id = newId();
      await mediaStore.put(id, pictures[i], mime: 'image/png');
      pages.add(
        NotePage(title: pictures.length == 1 ? title : '$title ${i + 1}', paper: PaperStyle.blank, background: id),
      );
    }
    store.addPages(pages);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Added ${pages.length} page${pages.length == 1 ? '' : 's'} from the PDF.')),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not open that PDF: $e')));
  }
}
