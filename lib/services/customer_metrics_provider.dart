import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/customer_metrics.dart';
import 'customer_provider.dart';
import 'sale_provider.dart';

final customerMetricsProvider = Provider<Map<String, CustomerMetric>>((ref) {
  final customers = ref.watch(customerProvider);
  final sales = ref.watch(saleHistoryProvider);

  final Map<String, CustomerMetric> metrics = {};

  for (final customer in customers) {
    final customerSales = sales
        .where((s) => s.customerPhone == customer.phone)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (customerSales.isEmpty) {
      metrics[customer.phone] = CustomerMetric(
        customerPhone: customer.phone,
        totalSpend: 0,
        totalDebt: 0,
        visitCount: 0,
        averageOrderValue: 0,
        recentSpends: [],
      );
      continue;
    }

    final totalSpend = customerSales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final totalDebt = customerSales.fold(0.0, (sum, s) => sum + (s.isActive ? s.balance : 0));
    final visitCount = customerSales.length;
    final lastVisit = customerSales.last.timestamp;
    final recentSpends = customerSales.map((s) => s.totalAmount).toList();

    metrics[customer.phone] = CustomerMetric(
      customerPhone: customer.phone,
      totalSpend: totalSpend,
      totalDebt: totalDebt,
      visitCount: visitCount,
      averageOrderValue: totalSpend / visitCount,
      lastVisit: lastVisit,
      recentSpends: recentSpends,
    );
  }

  return metrics;
});
