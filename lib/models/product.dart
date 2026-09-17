import 'dart:convert';

/// Canonical display/sort order for product sizes. Unknown labels (typos,
/// future additions pulled from the server) sort after these, alphabetically.
const kSizeOrder = ['3XS', '2XS', 'XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'];

class Product {
  final int id;
  final String model;
  final String name;

  /// Sorted by [kSizeOrder]; empty means sizeless.
  final List<String> sizes;

  const Product({
    required this.id,
    required this.model,
    required this.name,
    this.sizes = const [],
  });

  /// More than one size → tapping the tile opens the size picker.
  bool get hasSizes => sizes.length > 1;

  /// Exactly one size → auto-selected, no picker needed.
  String? get singleSize => sizes.length == 1 ? sizes.single : null;

  /// Canonical order: known labels by [kSizeOrder], unknowns last
  /// (alphabetical tiebreak keeps the order deterministic across devices).
  /// Returns a new list; the input is never mutated.
  static List<String> sortSizes(List<String> sizes) {
    int rank(String s) {
      final i = kSizeOrder.indexOf(s);
      return i < 0 ? kSizeOrder.length : i;
    }

    return [...sizes]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  }

  /// Reads the DB/JSON/sync form: a JSON array string (the column format),
  /// a plain list (nested maps via [toMap]), or missing/corrupt → `[]`.
  /// Always sorted, so the invariant holds no matter the entry point.
  static List<String> parseSizes(Object? raw) {
    if (raw is List) return sortSizes(raw.whereType<String>().toList());
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return sortSizes(decoded.whereType<String>().toList());
        }
      } catch (_) {}
    }
    return const [];
  }

  /// Parses free-text size input (`S, M, L`): splits on commas,
  /// semicolons, or whitespace, drops empties, returns sorted.
  static List<String> parseSizeList(String raw) => sortSizes(
    raw
        .split(RegExp(r'[,;\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(),
  );

  /// The column/wire form: sorted JSON array (`[]` when sizeless).
  static String encodeSizes(List<String> sizes) => jsonEncode(sortSizes(sizes));

  static Product? fromMap(Map<String, dynamic> map) {
    if (map case {'id': int id, 'model': String model, 'name': String name}) {
      return Product(
        id: id,
        model: model,
        name: name,
        sizes: parseSizes(map['sizes']),
      );
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'model': model, 'name': name, 'sizes': sizes};
  }

  Product copyWith({
    int? id,
    String? model,
    String? name,
    List<String>? sizes,
  }) {
    return Product(
      id: id ?? this.id,
      model: model ?? this.model,
      name: name ?? this.name,
      sizes: sizes ?? this.sizes,
    );
  }
}
