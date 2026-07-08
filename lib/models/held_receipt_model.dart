import 'sale_model.dart';

class HeldReceipt {
  final String id;
  final List<SaleItem> items;
  final String? customerName;
  final String? customerPhone;
  final double totalAmount;
  final double totalDiscount;
  final String? appliedPromo;
  final DateTime timestamp;

  HeldReceipt({
    required this.id,
    required this.items,
    this.customerName,
    this.customerPhone,
    required this.totalAmount,
    required this.totalDiscount,
    this.appliedPromo,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items.map((e) => e.toJson()).toList(),
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'total_amount': totalAmount,
    'total_discount': totalDiscount,
    'applied_promo': appliedPromo,
    'timestamp': timestamp.toIso8601String(),
  };

  factory HeldReceipt.fromJson(Map<String, dynamic> json) => HeldReceipt(
    id: json['id'],
    items: (json['items'] as List).map((e) => SaleItem.fromJson(e)).toList(),
    customerName: json['customer_name'],
    customerPhone: json['customer_phone'],
    totalAmount: (json['total_amount'] as num).toDouble(),
    totalDiscount: (json['total_discount'] as num).toDouble(),
    appliedPromo: json['applied_promo'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}
