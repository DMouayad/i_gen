// Read-only view models for the shared orders domain (Phase 10).
// This app never writes orders — the web app does — so there are no
// toMap/save paths here, only parsing of live server reads.

class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.amount,
    required this.price,
  });

  static OrderItem? fromMap(Map<String, dynamic> map) {
    if (map case {
      'id': String id,
      'order_id': String orderId,
      'amount': int amount,
      'price': num price,
    }) {
      return OrderItem(
        id: id,
        orderId: orderId,
        productId: map['product_id']?.toString(),
        amount: amount,
        price: price.toDouble(),
      );
    }
    return null;
  }

  final String id;
  final String orderId;
  final String? productId;
  final int amount;
  final double price;
}

class Order {
  const Order({
    required this.id,
    required this.distributorId,
    required this.status,
    required this.total,
    required this.currency,
    required this.createdAt,
    this.items = const [],
  });

  static Order? fromMap(
    Map<String, dynamic> map, {
    List<OrderItem> items = const [],
  }) {
    if (map case {
      'id': String id,
      'distributor_id': String distributorId,
      'status': String status,
      'total': num total,
      'currency': String currency,
    }) {
      return Order(
        id: id,
        distributorId: distributorId,
        status: status,
        total: total.toDouble(),
        currency: currency,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
        items: items,
      );
    }
    return null;
  }

  final String id;
  final String distributorId;
  final String status;
  final double total;
  final String currency;
  final DateTime? createdAt;
  final List<OrderItem> items;
}

/// Narrow distributor projection for the staff directory (names + phone +
/// order linkage only — no credential details).
class Distributor {
  const Distributor({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.phone,
  });

  static Distributor? fromMap(Map<String, dynamic> map) {
    if (map case {
      'id': String id,
      'name_ar': String nameAr,
      'name_en': String nameEn,
      'phone': String phone,
    }) {
      return Distributor(id: id, nameAr: nameAr, nameEn: nameEn, phone: phone);
    }
    return null;
  }

  final String id;
  final String nameAr;
  final String nameEn;
  final String phone;
}
