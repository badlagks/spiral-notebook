import 'package:flutter/material.dart';

import '../../models/notebook.dart';
import '../paper_painters.dart';
import '../store_scope.dart';
import '../theme.dart';

class ChecklistView extends StatefulWidget {
  const ChecklistView({super.key, required this.block, this.fontSize = 19});

  final ChecklistBlock block;
  final double fontSize;

  @override
  State<ChecklistView> createState() => _ChecklistViewState();
}

class _ChecklistViewState extends State<ChecklistView> {
  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  TextEditingController _controllerFor(ChecklistItem item) =>
      _controllers.putIfAbsent(item.id, () => TextEditingController(text: item.text));

  FocusNode _focusFor(ChecklistItem item) => _focusNodes.putIfAbsent(item.id, () {
        final node = FocusNode();
        node.addListener(() {
          // Leaving an empty item tidies it away.
          if (!node.hasFocus && item.text.trim().isEmpty && widget.block.items.length > 1) {
            _remove(item);
          }
        });
        return node;
      });

  void _remove(ChecklistItem item) {
    if (!widget.block.items.contains(item)) return;
    setState(() => widget.block.items.remove(item));
    StoreScope.read(context).changed();
  }

  void _insertAfter(ChecklistItem item) {
    final next = ChecklistItem();
    final at = widget.block.items.indexOf(item) + 1;
    setState(() => widget.block.items.insert(at, next));
    StoreScope.read(context).changed();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusFor(next).requestFocus());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in widget.block.items)
          Row(
            key: ValueKey(item.id),
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                checked: item.done,
                button: true,
                label: item.text,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => item.done = !item.done);
                    StoreScope.read(context).changed();
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 10, 4),
                    child: SizedBox.square(
                      dimension: 18,
                      child: CustomPaint(painter: CheckboxPainter(checked: item.done)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _controllerFor(item),
                  focusNode: _focusFor(item),
                  style: handwriting.copyWith(
                    fontSize: widget.fontSize,
                    color: item.done ? Pen.blue.withValues(alpha: 0.75) : Pen.blue,
                  ),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration.collapsed(
                    hintText: 'To do…',
                    hintStyle: handwriting.copyWith(fontSize: widget.fontSize, color: Pen.pencil.withValues(alpha: 0.45)),
                  ),
                  onChanged: (text) {
                    item.text = text;
                    StoreScope.read(context).changedQuietly();
                  },
                  onSubmitted: (_) => _insertAfter(item),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
