import 'package:flutter/material.dart';

import '../../models/notebook.dart';
import 'calculator_view.dart';
import 'checklist_view.dart';
import 'media_view.dart';
import 'sheet_view.dart';
import 'sticky_view.dart';
import 'text_block_view.dart';

/// The view for any block, sized to the block's width. Spreadsheets and
/// calculators are drawn at their natural size and scaled to fit.
Widget blockContent(Block block, {bool autofocus = false}) => switch (block) {
      TextBlock() => TextBlockView(block: block, autofocus: autofocus),
      StickyBlock() => StickyView(block: block),
      ChecklistBlock() => ChecklistView(block: block),
      SheetBlock() => _Scaled(width: block.width, child: SheetView(block: block)),
      CalculatorBlock() => _Scaled(width: block.width, child: CalculatorView(block: block)),
      MediaBlock() => MediaView(key: ValueKey(block.id), block: block),
    };

class _Scaled extends StatelessWidget {
  const _Scaled({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: FittedBox(fit: BoxFit.fitWidth, alignment: Alignment.topLeft, child: child),
      );
}
