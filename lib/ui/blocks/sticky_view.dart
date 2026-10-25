import 'package:flutter/material.dart';

import '../../models/notebook.dart';
import '../store_scope.dart';
import '../theme.dart';

/// Sticky note colors offered in its menu.
const stickyColors = <int>[0xFFFFF59D, 0xFFFFCC80, 0xFFB2EBF2, 0xFFC5E1A5, 0xFFF8BBD0];

/// A square paper note with a slightly darker glue strip along the top.
class StickyView extends StatefulWidget {
  const StickyView({super.key, required this.block});

  final StickyBlock block;

  @override
  State<StickyView> createState() => _StickyViewState();
}

class _StickyViewState extends State<StickyView> {
  late final _controller = TextEditingController(text: widget.block.text);

  @override
  void didUpdateWidget(StickyView old) {
    super.didUpdateWidget(old);
    if (widget.block.text != _controller.text) _controller.text = widget.block.text;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(widget.block.color);
    return Container(
      constraints: BoxConstraints(minHeight: widget.block.width * 0.85),
      decoration: BoxDecoration(
        color: color,
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(2, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 14, color: Color.lerp(color, Colors.black, 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: TextField(
              controller: _controller,
              maxLines: null,
              style: handwriting.copyWith(fontSize: 18, height: 1.3),
              decoration: InputDecoration.collapsed(
                hintText: 'Note…',
                hintStyle: handwriting.copyWith(color: Pen.pencil.withValues(alpha: 0.5)),
              ),
              onChanged: (t) {
                widget.block.text = t;
                StoreScope.read(context).changedQuietly();
              },
            ),
          ),
        ],
      ),
    );
  }
}
