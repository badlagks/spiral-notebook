import 'dart:math';

final _rand = Random();

/// Short unique id, good enough for local-only data.
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

/// Paper styles a page can be printed on.
enum PaperStyle { ruled, grid, blank }

/// A colored tab down the edge of the notebook, holding its own pages.
class Section {
  Section({
    String? id,
    required this.name,
    required this.color,
    List<NotePage>? pages,
  })  : id = id ?? newId(),
        pages = pages ?? [NotePage()];

  final String id;
  String name;
  int color; // ARGB
  final List<NotePage> pages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as int,
        pages: (j['pages'] as List)
            .map((p) => NotePage.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

class NotePage {
  NotePage({
    String? id,
    this.title = '',
    this.paper = PaperStyle.ruled,
    List<Block>? blocks,
  })  : id = id ?? newId(),
        blocks = blocks ?? [];

  final String id;
  String title;
  PaperStyle paper;
  final List<Block> blocks;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'paper': paper.name,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory NotePage.fromJson(Map<String, dynamic> j) => NotePage(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        paper: PaperStyle.values.asNameMap()[j['paper']] ?? PaperStyle.ruled,
        blocks: (j['blocks'] as List)
            .map((b) => Block.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  /// All the words on the page, for search.
  String get searchableText =>
      [title, ...blocks.map((b) => b.searchableText)].join('\n');
}

/// Something placed on a page: handwriting, a checklist, a spreadsheet or a calculator.
sealed class Block {
  Block({String? id}) : id = id ?? newId();
  final String id;

  Map<String, dynamic> toJson();
  String get searchableText;

  static Block fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'text' => TextBlock.fromJson(j),
        'checklist' => ChecklistBlock.fromJson(j),
        'sheet' => SheetBlock.fromJson(j),
        'calculator' => CalculatorBlock.fromJson(j),
        _ => TextBlock(text: ''),
      };
}

enum TextKind { heading, body }

/// Free handwriting. Lines starting with "- " render as an outline,
/// and extra leading spaces indent them further.
class TextBlock extends Block {
  TextBlock({super.id, this.text = '', this.kind = TextKind.body, this.highlight = false});

  String text;
  TextKind kind;
  bool highlight;

  @override
  Map<String, dynamic> toJson() => {
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

class ChecklistItem {
  ChecklistItem({String? id, this.text = '', this.done = false}) : id = id ?? newId();
  final String id;
  String text;
  bool done;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        text: j['text'] as String? ?? '',
        done: j['done'] as bool? ?? false,
      );
}

class ChecklistBlock extends Block {
  ChecklistBlock({super.id, List<ChecklistItem>? items})
      : items = items ?? [ChecklistItem()];

  final List<ChecklistItem> items;

  @override
  Map<String, dynamic> toJson() => {
        'type': 'checklist',
        'id': id,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory ChecklistBlock.fromJson(Map<String, dynamic> j) => ChecklistBlock(
        id: j['id'] as String,
        items: (j['items'] as List)
            .map((i) => ChecklistItem.fromJson(i as Map<String, dynamic>))
            .toList(),
      );

  @override
  String get searchableText => items.map((i) => i.text).join('\n');
}

/// A small spreadsheet. Cells hold raw input; formulas start with "=".
class SheetBlock extends Block {
  SheetBlock({super.id, int rows = 6, int cols = 4, List<List<String>>? cells})
      : cells = cells ??
            List.generate(rows, (_) => List.filled(cols, '', growable: true));

  final List<List<String>> cells;

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
  Map<String, dynamic> toJson() => {'type': 'sheet', 'id': id, 'cells': cells};

  factory SheetBlock.fromJson(Map<String, dynamic> j) => SheetBlock(
        id: j['id'] as String,
        cells: (j['cells'] as List)
            .map((r) => (r as List).map((c) => c as String).toList())
            .toList(),
      );

  @override
  String get searchableText => cells.expand((r) => r).join(' ');
}

class CalculatorBlock extends Block {
  CalculatorBlock({super.id, this.display = '0', this.memory = 0});

  String display;
  double memory;

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'calculator', 'id': id, 'display': display, 'memory': memory};

  factory CalculatorBlock.fromJson(Map<String, dynamic> j) => CalculatorBlock(
        id: j['id'] as String,
        display: j['display'] as String? ?? '0',
        memory: (j['memory'] as num?)?.toDouble() ?? 0,
      );

  @override
  String get searchableText => display;
}

class Notebook {
  Notebook({required this.title, required this.sections});

  String title;
  final List<Section> sections;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'title': title,
        'sections': sections.map((s) => s.toJson()).toList(),
      };

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
        title: j['title'] as String? ?? 'My Notebook',
        sections: (j['sections'] as List)
            .map((s) => Section.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
