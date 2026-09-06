import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/role_pop_scope.dart';
import '../../widgets/responsive_layout.dart';
import '../../models/product.dart';
import '../../models/sale_model.dart';
import '../../models/system_models.dart';
import '../../services/product_service.dart';
import '../../services/sale_provider.dart';
import '../../services/system_provider.dart';
import '../../services/report_service.dart';
import '../../services/user_provider.dart';
import '../../services/menu_service.dart';

class ProductActivityReportScreen extends ConsumerStatefulWidget {
  const ProductActivityReportScreen({super.key});

  @override
  ConsumerState<ProductActivityReportScreen> createState() => _ProductActivityReportScreenState();
}

class _ProductActivityReportScreenState extends ConsumerState<ProductActivityReportScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  final Set<String> _selectedProductIds = {};
  bool _isExporting = false;

  final Map<String, List<StockHistory>> _stockHistoryCache = {};
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    _fetchStockHistories();
  }

  Future<void> _fetchStockHistories() async {
    setState(() => _isLoadingHistory = true);
    final products = ref.read(productsFutureProvider).value ?? [];
    for (var p in products) {
      try {
        final history = await ref.read(systemServiceProvider).getStockHistory(p.id);
        _stockHistoryCache[p.id] = history;
      } catch (e) {
        _stockHistoryCache[p.id] = [];
      }
    }
    if (mounted) {
      setState(() => _isLoadingHistory = false);
    }
  }

  void _applyQuickDatePreset(String preset) {
    final now = DateTime.now();
    setState(() {
      if (preset == 'Today') {
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = now;
      } else if (preset == 'This Week') {
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _endDate = now;
      } else if (preset == 'This Month') {
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
      } else if (preset == 'Last 30 Days') {
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
      }
    });
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  void _showProductFilterDialog(List<Product> products) {
    showDialog(
      context: context,
      builder: (context) {
        final tempSelected = Set<String>.from(_selectedProductIds);
        String dialogSearch = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = products.where((p) {
              return p.name.toLowerCase().contains(dialogSearch.toLowerCase()) ||
                     p.category.toLowerCase().contains(dialogSearch.toLowerCase());
            }).toList();

            final allSelected = tempSelected.isEmpty || tempSelected.length == products.length;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.filter_alt, color: Color(0xFF4A0808)),
                  SizedBox(width: 8),
                  Text('Select Products for Report'),
                ],
              ),
              content: SizedBox(
                width: 450,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search products...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDialogState(() => dialogSearch = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      title: const Text('ALL PRODUCTS', style: TextStyle(fontWeight: FontWeight.bold)),
                      value: allSelected,
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            tempSelected.clear();
                          } else {
                            tempSelected.clear();
                            for (var p in products) {
                              tempSelected.add(p.id);
                            }
                          }
                        });
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, idx) {
                          final p = filtered[idx];
                          final isChecked = tempSelected.contains(p.id) || (tempSelected.isEmpty);
                          return CheckboxListTile(
                            title: Text(p.name),
                            subtitle: Text('${p.category} | Stock: ${p.stockQuantity}${p.unit}'),
                            value: isChecked,
                            onChanged: (val) {
                              setDialogState(() {
                                if (tempSelected.isEmpty) {
                                  tempSelected.addAll(products.map((item) => item.id));
                                }
                                if (val == true) {
                                  tempSelected.add(p.id);
                                } else {
                                  tempSelected.remove(p.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedProductIds.clear();
                      if (tempSelected.length < products.length) {
                        _selectedProductIds.addAll(tempSelected);
                      }
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply Filter'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<ProductActivityReportData> _computeReportData(List<Product> products, List<SaleRecord> sales) {
    final startOfPeriod = DateTime(_startDate.year, _startDate.month, _startDate.day);
    final endOfPeriod = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 59, 59);

    final periodSales = sales.where((s) =>
        s.status == SaleStatus.completed &&
        s.timestamp.isAfter(startOfPeriod.subtract(const Duration(seconds: 1))) &&
        s.timestamp.isBefore(endOfPeriod.add(const Duration(seconds: 1)))
    ).toList();

    List<Product> targetProducts = products.where((p) => !p.isDeleted).toList();
    if (_selectedProductIds.isNotEmpty) {
      targetProducts = targetProducts.where((p) => _selectedProductIds.contains(p.id)).toList();
    }

    if (_selectedCategory != 'All') {
      targetProducts = targetProducts.where((p) => p.category == _selectedCategory).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      targetProducts = targetProducts.where((p) =>
        p.name.toLowerCase().contains(q) ||
        p.category.toLowerCase().contains(q)
      ).toList();
    }

    final List<ProductActivityReportData> reportList = [];

    for (var p in targetProducts) {
      // 1. Calculate Intake Data
      final histories = _stockHistoryCache[p.id] ?? [];
      final intakeEntries = histories.where((h) =>
          h.changeAmount > 0 &&
          h.timestamp.isAfter(startOfPeriod.subtract(const Duration(seconds: 1))) &&
          h.timestamp.isBefore(endOfPeriod.add(const Duration(seconds: 1)))
      ).toList();

      double totalIntakeQty = intakeEntries.fold(0.0, (sum, h) => sum + h.changeAmount);
      DateTime? lastIntakeDate;
      if (intakeEntries.isNotEmpty) {
        intakeEntries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        lastIntakeDate = intakeEntries.first.timestamp;
      } else if (p.lastStockUpdate != null &&
          p.lastStockUpdate!.isAfter(startOfPeriod.subtract(const Duration(seconds: 1))) &&
          p.lastStockUpdate!.isBefore(endOfPeriod.add(const Duration(seconds: 1)))) {
        lastIntakeDate = p.lastStockUpdate;
        if (p.dailyStockAdded > 0) {
          totalIntakeQty = p.dailyStockAdded;
        }
      }

      // 2. Calculate Sales & Revenue
      double totalQtySold = 0.0;
      double totalRevenue = 0.0;
      final List<Map<String, dynamic>> salesBreakdown = [];

      for (var sale in periodSales) {
        for (var item in sale.items) {
          if (item.product.id == p.id) {
            totalQtySold += item.quantity;
            totalRevenue += item.total;
            salesBreakdown.add({
              'sale_id': sale.id,
              'timestamp': sale.timestamp,
              'cashier_name': sale.cashierName,
              'customer_name': sale.customerName ?? 'Walk-in',
              'quantity': item.quantity,
              'price_at_sale': item.priceAtSale,
              'total': item.total,
            });
          }
        }
      }

      reportList.add(ProductActivityReportData(
        product: p,
        totalIntakeQty: totalIntakeQty,
        intakeEntries: intakeEntries,
        lastIntakeDate: lastIntakeDate,
        totalQtySold: totalQtySold,
        totalRevenue: totalRevenue,
        salesBreakdown: salesBreakdown,
        remainingStock: p.stockQuantity,
      ));
    }

    return reportList;
  }

  void _showProductDetailModal(ProductActivityReportData data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.analytics, color: Color(0xFF4A0808)),
              const SizedBox(width: 8),
              Expanded(child: Text('${data.product.name} Activity Details')),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _modalStat('Category', data.product.category),
                        _modalStat('Retail Price', '₵${data.product.retailPrice.toStringAsFixed(2)}'),
                        _modalStat('Remaining Stock', '${data.remainingStock.toStringAsFixed(1)} ${data.product.unit}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Intake / Restock Log (Within Selected Period)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  data.intakeEntries.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(data.lastIntakeDate != null
                              ? 'Last Stock Update recorded on ${DateFormat('MMM dd, yyyy HH:mm').format(data.lastIntakeDate!)}'
                              : 'No specific intake transactions logged in this date range.'),
                        )
                      : Table(
                          border: TableBorder.all(color: Colors.grey.shade300),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: Colors.grey.shade200),
                              children: const [
                                Padding(padding: EdgeInsets.all(6), child: Text('Date/Time', style: TextStyle(fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Quantity Added', style: TextStyle(fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                            ),
                            ...data.intakeEntries.map((h) => TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text(DateFormat('MMM dd, HH:mm').format(h.timestamp))),
                                Padding(padding: const EdgeInsets.all(6), child: Text('+${h.changeAmount}${data.product.unit}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                                Padding(padding: const EdgeInsets.all(6), child: Text(h.reason)),
                              ],
                            )),
                          ],
                        ),
                  const SizedBox(height: 20),
                  const Text('Sales Transactions (Within Selected Period)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  data.salesBreakdown.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6)),
                          child: const Text('No sales transactions for this product during this period.'),
                        )
                      : Table(
                          border: TableBorder.all(color: Colors.grey.shade300),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: Colors.grey.shade200),
                              children: const [
                                Padding(padding: EdgeInsets.all(6), child: Text('Date/Time', style: TextStyle(fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                                Padding(padding: EdgeInsets.all(6), child: Text('Amount (GHS)', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                            ),
                            ...data.salesBreakdown.map((s) => TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(6), child: Text(DateFormat('MMM dd, HH:mm').format(s['timestamp']))),
                                Padding(padding: const EdgeInsets.all(6), child: Text(s['customer_name'])),
                                Padding(padding: const EdgeInsets.all(6), child: Text('${s['quantity']}')),
                                Padding(padding: const EdgeInsets.all(6), child: Text('₵${(s['total'] as double).toStringAsFixed(2)}')),
                              ],
                            )),
                          ],
                        ),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _modalStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Future<void> _generatePdfReport(List<ProductActivityReportData> reportData) async {
    setState(() => _isExporting = true);
    try {
      final user = ref.read(currentUserProvider);
      await ReportService.generateProductActivityReport(
        reportData: reportData,
        startDate: _startDate,
        endDate: _endDate,
        branchName: user?.branchCode ?? 'Main Branch',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CEO Product Activity Report PDF generated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsFutureProvider);
    final salesHistory = ref.watch(saleHistoryProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/product-report';

    final products = productsAsync.value ?? [];
    final categories = ['All', ...{...products.map((p) => p.category)}];

    final reportData = _computeReportData(products, salesHistory);

    double intakesKg = 0.0, intakesUnits = 0.0;
    double soldKg = 0.0, soldUnits = 0.0;
    double stockKg = 0.0, stockUnits = 0.0;
    final totalRevenueGenerated = reportData.fold(0.0, (sum, d) => sum + d.totalRevenue);

    for (final d in reportData) {
      final u = d.product.unit.trim().toLowerCase();
      final isKg = u == 'kg' || u == 'kgs' || u == 'kilogram' || u == 'kilograms';
      if (isKg) {
        intakesKg += d.totalIntakeQty;
        soldKg += d.totalQtySold;
        stockKg += d.remainingStock;
      } else {
        intakesUnits += d.totalIntakeQty;
        soldUnits += d.totalQtySold;
        stockUnits += d.remainingStock;
      }
    }

    final intakesFormatted = _formatQtyKPI(intakesKg, intakesUnits);
    final soldFormatted = _formatQtyKPI(soldKg, soldUnits);
    final stockFormatted = _formatQtyKPI(stockKg, stockUnits);

    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'Product Activity & Inventory Report', showMenuButton: true),
        drawer: isDesktop
            ? null
            : Drawer(
                child: AppSidebar(
                  userId: user.id,
                  userName: user.name,
                  userRole: user.activePrimaryRole.name.toUpperCase(),
                  currentRoute: currentRoute,
                  items: ref.watch(menuItemsProvider),
                  onTap: (route) => MenuService.navigate(context, route, currentRoute),
                ),
              ),
        body: Row(
          children: [
            if (isDesktop)
              AppSidebar(
                userId: user.id,
                userName: user.name,
                userRole: user.activePrimaryRole.name.toUpperCase(),
                currentRoute: currentRoute,
                items: ref.watch(menuItemsProvider),
                onTap: (route) => MenuService.navigate(context, route, currentRoute),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Filter Header
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isMobile) ...[
                              const Row(
                                children: [
                                  Icon(Icons.assessment, color: Color(0xFF4A0808), size: 28),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'CEO Executive Product Activity Report',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isExporting ? null : () => _generatePdfReport(reportData),
                                  icon: _isExporting
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.picture_as_pdf),
                                  label: Text(_isExporting ? 'Generating PDF...' : 'EXPORT CEO REPORT (PDF)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4A0808),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  const Icon(Icons.assessment, color: Color(0xFF4A0808), size: 28),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'CEO Executive Product Activity Report',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _isExporting ? null : () => _generatePdfReport(reportData),
                                    icon: _isExporting
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.picture_as_pdf),
                                    label: Text(_isExporting ? 'Generating PDF...' : 'EXPORT CEO REPORT (PDF)'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4A0808),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // Date Presets
                                Wrap(
                                  spacing: 6,
                                  children: ['Today', 'This Week', 'This Month', 'Last 30 Days'].map((preset) {
                                    return ActionChip(
                                      label: Text(preset),
                                      backgroundColor: Colors.grey.shade100,
                                      onPressed: () => _applyQuickDatePreset(preset),
                                    );
                                  }).toList(),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _selectCustomDateRange,
                                  icon: const Icon(Icons.date_range, size: 18),
                                  label: Text(
                                    '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _showProductFilterDialog(products),
                                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                  label: Text(
                                    _selectedProductIds.isEmpty
                                        ? 'All Products (${products.length})'
                                        : '${_selectedProductIds.length} Products Selected',
                                  ),
                                ),
                                DropdownButton<String>(
                                  value: _selectedCategory,
                                  underline: Container(height: 1, color: Colors.grey),
                                  items: categories.map((cat) {
                                    return DropdownMenuItem(value: cat, child: Text('Category: $cat'));
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedCategory = val);
                                  },
                                ),
                                SizedBox(
                                  width: isMobile ? double.infinity : 200,
                                  child: TextField(
                                    decoration: const InputDecoration(
                                      hintText: 'Search product...',
                                      prefixIcon: Icon(Icons.search, size: 18),
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => setState(() => _searchQuery = val),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Executive Summary KPIs
                    GridView.count(
                      crossAxisCount: isDesktop ? 4 : 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: isDesktop ? 2.2 : 1.7,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _kpiCard(
                          'Total Product Intakes',
                          intakesFormatted.primaryValue,
                          Icons.add_business_rounded,
                          Colors.blue,
                          unit: intakesFormatted.primaryUnit,
                          secondaryValue: intakesFormatted.secondaryText,
                        ),
                        _kpiCard(
                          'Total Quantity Sold',
                          soldFormatted.primaryValue,
                          Icons.shopping_cart_checkout_rounded,
                          Colors.purple,
                          unit: soldFormatted.primaryUnit,
                          secondaryValue: soldFormatted.secondaryText,
                        ),
                        _kpiCard(
                          'Total Revenue Generated',
                          '₵${currencyFormat.format(totalRevenueGenerated)}',
                          Icons.monetization_on_rounded,
                          Colors.green,
                        ),
                        _kpiCard(
                          'Total Remaining Stock',
                          stockFormatted.primaryValue,
                          Icons.inventory_rounded,
                          Colors.orange,
                          unit: stockFormatted.primaryUnit,
                          secondaryValue: stockFormatted.secondaryText,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Product Report Table Card
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Product Breakdown (${reportData.length} items)',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                if (_isLoadingHistory)
                                  const Row(
                                    children: [
                                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                                      SizedBox(width: 8),
                                      Text('Syncing stock history...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            reportData.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(32),
                                    child: Center(child: Text('No products match your current filters.')),
                                  )
                                : SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(Color(0xFF4A0808).withValues(alpha: 0.1)),
                                      columns: const [
                                        DataColumn(label: Text('Product & Category', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Intaked Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Last Intake Date', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Qty Sold', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Revenue Generated', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Remaining Stock', style: TextStyle(fontWeight: FontWeight.bold))),
                                        DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                                      ],
                                      rows: reportData.map((d) {
                                        final isLow = d.remainingStock <= d.product.lowStockThreshold;
                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text(d.product.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  Text(d.product.category, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                d.totalIntakeQty > 0
                                                    ? '+${d.totalIntakeQty.toStringAsFixed(1)}${d.product.unit}'
                                                    : '0.0${d.product.unit}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: d.totalIntakeQty > 0 ? Colors.green : Colors.grey,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                d.lastIntakeDate != null
                                                    ? DateFormat('MMM dd, HH:mm').format(d.lastIntakeDate!)
                                                    : 'N/A',
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                '${d.totalQtySold.toStringAsFixed(1)}${d.product.unit}',
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            DataCell(
                                              Text(
                                                '₵${d.totalRevenue.toStringAsFixed(2)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                                              ),
                                            ),
                                            DataCell(
                                              Row(
                                                children: [
                                                  Text(
                                                    '${d.remainingStock.toStringAsFixed(1)}${d.product.unit}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: isLow ? Colors.red : Colors.black,
                                                    ),
                                                  ),
                                                  if (isLow) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.red.shade100,
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text('LOW', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            DataCell(
                                              IconButton(
                                                icon: Icon(Icons.remove_red_eye_outlined, color: Color(0xFF4A0808)),
                                                tooltip: 'View Details',
                                                onPressed: () => _showProductDetailModal(d),
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String primaryValue, String primaryUnit, String? secondaryText}) _formatQtyKPI(
    double qtyKg, 
    double qtyUnits,
  ) {
    if (qtyKg > 0 && qtyUnits > 0) {
      return (
        primaryValue: qtyKg.toStringAsFixed(1),
        primaryUnit: 'kg',
        secondaryText: '+ ${qtyUnits.toStringAsFixed(1)} units',
      );
    } else if (qtyKg > 0) {
      return (
        primaryValue: qtyKg.toStringAsFixed(1),
        primaryUnit: 'kg',
        secondaryText: null,
      );
    } else if (qtyUnits > 0) {
      return (
        primaryValue: qtyUnits.toStringAsFixed(1),
        primaryUnit: 'units',
        secondaryText: null,
      );
    } else {
      return (
        primaryValue: '0.0',
        primaryUnit: 'kg',
        secondaryText: null,
      );
    }
  }

  Widget _kpiCard(
    String title, 
    String value, 
    IconData icon, 
    Color color, {
    String? unit,
    String? secondaryValue,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                ),
                if (unit != null && unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    unit,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withValues(alpha: 0.8)),
                  ),
                ],
              ],
            ),
            if (secondaryValue != null && secondaryValue.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                secondaryValue,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
