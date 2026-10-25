import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart';

import '../data/media/media_picker.dart';
import '../data/media/media_store.dart';
import '../models/notebook.dart';
import 'blocks/block_content.dart';
import 'paper_painters.dart';
import 'theme.dart';

/// One kind of widget that can be put on a page.
class GalleryEntry {
  const GalleryEntry({
    required this.name,
    required this.description,
    required this.icon,
    required this.make,
    required this.sample,
    this.media,
  });

  final String name;
  final String description;
  final IconData icon;

  /// A fresh, empty widget for the page.
  final Block Function() make;

  /// The same widget filled with example content, for its preview.
  final Block Function() sample;

  /// For photos and videos: what to pick before it can be added.
  final MediaKind? media;
}

final galleryEntries = <GalleryEntry>[
  GalleryEntry(
    name: 'Writing',
    description: 'Free handwriting. Start a line with "- " to make an outline.',
    icon: Icons.edit_outlined,
    make: () => TextBlock(),
    sample: () => TextBlock(text: '- Draft design\n  - Ask Sam\n- Measurement'),
  ),
  GalleryEntry(
    name: 'Heading',
    description: 'A big handwritten heading to split up a page.',
    icon: Icons.title,
    make: () => TextBlock(kind: TextKind.heading),
    sample: () => TextBlock(kind: TextKind.heading, text: 'Weekend plans'),
  ),
  GalleryEntry(
    name: 'Highlight',
    description: 'A short note with a highlighter stroke behind it.',
    icon: Icons.highlight,
    make: () => TextBlock(highlight: true),
    sample: () => TextBlock(highlight: true, text: 'Remember this!'),
  ),
  GalleryEntry(
    name: 'Sticky note',
    description: 'A square paper note you can stick anywhere and tilt.',
    icon: Icons.sticky_note_2_outlined,
    make: () => StickyBlock(),
    sample: () => StickyBlock(text: 'Call Sam about the sketches'),
  ),
  GalleryEntry(
    name: 'Checklist',
    description: 'Tick things off. Press Enter for the next item.',
    icon: Icons.checklist,
    make: () => ChecklistBlock(),
    sample: () => ChecklistBlock(
      items: [
        ChecklistItem(text: 'Call client', done: true),
        ChecklistItem(text: 'Draft design'),
        ChecklistItem(text: 'Send invoice'),
      ],
    ),
  ),
  GalleryEntry(
    name: 'Spreadsheet',
    description: 'Rows and columns with formulas like =SUM(D2:D4).',
    icon: Icons.grid_on,
    make: () => SheetBlock(
      cells: [
        ['Item', 'Qty', 'Price', 'Total'],
        ['', '', '', '=B2*C2'],
        ['', '', '', '=B3*C3'],
        ['', '', '', '=B4*C4'],
        ['', '', 'Total', '=SUM(D2:D4)'],
      ],
    ),
    sample: () => SheetBlock(
      cells: [
        ['Item', 'Qty', 'Price', 'Total'],
        ['Paper', '2', '\$4.50', '=B2*C2'],
        ['Pens', '3', '\$1.20', '=B3*C3'],
        ['', '', 'Total', '=SUM(D2:D3)'],
      ],
    ),
  ),
  GalleryEntry(
    name: 'Calculator',
    description: 'A desk calculator. Works with your keyboard too.',
    icon: Icons.calculate_outlined,
    make: () => CalculatorBlock(),
    sample: () => CalculatorBlock(display: '1,450.00'),
  ),
  GalleryEntry(
    name: 'Photo',
    description: 'A photo in a small frame, with a note, where it was, and to-dos about it.',
    icon: Icons.photo_outlined,
    media: MediaKind.photo,
    make: () => throw UnsupportedError('pick a photo first'),
    sample: () => MediaBlock(
      mediaId: '${MediaBlock.samplePrefix}photo',
      note: 'Cabin by the lake',
      place: 'Lake Tahoe',
      todos: ChecklistBlock(items: [ChecklistItem(text: 'Print for mum')]),
    ),
  ),
  GalleryEntry(
    name: 'Video',
    description: 'A short video in a small window you can resize. Tap it to play.',
    icon: Icons.videocam_outlined,
    media: MediaKind.video,
    make: () => throw UnsupportedError('pick a video first'),
    sample: () => MediaBlock(
      mediaId: '${MediaBlock.samplePrefix}video',
      kind: MediaKind.video,
      aspect: 16 / 9,
      note: 'Kitchen tap leak',
      todos: ChecklistBlock(items: [ChecklistItem(text: 'Send to plumber')]),
    ),
  ),
];

/// Asks for a photo or video, keeps it on the device, and wraps it in a widget.
Future<MediaBlock?> pickMediaBlock(BuildContext context, MediaKind kind, {bool camera = false}) async {
  final picked = await mediaPicker.pick(kind, camera: camera);
  if (picked == null) return null;
  final id = newId();
  await mediaStore.put(id, picked.bytes, mime: picked.mime, name: picked.name);
  return MediaBlock(
    mediaId: id,
    kind: kind,
    name: picked.name,
    aspect: kind == MediaKind.photo ? (imageAspect(picked.bytes) ?? 4 / 3).clamp(0.4, 2.5) : 16 / 9,
  );
}

/// Phones and tablets have a camera to take a photo with right away.
bool get _hasCamera =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Shows every widget with a live preview. Returns the widget to add, or null.
Future<Block?> showWidgetGallery(BuildContext context) =>
    showDialog<Block>(context: context, builder: (_) => const _GalleryDialog());

class _GalleryDialog extends StatefulWidget {
  const _GalleryDialog();

  @override
  State<_GalleryDialog> createState() => _GalleryDialogState();
}

class _GalleryDialogState extends State<_GalleryDialog> {
  GalleryEntry? _open;
  Block? _tryOut;

  /// The photo or video chosen in the try-out, ready to add.
  MediaBlock? _picked;
  bool _picking = false;

  void _show(GalleryEntry e) => setState(() {
    _open = e;
    _tryOut = e.sample();
    _picked = null;
  });

  Future<void> _pick(MediaKind kind, {bool camera = false}) async {
    setState(() => _picking = true);
    try {
      final block = await pickMediaBlock(context, kind, camera: camera);
      if (block != null && mounted) {
        setState(() => _tryOut = _picked = block);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Could not open that file: $e')));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFFF6F1E4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _open == null ? _grid() : _detail(_open!),
        ),
      ),
    );
  }

  Widget _grid() {
    return Column(
      key: const ValueKey('grid'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBar('Add to this page', null),
        Flexible(
          child: GridView.extent(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            maxCrossAxisExtent: 220,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
            children: [for (final e in galleryEntries) _Card(entry: e, onTap: () => _show(e))],
          ),
        ),
      ],
    );
  }

  Widget _detail(GalleryEntry e) {
    final block = _tryOut!;
    return Column(
      key: ValueKey(e.name),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _titleBar(e.name, () => setState(() => _open = null)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            e.media == null
                ? '${e.description} Try it below before adding it.'
                : _picked == null
                ? '${e.description} Here is an example. Choose your own to see it here before adding it.'
                : 'Here is how it will look. Add a note or to-dos now or later.',
            style: const TextStyle(fontSize: 14, color: Color(0xFF555555)),
          ),
        ),
        Flexible(
          child: Container(
            margin: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minHeight: 280),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: PaperPainter(style: PaperStyle.ruled, bindingOnLeft: true, headerHeight: 20),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(56, 24, 24, 24),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(width: block.width, child: blockContent(block)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              TextButton(onPressed: () => setState(() => _open = null), child: const Text('Back')),
              const SizedBox(width: 8),
              if (e.media case final kind? when _picked == null) ...[
                if (_hasCamera && !_picking) ...[
                  OutlinedButton.icon(
                    onPressed: () => _pick(kind, camera: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(kind == MediaKind.photo ? 'Take photo' : 'Record'),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: _picking ? null : () => _pick(kind),
                  icon: _picking
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(kind == MediaKind.photo ? 'Choose photo' : 'Choose video'),
                ),
              ] else ...[
                if (_picked case final picked?) ...[
                  TextButton(onPressed: () => _pick(picked.kind), child: const Text('Choose another')),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _picked ?? e.make()),
                  icon: const Icon(Icons.add),
                  label: const Text('Add to page'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _titleBar(String title, VoidCallback? onBack) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(tooltip: 'Back', onPressed: onBack, icon: const Icon(Icons.arrow_back))
        else
          const SizedBox(width: 12),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.entry, required this.onTap});

  final GalleryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sample = entry.sample();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomPaint(
                painter: PaperPainter(style: PaperStyle.ruled, bindingOnLeft: true, headerHeight: 14),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 10, 10, 10),
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(width: sample.width, child: blockContent(sample)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  Icon(entry.icon, size: 18, color: Pen.blue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(entry.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
