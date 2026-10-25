import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'blocks/block_content.dart';
import 'blocks/sticky_view.dart';
import 'ink.dart';
import 'paper_painters.dart';
import 'store_scope.dart';
import 'theme.dart';
import 'widget_gallery.dart';

/// One sheet of paper, [pageWidth] × [pageHeight] paper units, with its title
/// and the widgets placed freely on it. The caller scales it to the screen.
class PaperPage extends StatefulWidget {
  const PaperPage({
    super.key,
    required this.section,
    required this.page,
    required this.pageNumber,
    required this.bindingOnLeft,
    this.interactive = true,
  });

  final Section section;
  final NotePage page;
  final int pageNumber;
  final bool bindingOnLeft;

  /// False for thumbnails and pages mid-flip: drawn the same, but nothing
  /// on them can be edited.
  final bool interactive;

  @override
  State<PaperPage> createState() => _PaperPageState();
}

class _PaperPageState extends State<PaperPage> {
  late final _title = TextEditingController(text: widget.page.title);
  final _canvasKey = GlobalKey();
  String? _selected;
  String? _justAdded;

  NotePage get _page => widget.page;
  double get _left => widget.bindingOnLeft ? 56 : 28;
  double get _right => widget.bindingOnLeft ? 20 : 40;

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

  /// Converts a screen position to paper units on this page.
  Offset _toPaper(Offset global) =>
      (_canvasKey.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  Future<void> _openGallery() async {
    final block = await showWidgetGallery(context);
    if (block == null || !mounted) return;
    StoreScope.read(context).addBlock(_page, block);
    setState(() {
      _selected = block.id;
      _justAdded = block.id;
    });
  }

  void _select(Block block) {
    if (_selected == block.id) return;
    setState(() => _selected = block.id);
    StoreScope.read(context).bringToFront(_page, block);
  }

  @override
  Widget build(BuildContext context) {
    final page = SizedBox(
      key: _canvasKey,
      width: pageWidth,
      height: pageHeight,
      child: CustomPaint(
        painter: PaperPainter(style: _page.paper, bindingOnLeft: widget.bindingOnLeft),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // Tapping bare paper puts down whatever was picked up.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  if (_selected != null) setState(() => _selected = null);
                },
              ),
            ),
            Positioned(left: _left, top: 14, right: _right, child: _header()),
            for (final block in _page.blocks)
              _PlacedBlock(
                key: ValueKey(block.id),
                block: block,
                page: _page,
                selected: block.id == _selected,
                toPaper: _toPaper,
                onSelect: () => _select(block),
                onRemoved: () => setState(() => _selected = null),
                child: blockContent(block, autofocus: block.id == _justAdded),
              ),
            // Drawing sits above the widgets, like ink on top of the paper.
            Positioned.fill(child: InkLayer(page: _page, interactive: widget.interactive)),
            if (widget.pageNumber > 0)
              Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: IgnorePointer(
                child: Text(
                  '${widget.pageNumber}',
                  textAlign: TextAlign.center,
                  style: headingHandwriting.copyWith(fontSize: 20, fontWeight: FontWeight.w400, color: Pen.pencil),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.interactive ? page : IgnorePointer(child: page);
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
        Tooltip(
          message: 'Add a widget to this page',
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Pen.pencil,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
            ),
            onPressed: _openGallery,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Text('Add', style: handwriting.copyWith(fontSize: 17, color: Pen.pencil)),
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
      icon: Icon(Icons.more_vert, size: 20, color: Pen.pencil.withValues(alpha: 0.7)),
      onSelected: (value) {
        final store = StoreScope.read(context);
        switch (value) {
          case 'ruled' || 'grid' || 'blank':
            _page.paper = PaperStyle.values.byName(value);
            store.changed();
          case 'tear':
            final archived = store.tearOut(widget.section, _page);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Page torn out. It stays in Torn-out pages for 30 days.'),
              action: SnackBarAction(label: 'Undo', onPressed: () => store.restore(archived)),
            ));
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
        const PopupMenuItem(value: 'tear', child: Text('Tear out this page')),
      ],
    );
  }
}

/// A widget placed on the paper. Tap it to pick it up: a handle appears
/// above it to drag it anywhere, and a knob at its corner resizes it.
class _PlacedBlock extends StatefulWidget {
  const _PlacedBlock({
    super.key,
    required this.block,
    required this.page,
    required this.selected,
    required this.toPaper,
    required this.onSelect,
    required this.onRemoved,
    required this.child,
  });

  final Block block;
  final NotePage page;
  final bool selected;
  final Offset Function(Offset global) toPaper;
  final VoidCallback onSelect;
  final VoidCallback onRemoved;
  final Widget child;

  @override
  State<_PlacedBlock> createState() => _PlacedBlockState();
}

class _PlacedBlockState extends State<_PlacedBlock> {
  static const _handleRoom = 30.0;
  static const _side = 12.0;

  bool _hover = false;
  Offset? _grab; // pointer position when a drag began, in paper units
  Offset _origin = Offset.zero; // the block's position or size when a drag began

  Block get _b => widget.block;

  void _moveStart(DragStartDetails d) {
    widget.onSelect();
    _grab = widget.toPaper(d.globalPosition);
    _origin = Offset(_b.x!, _b.y!);
  }

  void _moveUpdate(DragUpdateDetails d) {
    final delta = widget.toPaper(d.globalPosition) - _grab!;
    setState(() {
      _b.x = (_origin.dx + delta.dx).clamp(40 - _b.width, pageWidth - 40);
      _b.y = (_origin.dy + delta.dy).clamp(0.0, pageHeight - 30);
    });
  }

  void _resizeStart(DragStartDetails d) {
    _grab = widget.toPaper(d.globalPosition);
    _origin = Offset(_b.width, 0);
  }

  void _resizeUpdate(DragUpdateDetails d) {
    final delta = widget.toPaper(d.globalPosition) - _grab!;
    setState(() => _b.width = (_origin.dx + delta.dx).clamp(_b.minWidth, pageWidth));
  }

  void _dragEnd([DragEndDetails? _]) {
    _grab = null;
    StoreScope.read(context).changed();
  }

  @override
  Widget build(BuildContext context) {
    final showHandle = widget.selected || _hover;
    return Positioned(
      left: _b.x! - _side,
      top: _b.y! - _handleRoom,
      width: _b.width + _side * 2,
      child: Transform.rotate(
        angle: _b.angle * math.pi / 180,
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(_side, _handleRoom, _side, _side),
                child: Listener(
                  onPointerDown: (_) => widget.onSelect(),
                  child: widget.child,
                ),
              ),
              if (widget.selected)
                Positioned.fill(
                  left: _side - 5,
                  top: _handleRoom - 5,
                  right: _side - 5,
                  bottom: _side - 5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0x993F72AF), width: 1.2),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: _side,
                top: 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: widget.selected ? 1 : (_hover ? 0.6 : 0),
                  child: IgnorePointer(ignoring: !showHandle, child: _handle()),
                ),
              ),
              if (widget.selected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Tooltip(
                    message: 'Drag to resize',
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _resizeStart,
                        onPanUpdate: _resizeUpdate,
                        onPanEnd: _dragEnd,
                        child: SizedBox.square(
                          dimension: 24,
                          child: Center(
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF3F72AF), width: 2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _handle() {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x553F72AF)),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Drag to move',
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _moveStart,
                onPanUpdate: _moveUpdate,
                onPanEnd: _dragEnd,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(Icons.open_with, size: 15, color: Color(0xFF3F72AF)),
                      SizedBox(width: 4),
                      Text('Move', style: TextStyle(fontSize: 12, color: Color(0xFF3F72AF))),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            height: 26,
            child: PopupMenuButton<String>(
              tooltip: 'Widget options',
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: const Icon(Icons.more_horiz, color: Color(0xFF3F72AF)),
              onSelected: _onMenu,
              itemBuilder: (_) => _menuItems(),
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems() {
    final b = _b;
    return [
      if (b is TextBlock) ...[
        CheckedPopupMenuItem(value: 'highlight', checked: b.highlight, child: const Text('Highlight')),
        CheckedPopupMenuItem(value: 'heading', checked: b.kind == TextKind.heading, child: const Text('Heading')),
        const PopupMenuDivider(),
      ],
      if (b is StickyBlock) ...[
        PopupMenuItem(
          enabled: false,
          child: Row(
            children: [
              for (final c in stickyColors)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      b.color = c;
                      StoreScope.read(context).changed();
                    },
                    child: CircleAvatar(radius: 12, backgroundColor: Color(c)),
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
      ],
      const PopupMenuItem(value: 'tilt-left', child: Text('Tilt left')),
      const PopupMenuItem(value: 'straighten', child: Text('Straighten')),
      const PopupMenuItem(value: 'tilt-right', child: Text('Tilt right')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
      const PopupMenuItem(value: 'erase', child: Text('Erase')),
    ];
  }

  void _onMenu(String value) {
    final store = StoreScope.read(context);
    final b = _b;
    switch (value) {
      case 'highlight':
        (b as TextBlock).highlight = !b.highlight;
      case 'heading':
        final t = b as TextBlock;
        t.kind = t.kind == TextKind.heading ? TextKind.body : TextKind.heading;
      case 'tilt-left':
        b.angle = (b.angle - 3).clamp(-15.0, 15.0);
      case 'tilt-right':
        b.angle = (b.angle + 3).clamp(-15.0, 15.0);
      case 'straighten':
        b.angle = 0;
      case 'duplicate':
        final json = b.toJson()..['id'] = newId();
        final copy = Block.fromJson(json)
          ..x = b.x! + 20
          ..y = b.y! + 20;
        store.addBlock(widget.page, copy);
        return;
      case 'erase':
        widget.page.blocks.remove(b);
        widget.onRemoved();
    }
    store.changed();
  }
}
