// lib/models/invoice.dart

import 'package:i_gen/models/invoice_line.dart';
import 'package:i_gen/sync/syncable.dart';

class Invoice with Syncable {
  final int id;
  final String customerName;
  final DateTime date;
  final double total;
  final String currency;
  final double discount;
  final List<InvoiceLine> lines;
  @override
  final String uuid;
  @override
  final int updatedAt;

  const Invoice({
    required this.id,
    required this.customerName,
    required this.date,
    required this.total,
    required this.currency,
    this.discount = 0,
    this.lines = const [],
    this.uuid = '',
    this.updatedAt = 0,
  });

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['_id'] as int? ?? -1,
      customerName: map['customer'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      total: (map['total'] as num?)?.toDouble() ?? 0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0,
      currency: map['currency'] as String? ?? 'USD',
      uuid: map['uuid'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? 0,
      lines: [],
    );
  }

  @override
  Map<String, dynamic> toSyncJson() => {
    'uuid': uuid,
    'customer': customerName,
    'date': date.toIso8601String(),
    'total': total,
    'currency': currency,
    'discount': discount,
    'updated_at': updatedAt,
    'lines': lines.map((l) => l.toSyncJson()).toList(),
  };

  factory Invoice.fromSyncJson(Map<String, dynamic> json) {
    return Invoice(
      id: -1,
      customerName: json['customer'] as String,
      date: DateTime.parse(json['date'] as String),
      total: (json['total'] as num).toDouble(),
      currency: json['currency'] as String,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      uuid: json['uuid'] as String,
      updatedAt: json['updated_at'] as int,
      lines:
          (json['lines'] as List<dynamic>?)
              ?.map((l) => InvoiceLine.fromSyncJson(l as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Invoice copyWith({
    int? id,
    String? customerName,
    DateTime? date,
    double? total,
    String? currency,
    double? discount,
    List<InvoiceLine>? lines,
    String? uuid,
    int? updatedAt,
  }) {
    return Invoice(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      date: date ?? this.date,
      total: total ?? this.total,
      currency: currency ?? this.currency,
      discount: discount ?? this.discount,
      lines: lines ?? this.lines,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
