import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'paper_painters.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Width of the coil between two pages, in paper units.
const spineWidth = 34.0;

/// How wide the strip along a page's outer edge is that you grab to turn it.
const _grabStrip = 44.0;

/// Builds the page at [index] of the open section, or a blank sheet past the end.
typedef PageBuilder = Widget Function(int index, {required bool bindingOnLeft, required bool interactive});

/// Lets other widgets (buttons, keys) ask the book to turn a page with the animation.
class FlipController extends ChangeNotifier {
  int _request = 0;
  int get request => _request;

  /// +1 turns forward, -1 turns back.
  void flip(int direction) {
    _request = direction;
    notifyListeners();
  }
}

/// The open book, in paper units: two pages and the coil when [spread] is
/// true, otherwise one page with the coil down its left edge. Grab a page by
/// its outer edge (finger or mouse) and drag to turn it, or tap that edge.
class FlippingBook extends StatefulWidget {
  const FlippingBook({super.key, required this.spread, required this.controller, required this.buildPage});

  final bool spread;
  final FlipController controller;
  final PageBuilder buildPage;

  @override
  State<FlippingBook> createState() => _FlippingBookState();
}

class _FlippingBookState extends State<FlippingBook> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  int _dir = 0; // +1 forward, -1 back, 0 at rest
  double _dragStartX = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onRequest);
    _anim.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(FlippingBook old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onRequest);
      widget.controller.addListener(_onRequest);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onRequest);
    _anim.dispose();
    super.dispose();
  }

  int get _step => widget.spread ? 2 : 1;
  double get _travel => widget.spread ? pageWidth * 1.6 : pageWidth;

  /// The page shown on the left of a spread (or the only page).
  int _first(int pageIndex) => widget.spread ? pageIndex - pageIndex % 2 : pageIndex;

  bool _canTurn(int dir) {
    final store = StoreScope.read(context);
    return dir > 0 || _first(store.pageIndex) > 0;
  }

  void _onRequest() => _turn(widget.controller.request);

  Future<void> _turn(int dir) async {
    if (_dir != 0 || !_canTurn(dir)) return;
    FocusScope.of(context).unfocus();
    setState(() => _dir = dir);
    await _anim.forward(from: _anim.value);
    _finish();
  }

  void _finish() {
    final store = StoreScope.read(context);
    final dir = _dir;
    setState(() {
      _dir = 0;
      _anim.value = 0;
    });
    if (dir != 0) store.turnPage(dir * _step);
  }

  void _dragStart(int dir, DragStartDetails d) {
    if (_dir != 0 || !_canTurn(dir)) return;
    FocusScope.of(context).unfocus();
    _dragStartX = d.localPosition.dx;
    setState(() => _dir = dir);
  }

  void _dragUpdate(int dir, DragUpdateDetails d) {
    if (_dir != dir) return;
    final moved = (d.localPosition.dx - _dragStartX) * -dir;
    _anim.value = (moved / _travel).clamp(0.0, 1.0);
  }

  Future<void> _dragEnd(int dir, DragEndDetails d) async {
    if (_dir != dir) return;
    final fling = -dir * d.velocity.pixelsPerSecond.dx;
    if (_anim.value > 0.25 || fling > 600) {
      await _anim.forward();
      _finish();
    } else {
      await _anim.reverse();
      setState(() => _dir = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final first = _first(store.pageIndex);
    return widget.spread ? _spread(first) : _single(first);
  }

  Widget _page(int index, {required bool left, bool interactive = true}) =>
      SizedBox(
        width: pageWidth,
        height: pageHeight,
        child: widget.buildPage(index, bindingOnLeft: !left, interactive: interactive && _dir == 0),
      );

  // ----- Two pages side by side -----

  Widget _spread(int l) {
    final t = _anim.value;
    Widget leftPage, rightPage;
    Widget? leaf;
    switch (_dir) {
      case 1:
        leftPage = _page(l, left: true);
        rightPage = _page(l + 3, left: false);
        leaf = t < 0.5
            ? _leaf(_page(l + 1, left: false), angle: -t * math.pi, hinge: Alignment.centerLeft, x: pageWidth + spineWidth, shade: t)
            : _leaf(_page(l + 2, left: true), angle: (1 - t) * math.pi, hinge: Alignment.centerRight, x: 0, shade: 1 - t);
      case -1:
        leftPage = _page(l - 2, left: true);
        rightPage = _page(l + 1, left: false);
        leaf = t < 0.5
            ? _leaf(_page(l, left: true), angle: t * math.pi, hinge: Alignment.centerRight, x: 0, shade: t)
            : _leaf(_page(l - 1, left: false), angle: -(1 - t) * math.pi, hinge: Alignment.centerLeft, x: pageWidth + spineWidth, shade: 1 - t);
      default:
        leftPage = _page(l, left: true);
        rightPage = _page(l + 1, left: false);
    }
    return SizedBox(
      width: pageWidth * 2 + spineWidth,
      height: pageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(key: const ValueKey('left'), left: 0, top: 0, child: leftPage),
          Positioned(key: const ValueKey('right'), left: pageWidth + spineWidth, top: 0, child: rightPage),
          const Positioned(
            key: ValueKey('spine'),
            left: pageWidth,
            top: 0,
            width: spineWidth,
            height: pageHeight,
            child: ColoredBox(color: Color(0xFFE9DFC8), child: CustomPaint(painter: SpiralPainter())),
          ),
          ?leaf,
          // Grab strips on the outer edges, with a turned-up corner as a hint.
          // Keyed so a drag in progress survives the leaf being added above.
          Positioned(key: const ValueKey('grab-back'), left: 0, top: 0, bottom: 0, width: _grabStrip, child: _grab(-1, cornerOnLeft: true)),
          Positioned(key: const ValueKey('grab-next'), right: 0, top: 0, bottom: 0, width: _grabStrip, child: _grab(1, cornerOnLeft: false)),
        ],
      ),
    );
  }

  // ----- One page, coil on the left -----

  Widget _single(int p) {
    final t = _anim.value;
    Widget base;
    Widget? leaf;
    switch (_dir) {
      case 1:
        base = _page(p + 1, left: false);
        leaf = _leaf(_page(p, left: false), angle: -t * math.pi / 2, hinge: Alignment.centerLeft, x: 0, shade: t);
      case -1:
        base = _page(p, left: false);
        leaf = _leaf(_page(p - 1, left: false), angle: -(1 - t) * math.pi / 2, hinge: Alignment.centerLeft, x: 0, shade: 1 - t);
      default:
        base = _page(p, left: false);
    }
    return SizedBox(
      width: pageWidth,
      height: pageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(key: const ValueKey('base'), child: base),
          ?leaf,
          const Positioned(
            key: ValueKey('spine'),
            left: -8,
            top: 0,
            bottom: 0,
            width: 30,
            child: IgnorePointer(child: CustomPaint(painter: SpiralPainter())),
          ),
          Positioned(
            key: const ValueKey('grab-back'),
            left: 22,
            top: 0,
            bottom: 0,
            width: 28,
            child: _grab(-1, cornerOnLeft: true, showCorner: false),
          ),
          Positioned(key: const ValueKey('grab-next'), right: 0, top: 0, bottom: 0, width: _grabStrip, child: _grab(1, cornerOnLeft: false)),
        ],
      ),
    );
  }

  /// A page caught mid-turn, swinging around its [hinge] edge.
  Widget _leaf(Widget page, {required double angle, required Alignment hinge, required double x, required double shade}) {
    return Positioned(
      key: const ValueKey('leaf'),
      left: x,
      top: 0,
      child: Transform(
        alignment: hinge,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0011)
          ..rotateY(angle),
        child: Stack(
          children: [
            page,
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.28 * math.sin(shade * math.pi / 2))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grab(int dir, {required bool cornerOnLeft, bool showCorner = true}) {
    final enabled = _dir == 0 || _dir == dir;
    return Semantics(
      button: true,
      label: dir > 0 ? 'Turn to the next page' : 'Turn back a page',
      child: MouseRegion(
        opaque: false,
        cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _dragStart(dir, d),
          onHorizontalDragUpdate: (d) => _dragUpdate(dir, d),
          onHorizontalDragEnd: (d) => _dragEnd(dir, d),
          child: Align(
            alignment: cornerOnLeft ? Alignment.bottomLeft : Alignment.bottomRight,
            // Tapping the turned-up corner turns the page too.
            child: showCorner && _dir == 0
                ? GestureDetector(
                    onTap: () => _turn(dir),
                    child: CustomPaint(size: const Size(30, 30), painter: _CornerPainter(onLeft: cornerOnLeft)),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

/// A slightly lifted page corner, hinting the page can be turned.
class _CornerPainter extends CustomPainter {
  const _CornerPainter({required this.onLeft});
  final bool onLeft;

  @override
  void paint(Canvas canvas, Size size) {
    if (onLeft) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final w = size.width, h = size.height;
    final fold = Path()
      ..moveTo(w, h - 22)
      ..lineTo(w - 22, h)
      ..lineTo(w - 4, h - 4)
      ..close();
    canvas.drawPath(
      Path()
        ..moveTo(w, h - 22)
        ..lineTo(w, h)
        ..lineTo(w - 22, h)
        ..close(),
      Paint()..color = Paper.desk.withValues(alpha: 0.85),
    );
    canvas.drawShadow(fold, Colors.black, 2, false);
    canvas.drawPath(fold, Paint()..color = const Color(0xFFEFE6D2));
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.onLeft != onLeft;
}

/// The back side of the last page: an empty sheet waiting to be written on.
class BlankSheet extends StatelessWidget {
  const BlankSheet({super.key, required this.bindingOnLeft, required this.onStart});

  final bool bindingOnLeft;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PaperPainter(style: PaperStyle.ruled, bindingOnLeft: bindingOnLeft),
      child: Center(
        child: onStart == null
            ? null
            : TextButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.edit_outlined, color: Pen.pencil),
                label: Text('Start a new page', style: handwriting.copyWith(color: Pen.pencil)),
              ),
      ),
    );
  }
}
