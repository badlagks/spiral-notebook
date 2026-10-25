import 'dart:math';
import 'dart:ui' show Size;

final _rand = Random();

/// Short unique id, good enough for local-only data.
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

/// Pages are laid out in paper units and scaled to fit the screen, so
/// widgets keep their place on any device. The smallest sheet is A5-shaped.
const basePageWidth = 480.0;
const basePageHeight = 680.0;

/// The sheet's size right now. It starts at the A5 size and grows to the
/// screen's shape, so the notebook fills a tall phone or a wide laptop, and
/// it always grows to hold everything already on the pages.
double pageWidth = basePageWidth;
double pageHeight = basePageHeight;

/// How far right and down anything reaches on any page of [nb].
Size contentExtent(Notebook nb) {
  var right = 0.0, bottom = 0.0;
  for (final page in nb.sections.expand((s) => s.pages)) {
    for (final b in page.blocks) {
      if (!b.isPlaced) continue;
      right = max(right, b.x! + b.width + 16);
      bottom = max(bottom, b.y! + b.estimatedHeight + 40);
    }
    for (final stroke in page.strokes) {
      for (final p in stroke.points) {
        right = max(right, p.x + 16);
        bottom = max(bottom, p.y + 40);
      }
    }
  }
  return Size(right, bottom);
}

/// Sets [pageWidth] and [pageHeight] for a book shown in [area] (in screen
/// pixels): one page or two side by side with a [gutter] between, inside a
/// [frame] of cover all round. Only the side with room to spare grows, so
/// writing stays the same size on screen.
void fitPaper(Size area, {required bool spread, double gutter = 0, double frame = 0, Size content = Size.zero}) {
  if (area.width <= 0 || area.height <= 0) return;
  final pages = spread ? 2 : 1;
  final gap = spread ? gutter : 0.0;
  var w = basePageWidth, h = basePageHeight;
  final room = area.width / area.height;
  if (room > (pages * w + gap + frame) / (h + frame)) {
    w = (room * (h + frame) - frame - gap) / pages;
  } else {
    h = (pages * w + gap + frame) / room - frame;
  }
  pageWidth = max(w.clamp(basePageWidth, basePageWidth * 1.6), content.width);
  pageHeight = max(h.clamp(basePageHeight, basePageHeight * 1.8), content.height);
}

/// Paper styles a page can be printed on.
enum PaperStyle { ruled, grid, blank }

/// A colored tab down the edge of the notebook, holding its own pages.
class Section {
  Section({String? id, required this.name, required this.color, List<NotePage>? pages, this.lock})
    : id = id ?? newId(),
      pages = pages ?? [NotePage()];

  final String id;
  String name;
  int color; // ARGB
  final List<NotePage> pages;

  /// A hash of the section's PIN, or null when it isn't locked.
  String? lock;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    if (lock != null) 'lock': lock,
    'pages': pages.map((p) => p.toJson()).toList(),
  };

  factory Section.fromJson(Map<String, dynamic> j) => Section(
    id: j['id'] as String,
    name: j['name'] as String,
    color: j['color'] as int,
    lock: j['lock'] as String?,
    pages: (j['pages'] as List).map((p) => NotePage.fromJson(p as Map<String, dynamic>)).toList(),
  );
}

enum InkTool { pen, highlighter }

/// One point of a drawn line, in paper units, with pen pressure from 0 to 1.
class InkPoint {
  const InkPoint(this.x, this.y, [this.pressure = 0.5]);
  final double x;
  final double y;
  final double pressure;
}

/// One line drawn on the paper with a finger, mouse or pen.
class InkStroke {
  InkStroke({String? id, required this.tool, required this.color, required this.width, List<InkPoint>? points})
    : id = id ?? newId(),
      points = points ?? [];

  final String id;
  final InkTool tool;
  final int color;
  final double width;
  final List<InkPoint> points;

  static double _round(double v) => (v * 10).roundToDouble() / 10;

  /// Points are stored flat as x, y, pressure to keep notebooks small.
  Map<String, dynamic> toJson() => {
    'id': id,
    'tool': tool.name,
    'color': color,
    'width': width,
    'points': [
      for (final p in points) ...[_round(p.x), _round(p.y), (p.pressure * 100).roundToDouble() / 100],
    ],
  };

  factory InkStroke.fromJson(Map<String, dynamic> j) {
    final flat = (j['points'] as List).map((n) => (n as num).toDouble()).toList();
    return InkStroke(
      id: j['id'] as String,
      tool: InkTool.values.asNameMap()[j['tool']] ?? InkTool.pen,
      color: j['color'] as int,
      width: (j['width'] as num).toDouble(),
      points: [for (var i = 0; i + 2 < flat.length; i += 3) InkPoint(flat[i], flat[i + 1], flat[i + 2])],
    );
  }

  /// The same line moved by [dx], [dy] after scaling by [scale] around
  /// ([ox], [oy]), optionally in another [color].
  InkStroke transformed({double dx = 0, double dy = 0, double scale = 1, double ox = 0, double oy = 0, int? color}) =>
      InkStroke(
        id: id,
        tool: tool,
        color: color ?? this.color,
        width: width * scale,
        points: [
          for (final p in points) InkPoint(ox + (p.x - ox) * scale + dx, oy + (p.y - oy) * scale + dy, p.pressure),
        ],
      );

  /// Whether any part of the line passes within [radius] of [x], [y].
  bool passesNear(double x, double y, double radius) {
    final r = radius + width / 2;
    if (points.length == 1) {
      final p = points.first;
      return (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) <= r * r;
    }
    for (var i = 1; i < points.length; i++) {
      if (_segmentDistance(points[i - 1], points[i], x, y) <= r) return true;
    }
    return false;
  }

  static double _segmentDistance(InkPoint a, InkPoint b, double x, double y) {
    final dx = b.x - a.x, dy = b.y - a.y;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((x - a.x) * dx + (y - a.y) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final px = a.x + t * dx - x, py = a.y + t * dy - y;
    return sqrt(px * px + py * py);
  }
}

class NotePage {
  NotePage({
    String? id,
    this.title = '',
    this.paper = PaperStyle.ruled,
    List<Block>? blocks,
    List<InkStroke>? strokes,
    this.background,
    this.starred = false,
  }) : id = id ?? newId(),
       blocks = blocks ?? [],
       strokes = strokes ?? [];

  final String id;
  String title;
  PaperStyle paper;
  final List<Block> blocks;

  /// Drawing on the paper, oldest first. Drawn above the widgets.
  final List<InkStroke> strokes;

  /// A picture under everything on the page, such as a page of an imported PDF.
  String? background;

  /// Marked as a favourite, to find it quickly in the page overview.
  bool starred;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'paper': paper.name,
    'blocks': blocks.map((b) => b.toJson()).toList(),
    if (strokes.isNotEmpty) 'strokes': strokes.map((s) => s.toJson()).toList(),
    if (background != null) 'bg': background,
    if (starred) 'star': true,
  };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    paper: PaperStyle.values.asNameMap()[j['paper']] ?? PaperStyle.ruled,
    blocks: (j['blocks'] as List).map((b) => Block.fromJson(b as Map<String, dynamic>)).toList(),
    strokes: ((j['strokes'] as List?) ?? []).map((s) => InkStroke.fromJson(s as Map<String, dynamic>)).toList(),
    background: j['bg'] as String?,
    starred: j['star'] as bool? ?? false,
  );

  /// Gives blocks with no position (from older notebooks) a spot,
  /// stacked down the page below anything already placed.
  void placeUnplaced() {
    var cursor = 96.0;
    for (final b in blocks.where((b) => b.isPlaced)) {
      cursor = max(cursor, b.y! + b.estimatedHeight + 16);
    }
    for (final b in blocks.where((b) => !b.isPlaced)) {
      b
        ..x = 48
        ..y = cursor;
      cursor += b.estimatedHeight + 16;
    }
  }

  /// A free spot for a new block: the first gap down the page that fits,
  /// or a little cascade from the top if the page is full.
  void placeNew(Block block) {
    final h = block.estimatedHeight;
    final sorted = blocks.where((b) => b.isPlaced).toList()..sort((a, b) => a.y!.compareTo(b.y!));
    // The first free spot down the left side, then down the right side.
    for (final left in {48.0, max(48.0, pageWidth - block.width - 24)}) {
      var y = 96.0;
      for (final b in sorted) {
        final overlapsX = b.x! < left + block.width && b.x! + b.width > left;
        if (overlapsX && b.y! < y + h && b.y! + b.estimatedHeight > y) {
          y = b.y! + b.estimatedHeight + 16;
        }
      }
      if (y + h <= pageHeight - 30) {
        block
          ..x = left
          ..y = y;
        return;
      }
    }
    // A full page: put it on top, still all on the paper.
    final n = blocks.length % 6;
    block
      ..x = 60.0 + n * 18
      ..y = max(80.0, min(110.0 + n * 18, pageHeight - h - 30));
  }

  /// All the words on the page, for search.
  String get searchableText => [title, ...blocks.map((b) => b.searchableText)].join('\n');
}

/// Something placed on a page: handwriting, a sticky note, a checklist,
/// a spreadsheet or a calculator. It sits wherever it was dragged to.
sealed class Block {
  Block({String? id, this.x, this.y, double? width, this.angle = 0})
    : id = id ?? newId(),
      // ignore: prefer_initializing_formals
      _width = width;

  final String id;

  /// Top-left corner in paper units. Null until the block is first placed.
  double? x;
  double? y;
  double? _width;

  /// A slight tilt in degrees, so things look placed by hand.
  double angle;

  /// When to remind about this block, if ever.
  Reminder? reminder;

  double get defaultWidth;
  double get minWidth => 120;
  double get width => _width ?? defaultWidth;

  /// Roughly how tall the block draws, for finding free space.
  double get estimatedHeight => switch (this) {
    TextBlock(:final text, :final kind) => kind == TextKind.heading ? 44 : 28.0 * '\n'.allMatches(text).length + 32,
    StickyBlock() => width,
    ChecklistBlock(:final items) => 30.0 * items.length,
    SheetBlock(:final rows, :final naturalWidth) => (rows + 2) * 24 * width / naturalWidth,
    CalculatorBlock() => 330 * width / CalculatorBlock.naturalWidth,
    MediaBlock(:final aspect, :final todos) => (width - 16) / aspect + 70 + 30.0 * todos.items.length,
  };
  set width(double w) => _width = w;
  bool get isPlaced => x != null && y != null;

  Map<String, dynamic> toJson();
  String get searchableText;

  Map<String, dynamic> layoutJson() => {
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    if (_width != null) 'w': _width,
    if (angle != 0) 'angle': angle,
    if (reminder != null) 'remind': reminder!.toJson(),
  };

  void readLayout(Map<String, dynamic> j) {
    x = (j['x'] as num?)?.toDouble();
    y = (j['y'] as num?)?.toDouble();
    _width = (j['w'] as num?)?.toDouble();
    angle = (j['angle'] as num?)?.toDouble() ?? 0;
    final r = j['remind'];
    reminder = r is Map<String, dynamic> ? Reminder.fromJson(r) : null;
  }

  static Block fromJson(Map<String, dynamic> j) {
    final Block b = switch (j['type']) {
      'text' => TextBlock.fromJson(j),
      'sticky' => StickyBlock.fromJson(j),
      'checklist' => ChecklistBlock.fromJson(j),
      'sheet' => SheetBlock.fromJson(j),
      'calculator' => CalculatorBlock.fromJson(j),
      'media' => MediaBlock.fromJson(j),
      _ => TextBlock(text: ''),
    };
    return b..readLayout(j);
  }
}

/// A time to be reminded about a block, with a sound.
class Reminder {
  Reminder({required this.at, this.rang = false, this.calendarEventId});

  final DateTime at;

  /// True once it has gone off, so it rings only once.
  bool rang;

  /// The matching event in the phone's own calendar, if one was added.
  String? calendarEventId;

  /// A number for the device's alarm, the same every time for [blockId].
  static int alarmId(String blockId) {
    var h = 0x811c9dc5;
    for (final c in blockId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  Map<String, dynamic> toJson() => {
    'at': at.toUtc().toIso8601String(),
    if (rang) 'rang': true,
    if (calendarEventId != null) 'cal': calendarEventId,
  };

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
    at: DateTime.parse(j['at'] as String).toLocal(),
    rang: j['rang'] as bool? ?? false,
    calendarEventId: j['cal'] as String?,
  );
}

enum TextKind { heading, body }

/// Free handwriting. Lines starting with "- " render as an outline,
/// and extra leading spaces indent them further.
class TextBlock extends Block {
  TextBlock({
    super.id,
    super.x,
    super.y,
    super.width,
    this.text = '',
    this.kind = TextKind.body,
    this.highlight = false,
  });

  String text;
  TextKind kind;
  bool highlight;

  @override
  double get defaultWidth => highlight ? 200 : 300;

  @override
  Map<String, dynamic> toJson() => {
    ...layoutJson(),
    'type': 'text',
    'id': id,
    'text': text,
    'kind': kind.name,
    'highlight': highlight,
  };

  factory TextBlock.fromJson(Map<String, dynamic> j) => TextBlock(
    id: j['id'] as String,
    text: j['text'] as String? ?? '',
    kind: TextKind.values.asNameMap()[j['kind']] ?? TextKind.body,
    highlight: j['highlight'] as bool? ?? false,
  );

  @override
  String get searchableText => text;
}

/// A square paper note that sticks anywhere, slightly crooked.
class StickyBlock extends Block {
  StickyBlock({super.id, super.x, super.y, super.width, super.angle = -2, this.text = '', this.color = 0xFFFFF59D});

  String text;
  int color;

  @override
  double get defaultWidth => 170;

  @override
  Map<String, dynamic> toJson() => {...layoutJson(), 'type': 'sticky', 'id': id, 'text': text, 'color': color};

  factory StickyBlock.fromJson(Map<String, dynamic> j) =>
      StickyBlock(id: j['id'] as String, text: j['text'] as String? ?? '', color: j['color'] as int? ?? 0xFFFFF59D);

  @override
  String get searchableText => text;
}

class ChecklistItem {
  ChecklistItem({String? id, this.text = '', this.done = false}) : id = id ?? newId();
  final String id;
  String text;
  bool done;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
  factory ChecklistItem.fromJson(Map<String, dynamic> j) =>
      ChecklistItem(id: j['id'] as String, text: j['text'] as String? ?? '', done: j['done'] as bool? ?? false);
}

class ChecklistBlock extends Block {
  ChecklistBlock({super.id, super.x, super.y, super.width, List<ChecklistItem>? items})
    : items = items ?? [ChecklistItem()];

  final List<ChecklistItem> items;

  @override
  double get defaultWidth => 260;

  @override
  Map<String, dynamic> toJson() => {
    ...layoutJson(),
    'type': 'checklist',
    'id': id,
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory ChecklistBlock.fromJson(Map<String, dynamic> j) => ChecklistBlock(
    id: j['id'] as String,
    items: (j['items'] as List).map((i) => ChecklistItem.fromJson(i as Map<String, dynamic>)).toList(),
  );

  @override
  String get searchableText => items.map((i) => i.text).join('\n');
}

/// A small spreadsheet. Cells hold raw input; formulas start with "=".
class SheetBlock extends Block {
  SheetBlock({super.id, super.x, super.y, super.width, int rows = 6, int cols = 4, List<List<String>>? cells})
    : cells = cells ?? List.generate(rows, (_) => List.filled(cols, '', growable: true));

  final List<List<String>> cells;

  /// The spreadsheet's drawn size before it is scaled to [width].
  double get naturalWidth => 30 + 112 + (cols - 1) * 78;

  @override
  double get defaultWidth => naturalWidth;

  @override
  double get minWidth => 160;

  int get rows => cells.length;
  int get cols => cells.isEmpty ? 0 : cells.first.length;

  void addRow() => cells.add(List.filled(cols, '', growable: true));
  void addColumn() {
    for (final r in cells) {
      r.add('');
    }
  }

  void removeRow() {
    if (rows > 1) cells.removeLast();
  }

  void removeColumn() {
    if (cols > 1) {
      for (final r in cells) {
        r.removeLast();
      }
    }
  }

  @override
  Map<String, dynamic> toJson() => {...layoutJson(), 'type': 'sheet', 'id': id, 'cells': cells};

  factory SheetBlock.fromJson(Map<String, dynamic> j) => SheetBlock(
    id: j['id'] as String,
    cells: (j['cells'] as List).map((r) => (r as List).map((c) => c as String).toList()).toList(),
  );

  @override
  String get searchableText => cells.expand((r) => r).join(' ');
}

class CalculatorBlock extends Block {
  CalculatorBlock({super.id, super.x, super.y, super.width, this.display = '0', this.memory = 0});

  String display;
  double memory;

  /// The calculator's drawn width before it is scaled to [width].
  static const naturalWidth = 216.0;

  @override
  double get defaultWidth => 190;

  @override
  double get minWidth => 130;

  @override
  Map<String, dynamic> toJson() => {
    ...layoutJson(),
    'type': 'calculator',
    'id': id,
    'display': display,
    'memory': memory,
  };

  factory CalculatorBlock.fromJson(Map<String, dynamic> j) => CalculatorBlock(
    id: j['id'] as String,
    display: j['display'] as String? ?? '0',
    memory: (j['memory'] as num?)?.toDouble() ?? 0,
  );

  @override
  String get searchableText => display;
}

enum MediaKind { photo, video }

/// A photo or video in a small frame, with a note about it, where it was,
/// and things to do about it. The file itself is kept on the device by
/// [mediaId], outside the notebook's text so the notebook stays light.
class MediaBlock extends Block {
  MediaBlock({
    super.id,
    super.x,
    super.y,
    super.width,
    super.angle,
    required this.mediaId,
    this.kind = MediaKind.photo,
    this.aspect = 4 / 3,
    this.name = '',
    this.note = '',
    this.place = '',
    ChecklistBlock? todos,
  }) : todos = todos ?? ChecklistBlock(items: []);

  /// Media ids starting with this are drawn pictures used in previews.
  static const samplePrefix = 'sample:';

  final String mediaId;
  final MediaKind kind;

  /// Width divided by height of the photo or video.
  double aspect;
  final String name;
  String note;
  String place;

  /// To-dos about this photo or video.
  final ChecklistBlock todos;

  bool get isSample => mediaId.startsWith(samplePrefix);

  @override
  double get defaultWidth => 220;

  @override
  double get minWidth => 140;

  @override
  Map<String, dynamic> toJson() => {
    ...layoutJson(),
    'type': 'media',
    'id': id,
    'media': mediaId,
    'kind': kind.name,
    'aspect': aspect,
    if (name.isNotEmpty) 'name': name,
    if (note.isNotEmpty) 'note': note,
    if (place.isNotEmpty) 'place': place,
    if (todos.items.isNotEmpty) 'todos': todos.items.map((i) => i.toJson()).toList(),
  };

  factory MediaBlock.fromJson(Map<String, dynamic> j) => MediaBlock(
    id: j['id'] as String,
    mediaId: j['media'] as String,
    kind: MediaKind.values.asNameMap()[j['kind']] ?? MediaKind.photo,
    aspect: (j['aspect'] as num?)?.toDouble() ?? 4 / 3,
    name: j['name'] as String? ?? '',
    note: j['note'] as String? ?? '',
    place: j['place'] as String? ?? '',
    todos: ChecklistBlock(
      items: [for (final i in (j['todos'] as List? ?? const [])) ChecklistItem.fromJson(i as Map<String, dynamic>)],
    ),
  );

  @override
  String get searchableText => [name, note, place, todos.searchableText].join('\n');
}

/// A page that was torn out. It can be put back for [ArchivedPage.keepFor].
class ArchivedPage {
  ArchivedPage({
    required this.page,
    required this.sectionId,
    required this.sectionName,
    required this.sectionColor,
    required this.tornAt,
    this.sectionLock,
  });

  static const keepFor = Duration(days: 30);

  final NotePage page;
  final String sectionId;
  final String sectionName;
  final int sectionColor;
  final DateTime tornAt;

  /// The PIN hash of a locked section, so its torn-out pages stay hidden too.
  final String? sectionLock;

  DateTime get deleteAt => tornAt.add(keepFor);

  /// Whole days left before it is deleted for good, never below 0.
  int daysLeft(DateTime now) {
    final left = deleteAt.difference(now);
    return left.isNegative ? 0 : (left.inHours / 24).ceil();
  }

  Map<String, dynamic> toJson() => {
    'page': page.toJson(),
    'sectionId': sectionId,
    'sectionName': sectionName,
    'sectionColor': sectionColor,
    'tornAt': tornAt.toUtc().toIso8601String(),
    if (sectionLock != null) 'sectionLock': sectionLock,
  };

  factory ArchivedPage.fromJson(Map<String, dynamic> j) => ArchivedPage(
    page: NotePage.fromJson(j['page'] as Map<String, dynamic>),
    sectionId: j['sectionId'] as String,
    sectionName: j['sectionName'] as String,
    sectionColor: j['sectionColor'] as int,
    tornAt: DateTime.parse(j['tornAt'] as String),
    sectionLock: j['sectionLock'] as String?,
  );
}

/// How the app looks: a spiral notebook on a desk, or plain paper filling the screen.
enum Look { notebook, plain }

/// The colour of the paper.
enum PaperTone { cream, white }

class Notebook {
  Notebook({
    required this.title,
    required this.sections,
    List<ArchivedPage>? archive,
    this.look = Look.notebook,
    this.tone = PaperTone.cream,
    this.showPhoneCalendar = false,
  }) : archive = archive ?? [];

  String title;
  Look look;
  PaperTone tone;

  /// Whether the calendar also shows the phone's own events.
  bool showPhoneCalendar;
  final List<Section> sections;

  /// Torn-out pages, newest first.
  final List<ArchivedPage> archive;

  /// Every photo and video still used, including on torn-out pages.
  Set<String> get mediaIds => {
    for (final page in [...sections.expand((s) => s.pages), ...archive.map((a) => a.page)]) ...[
      ?page.background,
      for (final b in page.blocks)
        if (b is MediaBlock) b.mediaId,
    ],
  };

  Map<String, dynamic> toJson() => {
    'version': 2,
    'title': title,
    'look': look.name,
    'tone': tone.name,
    if (showPhoneCalendar) 'phoneCal': true,
    'sections': sections.map((s) => s.toJson()).toList(),
    'archive': archive.map((a) => a.toJson()).toList(),
  };

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
    title: j['title'] as String? ?? 'My Notebook',
    look: Look.values.asNameMap()[j['look']] ?? Look.notebook,
    tone: PaperTone.values.asNameMap()[j['tone']] ?? PaperTone.cream,
    showPhoneCalendar: j['phoneCal'] as bool? ?? false,
    sections: (j['sections'] as List).map((s) => Section.fromJson(s as Map<String, dynamic>)).toList(),
    archive: ((j['archive'] as List?) ?? []).map((a) => ArchivedPage.fromJson(a as Map<String, dynamic>)).toList(),
  );
}
