import 'package:i_gen/models/product.dart';
import 'package:i_gen/sync/syncable.dart';

class InvoiceLine with Syncable {
  final int id;
  final int invoiceId;
  final Product product;
  final int amount;
  final double price;
  @override
  final String uuid;
  @override
  final int updatedAt;

  // For sync: store UUIDs of related entities
  final String? invoiceUuid;
  final String? productUuid;

  const InvoiceLine({
    this.id = -1,
    required this.invoiceId,
    required this.product,
    required this.amount,
    required this.price,
    this.uuid = '',
    this.updatedAt = 0,
    this.invoiceUuid,
    this.productUuid,
  });

  factory InvoiceLine.fromMap(Map<String, dynamic> map, Product product) {
    return InvoiceLine(
      id: map['_id'] as int? ?? -1,
      invoiceId: map['invoice_id'] as int? ?? -1,
      product: product,
      amount: map['amount'] as int? ?? 0,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      uuid: map['uuid'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? 0,
    );
  }

  @override
  Map<String, dynamic> toSyncJson() => {
    'uuid': uuid,
    'invoice_uuid': invoiceUuid ?? '',
    'product_uuid': productUuid ?? product.uuid,
    'amount': amount,
    'price': price,
    'updated_at': updatedAt,
  };

  factory InvoiceLine.fromSyncJson(Map<String, dynamic> json) {
    return InvoiceLine(
      id: -1,
      invoiceId: -1,
      product: Product(id: -1, model: '', name: ''), // Resolved during merge
      amount: json['amount'] as int,
      price: (json['price'] as num).toDouble(),
      uuid: json['uuid'] as String,
      updatedAt: json['updated_at'] as int,
      invoiceUuid: json['invoice_uuid'] as String?,
      productUuid: json['product_uuid'] as String?,
    );
  }

  InvoiceLine copyWith({
    int? id,
    int? invoiceId,
    Product? product,
    int? amount,
    double? price,
    String? uuid,
    int? updatedAt,
    String? invoiceUuid,
    String? productUuid,
  }) {
    return InvoiceLine(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      product: product ?? this.product,
      amount: amount ?? this.amount,
      price: price ?? this.price,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
      invoiceUuid: invoiceUuid ?? this.invoiceUuid,
      productUuid: productUuid ?? this.productUuid,
    );
  }
}
