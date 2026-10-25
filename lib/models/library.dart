/// One notebook on the shelf, as the shelf shows it without opening it.
class ShelfEntry {
  ShelfEntry({required this.id, required this.title, required this.cover, required this.updated, this.deletedAt});

  final String id;
  String title;
  int cover;
  DateTime updated;

  /// Set when the notebook was deleted. It can be brought back for 30 days.
  DateTime? deletedAt;

  static const keepDeletedFor = Duration(days: 30);

  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'cover': cover,
    'updated': updated.toUtc().toIso8601String(),
    if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
  };

  factory ShelfEntry.fromJson(Map<String, dynamic> j) => ShelfEntry(
    id: j['id'] as String,
    title: j['title'] as String? ?? 'Notebook',
    cover: j['cover'] as int? ?? 0xFF7A5A3A,
    updated: DateTime.tryParse(j['updated'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    deletedAt: DateTime.tryParse(j['deletedAt'] as String? ?? '')?.toLocal(),
  );
}

/// Every notebook on this device, and which one is open.
class Shelf {
  Shelf({required this.entries, required this.openId});

  final List<ShelfEntry> entries;
  String openId;

  List<ShelfEntry> get notebooks => [for (final e in entries) if (!e.deleted) e];
  List<ShelfEntry> get recentlyDeleted => [for (final e in entries) if (e.deleted) e];

  ShelfEntry? find(String id) => entries.where((e) => e.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'open': openId,
    'notebooks': entries.map((e) => e.toJson()).toList(),
  };

  factory Shelf.fromJson(Map<String, dynamic> j) => Shelf(
    entries: [for (final e in j['notebooks'] as List) ShelfEntry.fromJson(e as Map<String, dynamic>)],
    openId: j['open'] as String,
  );
}
