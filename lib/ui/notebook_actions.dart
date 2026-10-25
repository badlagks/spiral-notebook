import 'package:flutter/material.dart';

import '../data/backup.dart';
import '../data/files.dart';
import '../data/media/media_store.dart';
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
