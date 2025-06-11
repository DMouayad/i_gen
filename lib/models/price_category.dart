class PriceCategory {
  final int id;
  final String name;
  final String currency;

  PriceCategory({required this.id, required this.name, required this.currency});

  static PriceCategory? fromMap(Map<String, dynamic> map) {
    if (map case {
      '_id': int id,
      'name': String name,
      'currency': String currency,
    }) {
      return PriceCategory(id: id, name: name, currency: currency);
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'currency': currency};
  }

  PriceCategory copyWith({int? id, String? name, String? currency}) {
    return PriceCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PriceCategory &&
        other.currency == currency &&
        other.name == name &&
        other.id == id;
  }

  @override
  int get hashCode => currency.hashCode ^ id.hashCode ^ name.hashCode;
}
