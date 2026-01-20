import 'package:i_gen/models/invoice_line.dart';

class Invoice {
  final int id;
  final String customerName;
  final DateTime date;
  final double total;
  final List<InvoiceLine> lines;
  final String currency;
  final double discount;

  const Invoice({
    required this.id,
    required this.customerName,
    required this.date,
    required this.total,
    required this.currency,
    this.discount = 0,
    this.lines = const [],
  });
  static Invoice? fromMap(Map<String, dynamic> map) {
    if (map case {
      '_id': int id,
      'customer': String customerName,
      'date': String date,
      'total': double total,
      'discount': double discount,
      'currency': String currency,
    }) {
      return Invoice(
        id: id,
        customerName: customerName,
        date: DateTime.parse(date),
        total: total,
        discount: discount,
        currency: currency,
        lines: [],
      );
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer': customerName,
      'date': date.toIso8601String(),
      'total': total,
      'lines': lines.map((e) => e.toMap()).toList(),
    };
  }

  Invoice copyWith({
    int? id,
    String? customerName,
    String? currency,
    DateTime? date,
    double? total,
    double? discount,
    List<InvoiceLine>? lines,
  }) {
    return Invoice(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      currency: currency ?? this.currency,
      date: date ?? this.date,
      total: total ?? this.total,
      lines: lines ?? this.lines,
      discount: discount ?? this.discount,
    );
  }
}
