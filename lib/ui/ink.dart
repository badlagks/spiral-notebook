import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/notebook_store.dart';
import '../models/notebook.dart';
import 'store_scope.dart';

enum DrawTool { pen, highlighter, eraser, lasso }

/// Ink colors offered for the pen. The highlighter has its own set.
const penColors = <int>[0xFF1F3A73, 0xFF222222, 0xFFC0392B, 0xFF2E7D32, 0xFF8E44AD];
const highlighterColors = <int>[0xFFFFEB3B, 0xFF7CF29C, 0xFFFF9EC7, 0xFF8FD3FF];

/// Pen sizes in paper units: fine, medium, bold.
const penSizes = <double>[1.6, 2.6, 4.2];

/// What the drawing tools are set to, shared by every page, plus undo and
/// redo for drawing on each page (kept until the app closes).
class InkController extends ChangeNotifier {
  bool _drawing = false;
  DrawTool _tool = DrawTool.pen;
  int _penColor = penColors.first;
  int _highlighterColor = highlighterColors.first;
  double _size = penSizes[1];
  bool _stylusSeen = false;

  final _undo = <String, List<_InkChange>>{};
  final _redo = <String, List<_InkChange>>{};

  /// The page drawn on most recently, which Undo and Redo act on.
  NotePage? _lastPage;

  /// Lines circled with the lasso, and the page they are on.
  Set<InkStroke> _selection = {};
  NotePage? _selectionPage;

  /// In drawing mode a finger or mouse draws; otherwise only a stylus does.
  bool get drawing => _drawing;
  DrawTool get tool => _tool;
  int get color => _tool == DrawTool.highlighter ? _highlighterColor : _penColor;
  double get size => _size;

  /// Once a stylus has been used, fingers no longer draw, so a resting
  /// palm leaves no marks.
  bool get stylusSeen => _stylusSeen;

  set drawing(bool v) {
    if (_drawing == v) return;
    _drawing = v;
    if (!v) _selection = {};
    notifyListeners();
  }

  set tool(DrawTool t) {
    _tool = t;
    _drawing = true;
    if (t != DrawTool.lasso) _selection = {};
    notifyListeners();
  }

  bool get hasSelection => _selection.isNotEmpty;
  Set<InkStroke> selectionOn(NotePage page) => _selectionPage == page ? _selection : const {};

  void select(NotePage page, Set<InkStroke> strokes) {
    _selection = strokes;
    _selectionPage = page;
    notifyListeners();
  }

  /// Changes the circled lines, as one step that can be undone.
  void _changeSelection(NotebookStore store, InkStroke? Function(InkStroke s) change) {
    final page = _selectionPage;
    if (page == null || _selection.isEmpty) return;
    final before = List.of(page.strokes);
    final kept = <InkStroke>{};
    for (var i = page.strokes.length - 1; i >= 0; i--) {
      if (!_selection.contains(page.strokes[i])) continue;
      final next = change(page.strokes[i]);
      if (next == null) {
        page.strokes.removeAt(i);
      } else {
        page.strokes[i] = next;
        kept.add(next);
      }
    }
    _selection = kept;
    _record(page, _InkChange.snapshot(before, List.of(page.strokes)));
    store.changed();
  }

  void recolorSelection(int color, NotebookStore store) => _changeSelection(store, (s) => s.transformed(color: color));
  void deleteSelection(NotebookStore store) => _changeSelection(store, (_) => null);

  set color(int c) {
    if (_tool == DrawTool.highlighter) {
      _highlighterColor = c;
    } else {
      _tool = DrawTool.pen;
      _penColor = c;
    }
    notifyListeners();
  }

  set size(double s) {
    _size = s;
    notifyListeners();
  }

  void noteStylus() {
    if (_stylusSeen) return;
    _stylusSeen = true;
    notifyListeners();
  }

  /// Whether a pointer of this kind should draw right now.
  bool draws(PointerDeviceKind kind) => switch (kind) {
    PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus => true,
    PointerDeviceKind.touch => _drawing && !_stylusSeen,
    _ => _drawing,
  };

  bool canUndo(NotePage? page) => page != null && (_undo[page.id]?.isNotEmpty ?? false);
  bool canRedo(NotePage? page) => page != null && (_redo[page.id]?.isNotEmpty ?? false);
  NotePage? get lastPage => _lastPage;

  void _record(NotePage page, _InkChange change) {
    _lastPage = page;
    (_undo[page.id] ??= []).add(change);
    _redo[page.id]?.clear();
    notifyListeners();
  }

  void undo(NotePage page, NotebookStore store) {
    final stack = _undo[page.id];
    if (stack == null || stack.isEmpty) return;
    final change = stack.removeLast();
    _selection = {};
    change.revert(page);
    (_redo[page.id] ??= []).add(change);
    store.changed();
    notifyListeners();
  }

  void redo(NotePage page, NotebookStore store) {
    final stack = _redo[page.id];
    if (stack == null || stack.isEmpty) return;
    final change = stack.removeLast();
    _selection = {};
    change.apply(page);
    (_undo[page.id] ??= []).add(change);
    store.changed();
    notifyListeners();
  }
}

/// A drawing step that can be undone: lines added, lines erased, or lines
/// moved, resized or recoloured with the lasso (kept as before and after).
class _InkChange {
  _InkChange.added(InkStroke s) : added = s, erased = const [], before = null, after = null;
  _InkChange.erased(this.erased) : added = null, before = null, after = null;
  _InkChange.snapshot(this.before, this.after) : added = null, erased = const [];

  final InkStroke? added;

  /// Erased lines with the position each had in the page's list.
  final List<(int, InkStroke)> erased;

  final List<InkStroke>? before, after;

  void apply(NotePage page) {
    if (after != null) {
      page.strokes
        ..clear()
        ..addAll(after!);
      return;
    }
    if (added != null) page.strokes.add(added!);
    for (final (_, s) in erased) {
      page.strokes.remove(s);
    }
  }

  void revert(NotePage page) {
    if (before != null) {
      page.strokes
        ..clear()
        ..addAll(before!);
      return;
    }
    if (added != null) page.strokes.remove(added);
    for (final (i, s) in erased) {
      page.strokes.insert(i.clamp(0, page.strokes.length), s);
    }
  }
}

class InkScope extends InheritedNotifier<InkController> {
  const InkScope({super.key, required InkController controller, required super.child}) : super(notifier: controller);

  static InkController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<InkScope>()!.notifier!;

  static InkController read(BuildContext context) => context.getInheritedWidgetOfExactType<InkScope>()!.notifier!;
}

/// The drawing on one page, and the surface that takes new drawing.
/// In drawing mode it catches every touch on the page; otherwise only a
/// stylus draws and everything else passes through to the widgets below.
class InkLayer extends StatefulWidget {
  const InkLayer({super.key, required this.page, this.interactive = true});

  final NotePage page;
  final bool interactive;

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  InkStroke? _live;
  int? _pointer;
  bool _erasing = false;
  final List<(int, InkStroke)> _erasedNow = [];
  final _liveRepaint = ValueNotifier(0);

  // The lasso: the loop being drawn, or circled lines being moved or resized.
  List<Offset>? _loop;
  _LassoDrag? _drag;

  /// Around the circled lines on this page, or null.
  Rect? _selectionBox(InkController ink) {
    final Iterable<InkStroke> sel = _drag?.current ?? ink.selectionOn(widget.page);
    if (sel.isEmpty) return null;
    Rect? box;
    for (final s in sel) {
      for (final p in s.points) {
        final r = Rect.fromCircle(center: Offset(p.x, p.y), radius: s.width / 2 + 2);
        box = box == null ? r : box.expandToInclude(r);
      }
    }
    return box?.inflate(6);
  }

  void _lassoDown(InkController ink, Offset at) {
    final box = _selectionBox(ink);
    if (box != null && box.inflate(10).contains(at)) {
      final resize = (at - box.bottomRight).distance < 22;
      _drag = _LassoDrag(
        before: List.of(widget.page.strokes),
        originals: ink.selectionOn(widget.page).toList(),
        start: at,
        box: box,
        resize: resize,
      );
      return;
    }
    ink.select(widget.page, {});
    _loop = [at];
    _liveRepaint.value++;
  }

  void _lassoMove(Offset at) {
    final loop = _loop;
    if (loop != null) {
      if ((loop.last - at).distance >= 2) loop.add(at);
      _liveRepaint.value++;
      return;
    }
    final d = _drag;
    if (d == null) return;
    final strokes = widget.page.strokes;
    final origin = d.box.topLeft;
    final scale = d.resize ? ((at - origin).distance / math.max((d.start - origin).distance, 1)).clamp(0.2, 5.0) : 1.0;
    final move = d.resize ? Offset.zero : at - d.start;
    for (var i = 0; i < d.originals.length; i++) {
      final index = strokes.indexOf(d.current[i]);
      if (index < 0) continue;
      final next = d.originals[i].transformed(dx: move.dx, dy: move.dy, scale: scale, ox: origin.dx, oy: origin.dy);
      strokes[index] = next;
      d.current[i] = next;
    }
    setState(() {});
  }

  void _lassoUp(InkController ink) {
    final loop = _loop;
    _loop = null;
    if (loop != null) {
      _liveRepaint.value++;
      if (loop.length < 3) return;
      ink.select(widget.page, {
        for (final s in widget.page.strokes)
          if (s.points.where((p) => _inside(loop, Offset(p.x, p.y))).length >= s.points.length * 0.6) s,
      });
      return;
    }
    final d = _drag;
    _drag = null;
    if (d == null || d.originals.every((s) => d.current.contains(s))) return;
    ink._record(widget.page, _InkChange.snapshot(d.before, List.of(widget.page.strokes)));
    ink.select(widget.page, d.current.toSet());
    StoreScope.read(context).changed();
  }

  /// Whether [p] is inside the closed loop [poly].
  static bool _inside(List<Offset> poly, Offset p) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i], b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  static double _pressure(PointerEvent e) {
    if (e.pressureMax <= e.pressureMin) return 0.5;
    return ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.05, 1.0);
  }

  void _down(PointerDownEvent e) {
    final ink = InkScope.read(context);
    if (e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus) ink.noteStylus();
    if (_pointer != null || !ink.draws(e.kind)) return;
    _pointer = e.pointer;
    if (ink.tool == DrawTool.lasso && e.kind != PointerDeviceKind.invertedStylus) {
      _lassoDown(ink, e.localPosition);
      return;
    }
    _erasing = ink.tool == DrawTool.eraser || e.kind == PointerDeviceKind.invertedStylus;
    if (_erasing) {
      _erasedNow.clear();
      _eraseAt(e.localPosition);
      return;
    }
    final highlighter = ink.tool == DrawTool.highlighter;
    _live = InkStroke(
      tool: highlighter ? InkTool.highlighter : InkTool.pen,
      color: ink.color,
      width: highlighter ? ink.size * 5 : ink.size,
      points: [InkPoint(e.localPosition.dx, e.localPosition.dy, _pressure(e))],
    );
    _liveRepaint.value++;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    if (_loop != null || _drag != null) {
      _lassoMove(e.localPosition);
      return;
    }
    if (_erasing) {
      _eraseAt(e.localPosition);
      return;
    }
    final s = _live;
    if (s == null) return;
    final last = s.points.last;
    // Skip points closer than half a unit: smoother lines, smaller files.
    if ((Offset(last.x, last.y) - e.localPosition).distance < 0.5) return;
    s.points.add(InkPoint(e.localPosition.dx, e.localPosition.dy, _pressure(e)));
    _liveRepaint.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    final store = StoreScope.read(context);
    final ink = InkScope.read(context);
    if (_loop != null || _drag != null) {
      _lassoUp(ink);
      return;
    }
    if (_erasing) {
      if (_erasedNow.isNotEmpty) {
        ink._record(widget.page, _InkChange.erased(List.of(_erasedNow)));
        store.changed();
      }
      return;
    }
    final s = _live;
    _live = null;
    if (s == null) return;
    widget.page.strokes.add(s);
    ink._record(widget.page, _InkChange.added(s));
    store.changed();
    setState(() {});
  }

  void _eraseAt(Offset at) {
    final strokes = widget.page.strokes;
    var hit = false;
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (strokes[i].passesNear(at.dx, at.dy, 8)) {
        _erasedNow.add((i, strokes.removeAt(i)));
        hit = true;
      }
    }
    if (hit) setState(() {});
  }

  @override
  void dispose() {
    _liveRepaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drawing = widget.interactive && InkScope.of(context).drawing;
    final art = Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: InkPainter(widget.page.strokes, version: widget.page.strokes.length)),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _LivePainter(() => _live, repaint: _liveRepaint)),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _LassoPainter(
              loop: () => _loop,
              box: widget.interactive ? _selectionBox(InkScope.of(context)) : null,
              repaint: _liveRepaint,
            ),
          ),
        ),
      ],
    );
    if (!widget.interactive) return IgnorePointer(child: art);
    return MouseRegion(
      opaque: false,
      cursor: drawing ? SystemMouseCursors.precise : MouseCursor.defer,
      child: Listener(
        // Drawing mode takes every touch; otherwise a stylus still draws but
        // fingers and the mouse reach the widgets underneath.
        behavior: drawing ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: IgnorePointer(child: art),
      ),
    );
  }
}

/// Circled lines being moved or resized with the lasso.
class _LassoDrag {
  _LassoDrag({
    required this.before,
    required this.originals,
    required this.start,
    required this.box,
    required this.resize,
  }) : current = List.of(originals);

  final List<InkStroke> before;
  final List<InkStroke> originals;
  final List<InkStroke> current;
  final Offset start;
  final Rect box;
  final bool resize;
}

/// The lasso loop while it's drawn, and a dashed box with a resize knob
/// around circled lines.
class _LassoPainter extends CustomPainter {
  _LassoPainter({required this.loop, required this.box, required Listenable repaint}) : super(repaint: repaint);

  final List<Offset>? Function() loop;
  final Rect? box;

  static void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = const Color(0xFF1F3A73)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final pts = loop();
    if (pts != null && pts.length > 1) {
      _dashed(canvas, Path()..addPolygon(pts, false), line);
    }
    final b = box;
    if (b != null) {
      canvas.drawRect(b, Paint()..color = const Color(0x141F3A73));
      _dashed(canvas, Path()..addRect(b), line);
      canvas.drawCircle(b.bottomRight, 7, Paint()..color = Colors.white);
      canvas.drawCircle(b.bottomRight, 7, line..style = PaintingStyle.stroke);
      canvas.drawCircle(b.bottomRight, 3, Paint()..color = const Color(0xFF1F3A73));
    }
  }

  @override
  bool shouldRepaint(_LassoPainter old) => old.box != box;
}

/// Paints finished lines. Pen lines thicken with pressure; highlighter
/// lines are flat, see-through and darken what is under them.
class InkPainter extends CustomPainter {
  InkPainter(this.strokes, {required this.version});

  final List<InkStroke> strokes;

  /// Changes whenever a line is added or removed, so the layer repaints.
  final int version;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      paintStroke(canvas, s);
    }
  }

  @override
  bool shouldRepaint(InkPainter old) => true;
}

class _LivePainter extends CustomPainter {
  _LivePainter(this.stroke, {required Listenable repaint}) : super(repaint: repaint);
  final InkStroke? Function() stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = stroke();
    if (s != null) paintStroke(canvas, s);
  }

  @override
  bool shouldRepaint(_LivePainter old) => false;
}

void paintStroke(Canvas canvas, InkStroke s) {
  final pts = s.points;
  if (pts.isEmpty) return;
  final color = Color(s.color);
  if (s.tool == InkTool.highlighter) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.multiply;
    canvas.drawPath(_smoothPath(pts), paint);
    return;
  }
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  if (pts.length == 1) {
    canvas.drawCircle(
      Offset(pts.first.x, pts.first.y),
      s.width * (0.5 + pts.first.pressure) / 2,
      Paint()..color = color,
    );
    return;
  }
  // Each piece goes from one midpoint to the next, curving through the
  // point between them, with its own width from that point's pressure.
  Offset mid(int i) => Offset((pts[i].x + pts[i + 1].x) / 2, (pts[i].y + pts[i + 1].y) / 2);
  var from = Offset(pts.first.x, pts.first.y);
  for (var i = 1; i < pts.length; i++) {
    final to = i == pts.length - 1 ? Offset(pts[i].x, pts[i].y) : mid(i);
    final through = Offset(pts[i].x, pts[i].y);
    final p = (pts[i - 1].pressure + pts[i].pressure) / 2;
    paint.strokeWidth = s.width * (0.4 + 1.2 * p);
    final piece = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(through.dx, through.dy, to.dx, to.dy);
    canvas.drawPath(piece, paint);
    from = to;
  }
}

Path _smoothPath(List<InkPoint> pts) {
  final path = Path()..moveTo(pts.first.x, pts.first.y);
  if (pts.length == 1) return path..lineTo(pts.first.x + 0.1, pts.first.y);
  for (var i = 1; i < pts.length - 1; i++) {
    final mx = (pts[i].x + pts[i + 1].x) / 2, my = (pts[i].y + pts[i + 1].y) / 2;
    path.quadraticBezierTo(pts[i].x, pts[i].y, mx, my);
  }
  path.lineTo(pts.last.x, pts.last.y);
  return path;
}

/// The floating drawing toolbar: tools, colors, sizes, undo and redo.
class DrawToolbar extends StatelessWidget {
  const DrawToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = InkScope.of(context);
    final store = StoreScope.of(context);
    final page = ink.lastPage ?? store.page;
    final colors = ink.tool == DrawTool.highlighter ? highlighterColors : penColors;
    final lassoing = ink.tool == DrawTool.lasso && ink.hasSelection;
    final narrow = MediaQuery.sizeOf(context).width < 560;

    Widget toolButton(DrawTool t, IconData icon, String tip) {
      final on = ink.tool == t;
      return IconButton(
        tooltip: tip,
        isSelected: on,
        style: IconButton.styleFrom(
          backgroundColor: on ? const Color(0xFFE3ECF8) : null,
          foregroundColor: on ? const Color(0xFF1F3A73) : const Color(0xFF555555),
        ),
        onPressed: () => ink.tool = t,
        icon: Icon(icon),
      );
    }

    final items = <Widget>[
      toolButton(DrawTool.pen, Icons.edit, 'Pen'),
      toolButton(DrawTool.highlighter, Icons.border_color, 'Highlighter'),
      toolButton(DrawTool.eraser, Icons.auto_fix_normal, 'Eraser: touch a line to remove it'),
      toolButton(DrawTool.lasso, Icons.highlight_alt, 'Lasso: circle lines to move, resize or recolour them'),
      _divider(),
      for (final c in colors)
        _ColorDot(
          color: c,
          selected: ink.color == c && ink.tool != DrawTool.eraser && ink.tool != DrawTool.lasso,
          onTap: () => lassoing ? ink.recolorSelection(c, store) : ink.color = c,
        ),
      if (lassoing)
        IconButton(
          tooltip: 'Delete the circled lines',
          onPressed: () => ink.deleteSelection(store),
          icon: const Icon(Icons.delete_outline),
        ),
      _divider(),
      for (final (i, s) in penSizes.indexed)
        _SizeDot(
          dot: 4.0 + i * 4,
          selected: ink.size == s,
          tip: const ['Fine', 'Medium', 'Bold'].elementAt(i),
          onTap: () => ink.size = s,
        ),
      _divider(),
      IconButton(
        tooltip: 'Undo',
        onPressed: ink.canUndo(page) ? () => ink.undo(page, store) : null,
        icon: const Icon(Icons.undo),
      ),
      IconButton(
        tooltip: 'Redo',
        onPressed: ink.canRedo(page) ? () => ink.redo(page, store) : null,
        icon: const Icon(Icons.redo),
      ),
      _divider(),
      TextButton.icon(onPressed: () => ink.drawing = false, icon: const Icon(Icons.check), label: const Text('Done')),
    ];

    return Material(
      color: Colors.white,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        // On a phone the tools wrap onto two rows so Undo and Done stay in reach.
        child: narrow
            ? Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: items)
            : Row(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }

  Widget _divider() => Container(
    width: 1,
    height: 24,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: const Color(0x22000000),
  );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Color',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? const Color(0xFF1F3A73) : const Color(0x33000000),
                width: selected ? 3 : 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SizeDot extends StatelessWidget {
  const _SizeDot({required this.dot, required this.selected, required this.tip, required this.onTap});
  final double dot;
  final bool selected;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? const Color(0xFFE3ECF8) : null),
          child: Container(
            width: math.max(dot, 4),
            height: math.max(dot, 4),
            decoration: const BoxDecoration(color: Color(0xFF333333), shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
