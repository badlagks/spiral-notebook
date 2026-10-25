import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/notebook.dart';
import 'ink.dart';
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
///
/// A turning page curls like paper: its corner follows your finger, it
/// folds along a slanted line, and its back side rolls over with a soft
/// shadow, showing the page underneath.
class FlippingBook extends StatefulWidget {
  const FlippingBook({super.key, required this.spread, required this.controller, required this.buildPage});

  final bool spread;
  final FlipController controller;
  final PageBuilder buildPage;

  @override
  State<FlippingBook> createState() => _FlippingBookState();
}

class _FlippingBookState extends State<FlippingBook> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this);

  // Every turn is drawn as a forward turn of the spread (or page) at [_base]:
  // its outer corner travels from [_rest] (lying flat) to [_turned] (turned
  // over). Turning back is the same picture played in reverse.
  int? _base;
  Offset _corner = Offset.zero;
  double _cornerY = pageHeight;

  // The animation in flight: from, to, and how far the corner lifts on the way.
  Offset _from = Offset.zero, _to = Offset.zero;
  double _lift = 0;
  Curve _curve = Curves.easeInOut;

  // A drag in progress.
  int _dragDir = 0;
  Offset _dragStart = Offset.zero, _cornerAtStart = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onRequest);
    _anim.addListener(_tick);
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
  bool get _busy => _base != null;

  /// The line the sheet turns around: the middle of the coil.
  double get _hingeX => widget.spread ? pageWidth + spineWidth / 2 : 0;

  /// How far the sheet's outer edge is from the hinge.
  double get _reach => widget.spread ? pageWidth + spineWidth / 2 : pageWidth;

  Offset get _rest => Offset(_hingeX + _reach, _cornerY);
  Offset get _turned => Offset(_hingeX - _reach, _cornerY);

  /// Where the turning sheet lies when flat.
  Rect get _sheet => widget.spread
      ? Rect.fromLTWH(pageWidth + spineWidth, 0, pageWidth, pageHeight)
      : Rect.fromLTWH(0, 0, pageWidth, pageHeight);

  /// How far over the sheet is, from 0 (flat) to 1 (turned).
  double get _progress => ((_rest.dx - _corner.dx) / (2 * _reach)).clamp(0.0, 1.0);

  /// The page shown on the left of a spread (or the only page).
  int _first(int pageIndex) => widget.spread ? pageIndex - pageIndex % 2 : pageIndex;

  bool _canTurn(int dir) => dir > 0 || _first(StoreScope.read(context).pageIndex) > 0;

  /// Paper stays fixed to the coil, so the corner can't be pulled further
  /// from it than the sheet is wide (or, diagonally, than it is long).
  Offset _attached(Offset p) {
    Offset keep(Offset p, Offset pin, double r) {
      final d = p - pin;
      return d.distance <= r ? p : pin + d / d.distance * r;
    }

    final near = Offset(_hingeX, _cornerY);
    final far = Offset(_hingeX, pageHeight - _cornerY);
    p = keep(p, near, _reach);
    return keep(p, far, math.sqrt(_reach * _reach + pageHeight * pageHeight));
  }

  void _begin(int dir, {required double cornerY}) {
    FocusScope.of(context).unfocus();
    final first = _first(StoreScope.read(context).pageIndex);
    _cornerY = cornerY;
    _base = dir > 0 ? first : first - _step;
    _corner = dir > 0 ? _rest : _turned;
  }

  void _tick() {
    final a = _curve.transform(_anim.value);
    final lift = _lift * math.sin(a * math.pi) * (_cornerY == 0 ? 1 : -1);
    setState(() => _corner = _attached(Offset.lerp(_from, _to, a)! + Offset(0, lift)));
  }

  Future<void> _animateTo(Offset target, {double lift = 0, int ms = 520, Curve curve = Curves.easeInOut}) async {
    _from = _corner;
    _to = target;
    _lift = lift;
    _curve = curve;
    _anim.duration = Duration(milliseconds: ms);
    await _anim.forward(from: 0);
    if (!mounted) return;
    final store = StoreScope.read(context);
    final shownFirst = target == _turned ? _base! + _step : _base!;
    final delta = shownFirst - _first(store.pageIndex);
    setState(() => _base = null);
    if (delta != 0) store.turnPage(delta);
  }

  void _onRequest() => _turn(widget.controller.request);

  Future<void> _turn(int dir) async {
    if (_busy || !_canTurn(dir)) return;
    setState(() => _begin(dir, cornerY: pageHeight));
    await _animateTo(dir > 0 ? _turned : _rest, lift: pageHeight * 0.22, ms: 760);
  }

  void _onDragStart(int dir, DragStartDetails d) {
    if (_busy || !_canTurn(dir)) return;
    setState(() {
      _begin(dir, cornerY: d.localPosition.dy < pageHeight / 2 ? 0 : pageHeight);
      _dragDir = dir;
      _dragStart = d.localPosition;
      _cornerAtStart = _corner;
    });
  }

  void _onDragUpdate(int dir, DragUpdateDetails d) {
    if (_dragDir != dir) return;
    final moved = d.localPosition - _dragStart;
    // One page on a phone is narrow, so the corner runs ahead of the finger.
    final k = widget.spread ? 1.0 : 2.0;
    setState(() => _corner = _attached(_cornerAtStart + Offset(moved.dx * k, moved.dy)));
  }

  Future<void> _onDragEnd(int dir, DragEndDetails d) async {
    if (_dragDir != dir) return;
    _dragDir = 0;
    final fling = -dir * d.velocity.pixelsPerSecond.dx;
    final turnedBy = dir > 0 ? _progress : 1 - _progress;
    final complete = turnedBy > 0.25 || fling > 600;
    final toTurned = complete == dir > 0;
    await _animateTo(toTurned ? _turned : _rest, ms: 360, curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final first = _first(store.pageIndex);
    return widget.spread ? _spread(first) : _single(first);
  }

  Widget _page(int index, {required bool left}) => SizedBox(
    width: pageWidth,
    height: pageHeight,
    child: widget.buildPage(index, bindingOnLeft: !left, interactive: !_busy),
  );

  // ----- Two pages side by side -----

  Widget _spread(int l) {
    final b = _base;
    final List<Widget> layers;
    if (b == null) {
      layers = [
        Positioned(left: 0, top: 0, child: _page(l, left: true)),
        Positioned(left: pageWidth + spineWidth, top: 0, child: _page(l + 1, left: false)),
        _spine(),
      ];
    } else {
      layers = [
        Positioned(left: 0, top: 0, child: _page(b, left: true)),
        Positioned(left: pageWidth + spineWidth, top: 0, child: _page(b + 3, left: false)),
        _spine(),
        ..._curl(front: _page(b + 1, left: false), back: _page(b + 2, left: true), backLeft: 0),
      ];
    }
    return SizedBox(
      width: pageWidth * 2 + spineWidth,
      height: pageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            key: const ValueKey('pages'),
            child: Stack(clipBehavior: Clip.none, children: layers),
          ),
          // Grab strips on the outer edges, with a turned-up corner as a hint.
          // Keyed so a drag in progress survives the pages changing underneath.
          Positioned(
            key: const ValueKey('grab-back'),
            left: 0,
            top: 0,
            bottom: 0,
            width: _grabStrip,
            child: _grab(-1, cornerOnLeft: true),
          ),
          Positioned(
            key: const ValueKey('grab-next'),
            right: 0,
            top: 0,
            bottom: 0,
            width: _grabStrip,
            child: _grab(1, cornerOnLeft: false),
          ),
        ],
      ),
    );
  }

  Widget _spine() => Positioned(
    left: pageWidth,
    top: 0,
    width: spineWidth,
    height: pageHeight,
    child: Paper.plain
        // Plain paper just has a faint fold down the middle.
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Paper.sheet, Color.lerp(Paper.sheet, Colors.black, 0.035)!, Paper.sheet],
              ),
            ),
          )
        : const ColoredBox(
            color: Color(0xFFE9DFC8),
            child: CustomPaint(painter: SpiralPainter()),
          ),
  );

  // ----- One page, coil on the left -----

  Widget _single(int p) {
    final b = _base;
    final List<Widget> layers;
    if (b == null) {
      layers = [Positioned.fill(child: _page(p, left: false))];
    } else {
      layers = [
        Positioned.fill(child: _page(b + 1, left: false)),
        // The back of a sheet in a one-page notebook is plain paper.
        ..._curl(
          front: _page(b, left: false),
          back: SizedBox(
            width: pageWidth,
            height: pageHeight,
            child: CustomPaint(painter: PaperPainter(style: PaperStyle.blank, bindingOnLeft: false)),
          ),
          backLeft: 0,
          backIsMirror: true,
        ),
      ];
    }
    return SizedBox(
      width: pageWidth,
      height: pageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The page rolls away over the coil and out of sight.
          Positioned.fill(
            key: const ValueKey('pages'),
            child: ClipRect(child: Stack(children: layers)),
          ),
          if (!Paper.plain)
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
          Positioned(
            key: const ValueKey('grab-next'),
            right: 0,
            top: 0,
            bottom: 0,
            width: _grabStrip,
            child: _grab(1, cornerOnLeft: false),
          ),
        ],
      ),
    );
  }

  /// The turning sheet: the part still lying flat, the part folded over
  /// (showing [back]), and the shadows that make it look curled.
  ///
  /// [back] is laid out where it lies once the sheet is turned, at [backLeft].
  /// With [backIsMirror] it is the sheet's own reverse side instead.
  List<Widget> _curl({
    required Widget front,
    required Widget back,
    required double backLeft,
    bool backIsMirror = false,
  }) {
    final fold = _Fold(rest: _rest, corner: _corner, sheet: _sheet);
    final sheet = Positioned(left: _sheet.left, top: 0, child: front);
    if (fold.flat) return [sheet];

    // Reflecting across the fold, after reflecting across the coil, carries
    // the next page from where it will lie to where it is now.
    final mirror = fold.reflection;
    final toNow = backIsMirror
        ? (mirror..translateByDouble(_sheet.left - backLeft, 0, 0, 1))
        : (mirror
            ..translateByDouble(2 * _hingeX, 0, 0, 1)
            ..scaleByDouble(-1, 1, 1, 1));
    return [
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _UnderShadowPainter(fold))),
      ),
      Positioned.fill(
        child: ClipPath(
          clipper: _PolygonClipper(fold.flatPart),
          child: Stack(children: [sheet]),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _DropShadowPainter(fold))),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: ClipPath(
            clipper: _PolygonClipper(fold.foldedPart),
            child: Transform(
              transform: toNow,
              child: Stack(
                clipBehavior: Clip.none,
                children: [Positioned(left: backLeft, top: 0, child: back)],
              ),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _RollPainter(fold))),
      ),
    ];
  }

  Widget _grab(int dir, {required bool cornerOnLeft, bool showCorner = true}) {
    final corner = showCorner && !_busy
        ? GestureDetector(
            onTap: () => _turn(dir),
            child: CustomPaint(
              size: const Size(30, 30),
              painter: _CornerPainter(onLeft: cornerOnLeft),
            ),
          )
        : null;
    final align = cornerOnLeft ? Alignment.bottomLeft : Alignment.bottomRight;
    // While drawing, the page edges are for ink; the corner still turns pages.
    if (InkScope.of(context).drawing) return Align(alignment: align, child: corner);
    final enabled = !_busy || _dragDir == dir;
    return Semantics(
      button: true,
      label: dir > 0 ? 'Turn to the next page' : 'Turn back a page',
      child: MouseRegion(
        opaque: false,
        cursor: enabled ? SystemMouseCursors.grab : MouseCursor.defer,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (d) => _onDragStart(dir, d),
          onHorizontalDragUpdate: (d) => _onDragUpdate(dir, d),
          onHorizontalDragEnd: (d) => _onDragEnd(dir, d),
          // Tapping the turned-up corner turns the page too.
          child: Align(alignment: align, child: corner),
        ),
      ),
    );
  }
}

/// Where a sheet folds when its corner is lifted from [rest] to [corner]:
/// along the line halfway between them, at right angles to the pull.
class _Fold {
  _Fold({required this.rest, required this.corner, required this.sheet}) {
    final pull = corner - rest;
    flat = pull.distance < 0.5;
    normal = flat ? const Offset(-1, 0) : pull / pull.distance;
    mid = (rest + corner) / 2;
    final outline = [sheet.topLeft, sheet.topRight, sheet.bottomRight, sheet.bottomLeft];
    flatPart = flat ? outline : _cut(outline, keepAhead: true);
    foldedPart = flat ? const [] : [for (final p in _cut(outline, keepAhead: false)) reflect(p)];
  }

  final Offset rest, corner;
  final Rect sheet;
  late final bool flat;
  late final Offset normal, mid;

  /// The part of the sheet still lying flat, on the coil's side of the fold.
  late final List<Offset> flatPart;

  /// The lifted part, where it is now: folded over on top.
  late final List<Offset> foldedPart;

  /// How far over the fold the corner has gone.
  double get depth => (corner - rest).distance / 2;

  double side(Offset p) => (p.dx - mid.dx) * normal.dx + (p.dy - mid.dy) * normal.dy;

  Offset reflect(Offset p) => p - normal * (2 * side(p));

  Matrix4 get reflection {
    final (nx, ny) = (normal.dx, normal.dy);
    final k = 2 * (mid.dx * nx + mid.dy * ny);
    return Matrix4(
      1 - 2 * nx * nx,
      -2 * nx * ny,
      0,
      0, //
      -2 * nx * ny,
      1 - 2 * ny * ny,
      0,
      0,
      0,
      0,
      1,
      0,
      k * nx,
      k * ny,
      0,
      1,
    );
  }

  /// Cuts a convex outline along the fold, keeping one side.
  List<Offset> _cut(List<Offset> poly, {required bool keepAhead}) {
    bool inside(Offset p) => keepAhead ? side(p) >= 0 : side(p) < 0;
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i], b = poly[(i + 1) % poly.length];
      if (inside(a)) out.add(a);
      if (inside(a) != inside(b)) {
        final t = side(a) / (side(a) - side(b));
        out.add(Offset.lerp(a, b, t)!);
      }
    }
    return out;
  }

  Path pathOf(List<Offset> pts) => pts.isEmpty ? Path() : (Path()..addPolygon(pts, true));
}

class _PolygonClipper extends CustomClipper<Path> {
  _PolygonClipper(this.points);
  final List<Offset> points;

  @override
  Path getClip(Size size) => points.isEmpty ? Path() : (Path()..addPolygon(points, true));

  @override
  bool shouldReclip(_PolygonClipper old) => true;
}

/// The shadow the lifted paper casts on the page underneath, next to the fold.
class _UnderShadowPainter extends CustomPainter {
  _UnderShadowPainter(this.fold);
  final _Fold fold;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = math.min(46.0, fold.depth * 0.6 + 6);
    canvas.save();
    canvas.clipRect(fold.sheet);
    canvas.drawRect(
      fold.sheet,
      Paint()
        ..shader = ui.Gradient.linear(fold.mid, fold.mid - fold.normal * reach, [
          Colors.black.withValues(alpha: 0.32),
          Colors.black.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UnderShadowPainter old) => true;
}

/// The soft shadow under the folded-over part.
class _DropShadowPainter extends CustomPainter {
  _DropShadowPainter(this.fold);
  final _Fold fold;

  @override
  void paint(Canvas canvas, Size size) {
    if (fold.foldedPart.length < 3) return;
    canvas.drawShadow(fold.pathOf(fold.foldedPart), Colors.black, 6, false);
  }

  @override
  bool shouldRepaint(_DropShadowPainter old) => true;
}

/// Light and shade across the folded part so it looks rolled, not flat:
/// dark in the crease, a highlight where it bends, then fading out.
class _RollPainter extends CustomPainter {
  _RollPainter(this.fold);
  final _Fold fold;

  @override
  void paint(Canvas canvas, Size size) {
    if (fold.foldedPart.length < 3) return;
    final width = math.max(fold.depth, 1.0);
    canvas.drawPath(
      fold.pathOf(fold.foldedPart),
      Paint()
        ..shader = ui.Gradient.linear(
          fold.mid,
          fold.mid + fold.normal * width,
          [
            Colors.black.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.10),
          ],
          const [0, 0.12, 0.45, 1],
        ),
    );
    // The crease itself.
    canvas.drawPath(
      fold.pathOf(fold.flatPart),
      Paint()
        ..shader = ui.Gradient.linear(fold.mid, fold.mid + fold.normal * math.min(18.0, width), [
          Colors.black.withValues(alpha: 0.14),
          Colors.black.withValues(alpha: 0),
        ]),
    );
  }

  @override
  bool shouldRepaint(_RollPainter old) => true;
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
      Paint()..color = Paper.plain ? Color.lerp(Paper.sheet, Colors.black, 0.12)! : Paper.desk.withValues(alpha: 0.85),
    );
    canvas.drawShadow(fold, Colors.black, 2, false);
    canvas.drawPath(fold, Paint()..color = const Color(0xFFEFE6D2));
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.onLeft != onLeft;
}

/// The back side of the last page: an empty sheet waiting to be written on.
class BlankSheet extends StatelessWidget {
  const BlankSheet({super.key, required this.bindingOnLeft, required this.onStart, this.onTemplate});

  final bool bindingOnLeft;
  final VoidCallback? onStart;
  final VoidCallback? onTemplate;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: PaperPainter(style: PaperStyle.ruled, bindingOnLeft: bindingOnLeft),
      child: Center(
        child: onStart == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.edit_outlined, color: Pen.pencil),
                    label: Text('Start a new page', style: handwriting.copyWith(color: Pen.pencil)),
                  ),
                  if (onTemplate != null)
                    TextButton.icon(
                      onPressed: onTemplate,
                      icon: const Icon(Icons.dashboard_customize_outlined, color: Pen.pencil),
                      label: Text('or use a template', style: handwriting.copyWith(color: Pen.pencil, fontSize: 17)),
                    ),
                ],
              ),
      ),
    );
  }
}
