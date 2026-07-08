class CustomerMetric {
  final String customerPhone;
  final double totalSpend;
  final double totalDebt;
  final int visitCount;
  final double averageOrderValue;
  final DateTime? lastVisit;
  final List<double> recentSpends;

  CustomerMetric({
    required this.customerPhone,
    required this.totalSpend,
    required this.totalDebt,
    required this.visitCount,
    required this.averageOrderValue,
    this.lastVisit,
    this.recentSpends = const [],
  });

  String get performanceLabel {
    if (totalSpend > 500) return 'VIP';
    if (visitCount > 5) return 'Regular';
    return 'Occasional';
  }
}
