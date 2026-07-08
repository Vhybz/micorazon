import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/sale_provider.dart';
import '../../services/expense_provider.dart';
import '../../models/sale_model.dart';
import '../../models/user_model.dart';
import '../../services/receipt_service.dart';
import '../../services/notification_service.dart';
import '../../core/utils.dart';
import 'package:intl/intl.dart';

import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';

class SalesReportsScreen extends ConsumerStatefulWidget {
  const SalesReportsScreen({super.key});

  @override
  ConsumerState<SalesReportsScreen> createState() => _SalesReportsScreenState();
}

class _SalesReportsScreenState extends ConsumerState<SalesReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  SaleStatus? _statusFilter;
  final Set<String> _selectedSaleIds = {};
  bool _isPrintingSelected = false;
  bool _isDeletingSelected = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final salesHistory = ref.watch(saleHistoryProvider);
    
    final isCashier = user.activePrimaryRole == UserRole.cashier;
    final now = DateTime.now();

    final filteredSales = salesHistory.where((sale) {
      final matchesSearch = sale.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                           sale.cashierName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                           (sale.customerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
                           sale.items.any((item) => 
                             item.product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                             item.product.category.toLowerCase().contains(_searchQuery.toLowerCase())
                           );

      final matchesStatus = _statusFilter == null || sale.status == _statusFilter;
      
      final effectiveStart = (isCashier && _startDate == null) ? DateTime(now.year, now.month, now.day) : _startDate;
      final effectiveEnd = (isCashier && _endDate == null) ? now : _endDate;

      final matchesDate = (effectiveStart == null || sale.timestamp.isAfter(effectiveStart)) &&
                         (effectiveEnd == null || sale.timestamp.isBefore(effectiveEnd.add(const Duration(days: 1))));
      
      return matchesSearch && matchesStatus && matchesDate;
    }).toList();

    final expensesState = ref.watch(expenseProvider);
    final filteredExpenses = expensesState.records.where((e) {
      final matchesDate = (_startDate == null || e.date.isAfter(_startDate!)) &&
                         (_endDate == null || e.date.isBefore(_endDate!.add(const Duration(days: 1))));
      return matchesDate;
    }).toList();
    final totalExpenses = filteredExpenses.fold(0.0, (sum, e) => sum + e.amount);

    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/sales';

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'Sales & Analytics', showMenuButton: true),
        drawer: isDesktop
            ? null
            : Drawer(
                child: AppSidebar(
                  userId: user.id,
                  userName: user.name,
                  userRole: user.activePrimaryRole.name.toUpperCase(),
                  currentRoute: currentRoute,
                  items: MenuService.getMenuItemsForUser(user),
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
                items: MenuService.getMenuItemsForUser(user),
                onTap: (route) => MenuService.navigate(context, route, currentRoute),
              ),
            Expanded(
              child: Column(
                children: [
                  Container(
                    color: theme.cardTheme.color,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: !isDesktop,
                      tabAlignment: !isDesktop ? TabAlignment.start : null,
                      labelColor: theme.colorScheme.primary,
                      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                      indicatorColor: theme.colorScheme.primary,
                      tabs: [
                        Tab(
                          text: isDesktop ? 'Analytics Overview' : 'Analytics', 
                          icon: const Icon(Icons.analytics_outlined)
                        ),
                        Tab(
                          text: isDesktop ? 'Transaction Logs' : 'Logs', 
                          icon: const Icon(Icons.list_alt_rounded)
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAnalyticsTab(context, filteredSales, totalExpenses),
                        _buildLogsTab(context, filteredSales, totalExpenses),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab(BuildContext context, List<SaleRecord> sales, double totalExpenses) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(context, sales, totalExpenses),
          const SizedBox(height: AppSpacing.xl),
          if (sales.isNotEmpty) ...[
            _buildChartsRow(context, sales),
            const SizedBox(height: AppSpacing.xl),
            _buildTopPerformanceRow(context, sales),
          ] else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('No data available for the selected period.'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogsTab(BuildContext context, List<SaleRecord> sales, double totalExpenses) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, sales, totalExpenses),
          const SizedBox(height: AppSpacing.xl),
          _buildFilters(),
          const SizedBox(height: AppSpacing.l),
          _buildSalesTable(sales),
        ],
      ),
    );
  }

  Widget _buildChartsRow(BuildContext context, List<SaleRecord> sales) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 900;
      if (isMobile) {
        return Column(
          children: [
            _buildRevenueTrendCard(context, sales),
            const SizedBox(height: AppSpacing.l),
            _buildCategoryDistributionCard(context, sales),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: _buildRevenueTrendCard(context, sales)),
          const SizedBox(width: AppSpacing.l),
          Expanded(flex: 1, child: _buildCategoryDistributionCard(context, sales)),
        ],
      );
    });
  }

  Widget _buildTopPerformanceRow(BuildContext context, List<SaleRecord> sales) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 900;
      if (isMobile) {
        return Column(
          children: [
            _buildTopProductsCard(context, sales),
            const SizedBox(height: AppSpacing.l),
            _buildStaffPerformanceCard(context, sales),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildTopProductsCard(context, sales)),
          const SizedBox(width: AppSpacing.l),
          Expanded(child: _buildStaffPerformanceCard(context, sales)),
        ],
      );
    });
  }

  Widget _buildRevenueTrendCard(BuildContext context, List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Group revenue by date
    final dailyRevenue = <DateTime, double>{};
    for (final sale in sales) {
      if (sale.status == SaleStatus.cancelled) continue;
      final date = DateTime(sale.timestamp.year, sale.timestamp.month, sale.timestamp.day);
      dailyRevenue[date] = (dailyRevenue[date] ?? 0.0) + sale.totalAmount;
    }

    final sortedDates = dailyRevenue.keys.toList()..sort();
    if (sortedDates.isEmpty) return const SizedBox.shrink();

    final spots = sortedDates.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), dailyRevenue[e.value]!);
    }).toList();

    return Container(
      height: 350,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revenue Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        final index = val.toInt();
                        if (index % (spots.length > 5 ? (spots.length / 5).ceil() : 1) != 0) return const SizedBox.shrink();
                        if (index >= 0 && index < sortedDates.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(DateFormat('MM/dd').format(sortedDates[index]), style: const TextStyle(fontSize: 10)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: theme.colorScheme.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDistributionCard(BuildContext context, List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final categoryTotals = <String, double>{};
    for (final sale in sales) {
      if (sale.status == SaleStatus.cancelled) continue;
      for (final item in sale.items) {
        categoryTotals[item.product.category] = (categoryTotals[item.product.category] ?? 0.0) + item.total;
      }
    }

    final sections = categoryTotals.entries.map((e) {
      final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal];
      final index = categoryTotals.keys.toList().indexOf(e.key);
      return PieChartSectionData(
        color: colors[index % colors.length],
        value: e.value,
        title: '${(e.value / categoryTotals.values.fold(0.0, (a, b) => a + b) * 100).toStringAsFixed(0)}%',
        radius: 50,
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return Container(
      height: 350,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category Mix', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
          Expanded(
            child: PieChart(
              PieChartData(
                sections: sections,
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: categoryTotals.keys.map((cat) {
              final index = categoryTotals.keys.toList().indexOf(cat);
              final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red, Colors.teal];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 8, height: 8, color: colors[index % colors.length]),
                  const SizedBox(width: 4),
                  Text(cat, style: const TextStyle(fontSize: 10)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard(BuildContext context, List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final productStats = <String, Map<String, dynamic>>{};
    for (final sale in sales) {
      if (sale.status == SaleStatus.cancelled) continue;
      for (final item in sale.items) {
        final name = item.product.name;
        productStats.putIfAbsent(name, () => {'revenue': 0.0, 'weight': 0.0});
        productStats[name]!['revenue'] += item.total;
        productStats[name]!['weight'] += item.quantity;
      }
    }

    final sortedProducts = productStats.entries.toList()..sort((a, b) => b.value['revenue'].compareTo(a.value['revenue']));
    final top5 = sortedProducts.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Selling Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
          const SizedBox(height: AppSpacing.m),
          ...top5.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Text('${top5.indexOf(e) + 1}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('${WeightConverter.formatShort(e.value['weight'])} sold', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Text('₵${e.value['revenue'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildStaffPerformanceCard(BuildContext context, List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final staffStats = <String, Map<String, dynamic>>{};
    for (final sale in sales) {
      if (sale.status == SaleStatus.cancelled) continue;
      final name = sale.cashierName;
      staffStats.putIfAbsent(name, () => {'revenue': 0.0, 'count': 0});
      staffStats[name]!['revenue'] += sale.totalAmount;
      staffStats[name]!['count'] += 1;
    }

    final sortedStaff = staffStats.entries.toList()..sort((a, b) => b.value['revenue'].compareTo(a.value['revenue']));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cashier Performance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
          const SizedBox(height: AppSpacing.m),
          if (sortedStaff.isEmpty)
             const Text('No data available', style: TextStyle(fontSize: 12))
          else
            ...sortedStaff.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(e.key.substring(0, 1).toUpperCase(), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${e.value['count']} transactions', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text('₵${e.value['revenue'].toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.m,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 600 ? constraints.maxWidth : 250,
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search Receipt ID...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: constraints.maxWidth < 600 ? constraints.maxWidth : 220,
                  child: DropdownButtonFormField<SaleStatus>(
                    initialValue: _statusFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Status')),
                      ...SaleStatus.values.map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s.name.replaceAll(RegExp(r'(?=[A-Z])'), ' ').toUpperCase(),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {
                        _startDate = picked.start;
                        _endDate = picked.end;
                      });
                    }
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(_startDate == null
                      ? 'Filter Date'
                      : '${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}'),
                ),
                if (_startDate != null || _statusFilter != null || _searchQuery.isNotEmpty)
                  IconButton(
                    onPressed: () => setState(() {
                      _startDate = null;
                      _endDate = null;
                      _statusFilter = null;
                      _searchQuery = '';
                    }),
                    icon: const Icon(Icons.clear_all),
                    tooltip: 'Clear Filters',
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<SaleRecord> filteredSales, double totalExpenses) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      
      final headerContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Transaction History',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            'Detailed breakdown of all shop revenue (${filteredSales.length} items)',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      );

      final exportButton = ElevatedButton.icon(
        onPressed: () => ReceiptService.printSalesReport(filteredSales, totalExpenses: totalExpenses),
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Export to PDF'),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        ),
      );

      final printSelectedButton = _selectedSaleIds.isNotEmpty 
        ? ElevatedButton.icon(
            onPressed: _isPrintingSelected ? null : () async {
              setState(() => _isPrintingSelected = true);
              final selectedSales = filteredSales.where((s) => _selectedSaleIds.contains(s.id)).toList();
              await ReceiptService.printInvoices(selectedSales);
              setState(() {
                _isPrintingSelected = false;
                _selectedSaleIds.clear();
              });
            },
            icon: _isPrintingSelected 
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.print),
            label: Text('Print Selected (${_selectedSaleIds.length})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
          )
        : null;

      final deleteSelectedButton = _selectedSaleIds.isNotEmpty
        ? ElevatedButton.icon(
            onPressed: _isDeletingSelected ? null : () => _confirmDeleteSelected(context),
            icon: _isDeletingSelected
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.delete_outline),
            label: Text('Delete (${_selectedSaleIds.length})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            ),
          )
        : null;

      if (isMobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerContent,
            const SizedBox(height: AppSpacing.m),
            if (deleteSelectedButton != null) ...[
              SizedBox(width: double.infinity, child: deleteSelectedButton),
              const SizedBox(height: AppSpacing.s),
            ],
            if (printSelectedButton != null) ...[
              SizedBox(width: double.infinity, child: printSelectedButton),
              const SizedBox(height: AppSpacing.s),
            ],
            SizedBox(width: double.infinity, child: exportButton),
          ],
        );
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: headerContent),
          const SizedBox(width: 16),
          if (deleteSelectedButton != null) ...[
            deleteSelectedButton,
            const SizedBox(width: 8),
          ],
          if (printSelectedButton != null) ...[
            printSelectedButton,
            const SizedBox(width: 8),
          ],
          exportButton,
        ],
      );
    });
  }

  Widget _buildSummaryCards(BuildContext context, List<SaleRecord> sales, double totalExpenses) {
    final activeSales = sales.where((s) => s.status != SaleStatus.cancelled).toList();
    final totalRevenue = activeSales.fold(0.0, (sum, sale) => sum + sale.totalAmount);
    final netProfit = totalRevenue - totalExpenses;

    return LayoutBuilder(builder: (context, constraints) {
      final double width = constraints.maxWidth;
      // 1 column on small phones, 3 columns on desktop/tablets
      final int crossAxisCount = width > 600 ? 3 : 1;
      final double spacing = AppSpacing.m;
      final double itemWidth = (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;

      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          SizedBox(width: itemWidth, child: _reportCard(context, 'Gross Volume', '₵ ${totalRevenue.toStringAsFixed(2)}', Icons.payments, Colors.blue)),
          SizedBox(width: itemWidth, child: _reportCard(context, 'Total Expenses', '₵ ${totalExpenses.toStringAsFixed(2)}', Icons.trending_down, Colors.red)),
          SizedBox(width: itemWidth, child: _reportCard(context, 'Net Profit', '₵ ${netProfit.toStringAsFixed(2)}', Icons.account_balance_wallet, Colors.green)),
        ],
      );
    });
  }

  Widget _reportCard(BuildContext context, String title, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
        ],
        border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.s),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.toUpperCase(),
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTable(List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final user = ref.read(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                child: Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              ),
              if (sales.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Text('No transactions found.')))
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sales.length,
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    final isDebt = sale.balance > 0.01;
                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.m),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.m),
                        side: isDebt ? const BorderSide(color: Colors.red, width: 1) : BorderSide.none,
                      ),
                      child: ListTile(
                        onTap: () => _showSaleDetails(context, sale),
                        leading: CircleAvatar(
                          backgroundColor: _getStatusColor(sale.status).withValues(alpha: 0.1),
                          child: Icon(Icons.receipt_long, color: _getStatusColor(sale.status), size: 20),
                        ),
                        title: Text(sale.id, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat('MMM dd, HH:mm').format(sale.timestamp), style: const TextStyle(fontSize: 10)),
                            Text('Cust: ${sale.customerName ?? "Walk-in"}', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₵${sale.totalAmount.toStringAsFixed(2)}', 
                              style: TextStyle(fontWeight: FontWeight.bold, color: isDebt ? Colors.red : null)),
                            if (isDebt)
                              const Text('DEBT', style: TextStyle(color: Colors.red, fontSize: 8, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        }

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(AppRadius.m),
            boxShadow: [
              if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)
            ],
            border: isDark ? Border.all(color: theme.dividerColor) : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
              ),
              if (sales.isEmpty)
                const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Text('No transactions found.')))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 800),
                    child: DataTable(
                      columnSpacing: 24,
                      horizontalMargin: 12,
                      showCheckboxColumn: true,
                      onSelectAll: (selected) {
                        setState(() {
                          if (selected == true) {
                            _selectedSaleIds.addAll(sales.map((s) => s.id));
                          } else {
                            _selectedSaleIds.clear();
                          }
                        });
                      },
                      headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 12),
                      columns: const [
                        DataColumn(label: Text('Invoice ID')),
                        DataColumn(label: Text('Date & Time')),
                        DataColumn(label: Text('Customer')),
                        DataColumn(label: Text('Sold By')),
                        DataColumn(label: Text('Total')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: sales.map<DataRow>((sale) {
                        final isSelected = _selectedSaleIds.contains(sale.id);
                        final isDebt = sale.balance > 0.01;
                        return DataRow(
                          selected: isSelected,
                          color: WidgetStateProperty.resolveWith<Color?>((states) {
                            if (isDebt && !isSelected) return Colors.red.withValues(alpha: 0.03);
                            return null;
                          }),
                          onSelectChanged: (selected) {
                            setState(() {
                              if (selected == true) {
                                _selectedSaleIds.add(sale.id);
                              } else {
                                _selectedSaleIds.remove(sale.id);
                              }
                            });
                          },
                          onLongPress: () => _showSaleDetails(context, sale),
                          cells: [
                            DataCell(
                              InkWell(
                                onTap: () => _showSaleDetails(context, sale),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (sale.isVerified)
                                       const Icon(Icons.verified, color: Colors.blue, size: 14),
                                    if (sale.isVerified)
                                       const SizedBox(width: 4),
                                    Text(sale.id, style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      decoration: TextDecoration.underline,
                                      color: isDebt ? Colors.red.shade900 : null,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(Text(DateFormat('MMM dd, HH:mm:ss').format(sale.timestamp), 
                              style: TextStyle(color: isDebt ? Colors.red.shade900 : null))),
                            DataCell(
                              SizedBox(
                                width: 100,
                                child: Text(
                                  sale.customerName ?? 'Walk-in',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDebt ? Colors.red.shade900 : null,
                                    fontWeight: isDebt ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 100,
                                child: Text(
                                  sale.cashierName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: isDebt ? Colors.red.shade900 : null),
                                ),
                              ),
                            ),
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('₵ ${sale.totalAmount.toStringAsFixed(2)}', 
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      color: isDebt ? Colors.red : null
                                    )
                                  ),
                                  if (isDebt)
                                    Text('Balance: ₵${sale.balance.toStringAsFixed(2)}', 
                                      style: const TextStyle(fontSize: 9, color: Colors.red, fontWeight: FontWeight.bold)
                                    ),
                                ],
                              )
                            ),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(sale.status).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    sale.status.name.toUpperCase(),
                                    style: TextStyle(
                                      color: _getStatusColor(sale.status),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isDebt) ...[
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'DEBT',
                                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ],
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSaleDetails(BuildContext context, SaleRecord sale) {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    bool isPrinting = false;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            backgroundColor: theme.colorScheme.surface,
            child: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.l)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long, color: Colors.white),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Transaction Details',
                                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                sale.id,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('CASHIER', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                    Text(sale.cashierName, 
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text('ID: ${sale.cashierId.substring(0, 8).toUpperCase()}', 
                                      style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('DATE', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                  Text(DateFormat('MMM dd').format(sale.timestamp), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  Text(DateFormat('HH:mm').format(sale.timestamp), style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          Text('ITEMS', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ...sale.items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(item.product.name, 
                                    style: TextStyle(color: theme.colorScheme.onSurface),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Text('${WeightConverter.formatShort(item.quantity)} x ₵${item.priceAtSale.toStringAsFixed(2)}', 
                                    textAlign: TextAlign.right,
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text('₵${item.total.toStringAsFixed(2)}', 
                                  style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)
                                ),
                              ],
                            ),
                          )),
                          const Divider(height: 32),
                          _detailRow(context, 'NET INVOICE VALUE', '₵${sale.netInvoiceValue.toStringAsFixed(2)}', 
                            isBold: true, color: sale.balance > 0.01 ? Colors.red : theme.colorScheme.primary),
                          if (sale.balance > 0.01)
                            _detailRow(context, 'OUTSTANDING BALANCE', '₵${sale.balance.toStringAsFixed(2)}', 
                              isBold: true, color: Colors.red),
                          const Divider(height: 32),
                          Text('PAYMENTS', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ...sale.payments.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(p.method.name.toUpperCase(), style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
                                Text('₵${p.amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
                              ],
                            ),
                          )),
                          if (sale.bankReceiptUrl != null) ...[
                            const Divider(height: 32),
                            Text('BANK DEPOSIT SLIP', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                            if (sale.bankReceiptId != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Reference ID: ${sale.bankReceiptId}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple)),
                              ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AppBar(
                                        title: Text(sale.bankReceiptId ?? 'Deposit Slip', style: const TextStyle(fontSize: 14)),
                                        backgroundColor: Colors.purple,
                                        foregroundColor: Colors.white,
                                        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                                      ),
                                      Flexible(child: Image.network(sale.bankReceiptUrl!)),
                                    ],
                                  ),
                                ),
                              ),
                              child: Container(
                                height: 100,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(sale.bankReceiptUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Center(child: Text('Image Error'))),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Center(child: Text('Tap to enlarge', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic))),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: theme.dividerColor)),
                    ),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowSpacing: 8,
                      children: [
                        if (!sale.isVerified && (user.activePrimaryRole == UserRole.cashier || user.activePrimaryRole == UserRole.admin || user.activePrimaryRole == UserRole.superAdmin))
                          ElevatedButton.icon(
                            onPressed: () {
                              ref.read(saleHistoryProvider.notifier).verifySale(sale.id);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Transaction Verified. Inventory updated.'), backgroundColor: Colors.green),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('VERIFY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                          ),
                        if (sale.status != SaleStatus.cancelled)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.pop(context); // Close details
                              _showEditSaleDialog(context, sale);
                            },
                            icon: const Icon(Icons.edit_note, color: Colors.blue, size: 16),
                            label: const Text('Edit Receipt', style: TextStyle(color: Colors.blue, fontSize: 11)),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context), 
                          child: const Text('Close', style: TextStyle(fontSize: 12))
                        ),
                        ElevatedButton.icon(
                          onPressed: isPrinting ? null : () async {
                            setState(() => isPrinting = true);
                            await ReceiptService.printReceipt(sale);
                            setState(() => isPrinting = false);
                          },
                          icon: isPrinting 
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.print, size: 14),
                          label: const Text('REPRINT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary, 
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value, {bool isBold = false, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  void _showEditSaleDialog(BuildContext context, SaleRecord sale) {
    final List<SaleItem> editedItems = List.from(sale.items);
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          double calculateNewTotal() => editedItems.fold(0, (sum, item) => sum + item.total);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: Row(
              children: [
                const Icon(Icons.edit_note, color: Colors.blue),
                const SizedBox(width: 12),
                Text('Edit Transaction ${sale.id}'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modify item quantities or prices. Changes will update the database and alert the cashier for reprinting.', 
                      style: TextStyle(fontSize: 11, color: Colors.blue)),
                    const SizedBox(height: 16),
                    ...editedItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(item.product.category, style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.quantity.toString(),
                                decoration: const InputDecoration(labelText: 'Qty/Weight', isDense: true),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  final newQty = double.tryParse(value) ?? item.quantity;
                                  setState(() {
                                    editedItems[index] = SaleItem(
                                      product: item.product,
                                      quantity: newQty,
                                      priceAtSale: item.priceAtSale,
                                      originalPrice: item.originalPrice,
                                    );
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: item.priceAtSale.toString(),
                                decoration: const InputDecoration(labelText: 'Price/kg', isDense: true, prefixText: '₵'),
                                keyboardType: TextInputType.number,
                                onChanged: (value) {
                                  final newPrice = double.tryParse(value) ?? item.priceAtSale;
                                  setState(() {
                                    editedItems[index] = SaleItem(
                                      product: item.product,
                                      quantity: item.quantity,
                                      priceAtSale: newPrice,
                                      originalPrice: item.originalPrice,
                                    );
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Net Value:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('₵${calculateNewTotal().toStringAsFixed(2)}', 
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 18)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  final newTotal = calculateNewTotal();
                  final updatedSale = sale.copyWith(
                    items: editedItems,
                    totalAmount: newTotal,
                    status: SaleStatus.rectified,
                  );
                  
                  await ref.read(saleHistoryProvider.notifier).updateSale(updatedSale);
                  
                  // Notify the cashier/system
                  ref.read(notificationProvider.notifier).addNotification(
                    'RECEIPT UPDATED',
                    'Receipt ${sale.id} was edited by Admin. Please re-print if necessary.',
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transaction updated and saved to database.'), backgroundColor: AppColors.accentGreen),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
                child: const Text('Save & Update DB'),
              ),
            ],
          );
        },
      ),
    );
  }

  Color _getStatusColor(SaleStatus status) {
    switch (status) {
      case SaleStatus.completed: return Colors.green;
      case SaleStatus.rectified: return Colors.blue;
      case SaleStatus.pendingCorrection: return Colors.orange;
      case SaleStatus.cancelled: return Colors.red;
      case SaleStatus.awaitingDeposit: return Colors.purple;
    }
  }

  void _confirmDeleteSelected(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Transactions?'),
        content: Text('Are you sure you want to permanently delete ${_selectedSaleIds.length} selected transactions? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() => _isDeletingSelected = true);
              try {
                await ref.read(saleHistoryProvider.notifier).deleteSales(_selectedSaleIds.toList());
                if (!mounted) return;
                setState(() {
                  _selectedSaleIds.clear();
                  _isDeletingSelected = false;
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transactions deleted successfully.')),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _isDeletingSelected = false);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}
