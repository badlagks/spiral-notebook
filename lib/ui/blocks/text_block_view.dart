import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/notebook.dart';
import '../store_scope.dart';
import '../theme.dart';

class TextBlockView extends StatefulWidget {
  const TextBlockView({super.key, required this.block, this.autofocus = false});

  final TextBlock block;
  final bool autofocus;

  @override
  State<TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<TextBlockView> {
  late final _controller = TextEditingController(text: widget.block.text);

  @override
  void didUpdateWidget(TextBlockView old) {
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
    final block = widget.block;
    final style = block.kind == TextKind.heading ? headingHandwriting.copyWith(fontSize: 28) : handwriting;
    final field = TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      maxLines: null,
      style: style,
      inputFormatters: [OutlineContinuationFormatter()],
      decoration: InputDecoration.collapsed(
        hintText: block.kind == TextKind.heading
            ? 'Heading'
            : block.highlight
            ? 'Highlight'
            // Narrow boxes (like in templates) get the short hint.
            : block.width < 340
            ? 'Write here…'
            : 'Write here… start a line with "- " for an outline',
        hintStyle: style.copyWith(color: Pen.pencil.withValues(alpha: 0.45)),
      ),
      onChanged: (text) {
        block.text = text;
        StoreScope.read(context).changedQuietly();
        // The highlight grows with the text.
        if (block.highlight) setState(() {});
      },
    );
    if (!block.highlight) return field;
    // A highlighter stroke: translucent, a little uneven, hugging the text.
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: _controller.text.isEmpty ? 'Highlight' : _controller.text, style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        final width = (painter.width + 24).clamp(60.0, constraints.maxWidth);
        painter.dispose();
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              color: Pen.highlighter,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(8),
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(3),
              ),
            ),
            child: field,
          ),
        );
      },
    );
  }
}

/// When Enter is pressed on an outline line ("  - item"), starts the next
/// line with the same indent and dash. Enter on an empty item ends the outline.
class OutlineContinuationFormatter extends TextInputFormatter {
  static final _bullet = RegExp(r'^(\s*)([-•*])\s');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = newValue.selection;
    final insertedNewline =
        newValue.text.length == oldValue.text.length + 1 &&
        sel.isCollapsed &&
        sel.baseOffset > 0 &&
        newValue.text[sel.baseOffset - 1] == '\n';
    if (!insertedNewline) return newValue;

    final before = newValue.text.substring(0, sel.baseOffset - 1);
    final lineStart = before.lastIndexOf('\n') + 1;
    final line = before.substring(lineStart);
    final m = _bullet.firstMatch(line);
    if (m == null) return newValue;

    final after = newValue.text.substring(sel.baseOffset);
    if (line.trim() == m.group(2)) {
      // Empty bullet: remove it instead of adding another.
      final text = newValue.text.substring(0, lineStart) + after;
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: lineStart),
      );
    }
    final prefix = '${m.group(1)}${m.group(2)} ';
    final text = '$before\n$prefix$after';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: before.length + 1 + prefix.length),
    );
  }
}
