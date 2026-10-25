import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'paper_painters.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Lets the person choose the spiral notebook or plain paper, in cream or white.
Future<void> showLookPicker(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _LookDialog(),
    );

class _LookDialog extends StatefulWidget {
  const _LookDialog();

  @override
  State<_LookDialog> createState() => _LookDialogState();
}

class _LookDialogState extends State<_LookDialog> {
  late Look _look = Paper.look;
  late PaperTone _tone = Paper.tone;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFF6F1E4),
      title: const Text('How should it look?'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Choice(
                    label: 'Spiral notebook',
                    detail: 'Pages on a desk, with a coil and tabs',
                    selected: _look == Look.notebook,
                    onTap: () => setState(() => _look = Look.notebook),
                    preview: _Preview(look: Look.notebook, tone: _tone),
                  ),
                  _Choice(
                    label: 'Plain paper',
                    detail: 'Clean paper with no lines, filling the screen',
                    selected: _look == Look.plain,
                    onTap: () => setState(() => _look = Look.plain),
                    preview: _Preview(look: Look.plain, tone: _tone),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text('Paper colour', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<PaperTone>(
                segments: const [
                  ButtonSegment(value: PaperTone.cream, label: Text('Cream')),
                  ButtonSegment(value: PaperTone.white, label: Text('White')),
                ],
                selected: {_tone},
                onSelectionChanged: (s) => setState(() => _tone = s.first),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final store = StoreScope.read(context);
            Navigator.pop(context);
            store.setAppearance(look: _look, tone: _tone);
          },
          child: const Text('Use this look'),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
    required this.preview,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 210,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? Pen.blue : const Color(0x22000000), width: selected ? 2.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(aspectRatio: 1.45, child: preview),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
                    if (selected) const Icon(Icons.check_circle, size: 18, color: Pen.blue),
                  ],
                ),
                Text(detail, style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tiny picture of each look.
class _Preview extends StatelessWidget {
  const _Preview({required this.look, required this.tone});
  final Look look;
  final PaperTone tone;

  @override
  Widget build(BuildContext context) {
    final sheet = tone == PaperTone.white ? Paper.white : Paper.cream;
    Widget page() => DecoratedBox(
          decoration: BoxDecoration(color: sheet),
          child: look == Look.notebook ? const CustomPaint(painter: _MiniLines()) : null,
        );
    if (look == Look.plain) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0x22000000)),
        ),
        child: Padding(padding: const EdgeInsets.all(6), child: page()),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Paper.desk, borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(colors: [Paper.cover, Paper.coverDark]),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: page()),
            const SizedBox(
              width: 12,
              child: ColoredBox(color: Color(0xFFE9DFC8), child: CustomPaint(painter: SpiralPainter(ringSpacing: 8))),
            ),
            Expanded(child: page()),
          ],
        ),
      ),
    );
  }
}

class _MiniLines extends CustomPainter {
  const _MiniLines();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Paper.ruleLine
      ..strokeWidth = 0.8;
    for (var y = 14.0; y < size.height - 2; y += 7) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(const Offset(10, 0), Offset(10, size.height), Paint()..color = Paper.margin);
  }

  @override
  bool shouldRepaint(_MiniLines old) => false;
}
