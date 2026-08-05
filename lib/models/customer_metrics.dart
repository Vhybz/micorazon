class CustomerMetric {
  final String customerPhone;
  final double totalSpend;
  final double totalDebt;
  final int visitCount;
  final double averageOrderValue;
  final DateTime? lastVisit;
  final List<double> recentSpends;
  final bool isFavorite;
  final bool isBulkPurchaser;

  CustomerMetric({
    required this.customerPhone,
    required this.totalSpend,
    required this.totalDebt,
    required this.visitCount,
    required this.averageOrderValue,
    this.lastVisit,
    this.recentSpends = const [],
    this.isFavorite = false,
    this.isBulkPurchaser = false,
  });

  String get performanceLabel {
    if (isBulkPurchaser) return 'Bulk Buyer';
    if (isFavorite || totalSpend > 500) return 'VIP';
    if (visitCount > 5) return 'Regular';
    return 'Occasional';
  }
}
