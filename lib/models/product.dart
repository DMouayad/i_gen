class Product {
  final int id;
  final String model;
  final String name;

  Product({required this.id, required this.model, required this.name});
  static Product? fromMap(Map<String, dynamic> map) {
    if (map case {'id': int id, 'model': String model, 'name': String name}) {
      return Product(id: id, model: model, name: name);
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'model': model, 'name': name};
  }

  Product copyWith({int? id, String? model, String? name}) {
    return Product(
      id: id ?? this.id,
      model: model ?? this.model,
      name: name ?? this.name,
    );
  }
}
