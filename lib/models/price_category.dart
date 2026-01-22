// lib/models/price_category.dart

import 'package:i_gen/sync/syncable.dart';

class PriceCategory with Syncable {
  final int id;
  final String name;
  final String currency;
  @override
  final String uuid;
  @override
  final int updatedAt;

  PriceCategory({
    required this.id,
    required this.name,
    required this.currency,
    this.uuid = '',
    this.updatedAt = 0,
  });

  static PriceCategory? fromMap(Map<String, dynamic> map) {
    if (map case {
      '_id': int id,
      'name': String name,
      'currency': String currency,
    }) {
      return PriceCategory(
        id: id,
        name: name,
        currency: currency,
        uuid: map['uuid'] as String? ?? '',
        updatedAt: map['updated_at'] as int? ?? 0,
      );
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
      'currency': currency,
      'uuid': uuid,
      'updated_at': updatedAt,
    };
  }

  @override
  Map<String, dynamic> toSyncJson() => {
    'uuid': uuid,
    'name': name,
    'currency': currency,
    'updated_at': updatedAt,
  };

  factory PriceCategory.fromSyncJson(Map<String, dynamic> json) {
    return PriceCategory(
      id: -1,
      name: json['name'] as String,
      currency: json['currency'] as String,
      uuid: json['uuid'] as String,
      updatedAt: json['updated_at'] as int,
    );
  }

  PriceCategory copyWith({
    int? id,
    String? name,
    String? currency,
    String? uuid,
    int? updatedAt,
  }) {
    return PriceCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
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
