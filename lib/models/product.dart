import 'package:i_gen/sync/syncable.dart';

class Product with Syncable {
  final int id;
  final String model;
  final String name;
  @override
  final String uuid;
  @override
  final int updatedAt;

  const Product({
    required this.id,
    required this.model,
    required this.name,
    this.uuid = '',
    this.updatedAt = 0,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['_id'] as int? ?? -1,
      model: map['model'] as String? ?? '',
      name: map['name'] as String? ?? '',
      uuid: map['uuid'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    '_id': id,
    'model': model,
    'name': name,
    'uuid': uuid,
    'updated_at': updatedAt,
  };

  @override
  Map<String, dynamic> toSyncJson() => {
    'uuid': uuid,
    'model': model,
    'name': name,
    'updated_at': updatedAt,
  };

  factory Product.fromSyncJson(Map<String, dynamic> json) {
    return Product(
      id: -1, // Will be assigned locally
      model: json['model'] as String,
      name: json['name'] as String,
      uuid: json['uuid'] as String,
      updatedAt: json['updated_at'] as int,
    );
  }

  Product copyWith({
    int? id,
    String? model,
    String? name,
    String? uuid,
    int? updatedAt,
  }) {
    return Product(
      id: id ?? this.id,
      model: model ?? this.model,
      name: name ?? this.name,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
