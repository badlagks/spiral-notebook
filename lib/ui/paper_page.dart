import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'blocks/calculator_view.dart';
import 'blocks/checklist_view.dart';
import 'blocks/sheet_view.dart';
import 'blocks/text_block_view.dart';
import 'paper_painters.dart';
import 'store_scope.dart';
import 'theme.dart';

/// One sheet of paper with its title and everything placed on it.
class PaperPage extends StatefulWidget {
  const PaperPage({
    super.key,
    required this.section,
    required this.page,
    required this.pageNumber,
    required this.bindingOnLeft,
  });

  final Section section;
  final NotePage page;
  final int pageNumber;
  final bool bindingOnLeft;

  @override
  State<PaperPage> createState() => _PaperPageState();
}

class _PaperPageState extends State<PaperPage> {
  late final _title = TextEditingController(text: widget.page.title);
  String? _justAdded;

  NotePage get _page => widget.page;

  @override
  void didUpdateWidget(PaperPage old) {
    super.didUpdateWidget(old);
    if (_title.text != _page.title) _title.text = _page.title;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _add(Block block) {
    setState(() {
      _page.blocks.add(block);
      _justAdded = block.id;
    });
    StoreScope.read(context).changed();
  }

  @override
  Widget build(BuildContext context) {
    final inset = widget.bindingOnLeft
        ? const EdgeInsets.fromLTRB(56, 16, 22, 16)
        : const EdgeInsets.fromLTRB(26, 16, 34, 16);
    return CustomPaint(
      painter: PaperPainter(style: _page.paper, bindingOnLeft: widget.bindingOnLeft),
      child: ListView(
        padding: inset,
        children: [
          _header(),
          const SizedBox(height: 10),
          for (final block in _page.blocks)
            Padding(
              key: ValueKey(block.id),
              padding: const EdgeInsets.only(bottom: 14),
              child: _BlockFrame(
                block: block,
                page: _page,
                child: switch (block) {
                  TextBlock() => TextBlockView(block: block, autofocus: block.id == _justAdded),
                  ChecklistBlock() => ChecklistView(block: block),
                  SheetBlock() => SheetView(block: block),
                  CalculatorBlock() => CalculatorView(block: block),
                },
              ),
            ),
          _AddBlockButton(onAdd: _add),
          const SizedBox(height: 24),
          Align(
            alignment: widget.bindingOnLeft ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              '${widget.pageNumber}',
              style: handwriting.copyWith(fontSize: 14, color: Pen.pencil),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                style: headingHandwriting,
                decoration: InputDecoration.collapsed(
                  hintText: 'Page title',
                  hintStyle: headingHandwriting.copyWith(color: Pen.pencil.withValues(alpha: 0.4)),
                ),
                onChanged: (t) {
                  _page.title = t;
                  StoreScope.read(context).changedQuietly();
                  setState(() {}); // keeps the underline matched to the title
                },
              ),
              _titleUnderline(),
            ],
          ),
        ),
        _pageMenu(),
      ],
    );
  }

  Widget _titleUnderline() {
    final painter = TextPainter(
      text: TextSpan(text: _title.text.isEmpty ? ' ' : _title.text, style: headingHandwriting),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width + 8;
    painter.dispose();
    return LayoutBuilder(
      builder: (context, c) => SizedBox(
        width: width.clamp(0.0, c.maxWidth),
        height: 8,
        child: const CustomPaint(painter: PenUnderlinePainter()),
      ),
    );
  }

  Widget _pageMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Page options',
      icon: Icon(Icons.more_vert, size: 20, color: Pen.pencil.withValues(alpha: 0.6)),
      onSelected: (value) {
        final store = StoreScope.read(context);
        switch (value) {
          case 'ruled' || 'grid' || 'blank':
            _page.paper = PaperStyle.values.byName(value);
            store.changed();
          case 'delete':
            _confirmDelete();
        }
      },
      itemBuilder: (_) => [
        for (final style in PaperStyle.values)
          CheckedPopupMenuItem(
            value: style.name,
            checked: _page.paper == style,
            child: Text('${style.name[0].toUpperCase()}${style.name.substring(1)} paper'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('Tear out this page')),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Tear out this page?'),
        content: const Text('Everything on it will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Tear out')),
        ],
      ),
    );
    if (ok == true && mounted) StoreScope.read(context).deletePage(widget.section, _page);
  }
}

/// Wraps a block with a small, faint menu for arranging it.
class _BlockFrame extends StatefulWidget {
  const _BlockFrame({required this.block, required this.page, required this.child});

  final Block block;
  final NotePage page;
  final Widget child;

  @override
  State<_BlockFrame> createState() => _BlockFrameState();
}

class _BlockFrameState extends State<_BlockFrame> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: widget.child),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _hover ? 0.9 : 0.25,
            child: _menu(),
          ),
        ],
      ),
    );
  }

  Widget _menu() {
    final block = widget.block;
    final blocks = widget.page.blocks;
    final index = blocks.indexOf(block);
    return SizedBox(
      width: 28,
      height: 28,
      child: PopupMenuButton<String>(
        tooltip: 'Arrange',
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: const Icon(Icons.drag_indicator, color: Pen.pencil),
        onSelected: (value) {
          final store = StoreScope.read(context);
          switch (value) {
            case 'highlight':
              (block as TextBlock).highlight = !block.highlight;
            case 'heading':
              final t = block as TextBlock;
              t.kind = t.kind == TextKind.heading ? TextKind.body : TextKind.heading;
            case 'up':
              blocks.insert(index - 1, blocks.removeAt(index));
            case 'down':
              blocks.insert(index + 1, blocks.removeAt(index));
            case 'delete':
              blocks.remove(block);
          }
          store.changed();
        },
        itemBuilder: (_) => [
          if (block is TextBlock) ...[
            CheckedPopupMenuItem(value: 'highlight', checked: block.highlight, child: const Text('Highlight')),
            CheckedPopupMenuItem(
                value: 'heading', checked: block.kind == TextKind.heading, child: const Text('Heading')),
            const PopupMenuDivider(),
          ],
          PopupMenuItem(value: 'up', enabled: index > 0, child: const Text('Move up')),
          PopupMenuItem(value: 'down', enabled: index < blocks.length - 1, child: const Text('Move down')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'delete', child: Text('Erase')),
        ],
      ),
    );
  }
}

class _AddBlockButton extends StatelessWidget {
  const _AddBlockButton({required this.onAdd});

  final ValueChanged<Block> onAdd;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: 'Add to this page',
        onSelected: (value) => onAdd(switch (value) {
          'heading' => TextBlock(kind: TextKind.heading),
          'outline' => TextBlock(text: '- '),
          'highlight' => TextBlock(highlight: true),
          'checklist' => ChecklistBlock(),
          'sheet' => SheetBlock(cells: [
              ['Item', 'Qty', 'Price', 'Total'],
              ['', '', '', '=B2*C2'],
              ['', '', '', '=B3*C3'],
              ['', '', '', '=B4*C4'],
              ['', '', 'Total', '=SUM(D2:D4)'],
            ]),
          'calculator' => CalculatorBlock(),
          _ => TextBlock(),
        }),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Writing'))),
          PopupMenuItem(value: 'heading', child: ListTile(leading: Icon(Icons.title), title: Text('Heading'))),
          PopupMenuItem(value: 'outline', child: ListTile(leading: Icon(Icons.format_list_bulleted), title: Text('Outline'))),
          PopupMenuItem(value: 'highlight', child: ListTile(leading: Icon(Icons.highlight), title: Text('Highlighted note'))),
          PopupMenuItem(value: 'checklist', child: ListTile(leading: Icon(Icons.checklist), title: Text('Checklist'))),
          PopupMenuItem(value: 'sheet', child: ListTile(leading: Icon(Icons.grid_on), title: Text('Spreadsheet'))),
          PopupMenuItem(value: 'calculator', child: ListTile(leading: Icon(Icons.calculate_outlined), title: Text('Calculator'))),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline, size: 20, color: Pen.pencil.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('Add', style: handwriting.copyWith(fontSize: 16, color: Pen.pencil.withValues(alpha: 0.8))),
            ],
          ),
        ),
      ),
    );
  }
}
