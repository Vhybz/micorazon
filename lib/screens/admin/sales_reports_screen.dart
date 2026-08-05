import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/sale_provider.dart';
import '../../services/expense_provider.dart';
import '../../models/sale_model.dart';
import '../../services/receipt_service.dart';
import '../../services/notification_service.dart';
import '../../services/sms_service.dart';
import '../../services/branch_provider.dart';
import '../../core/utils.dart';
import 'package:intl/intl.dart';

import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../widgets/phone_prompt_dialog.dart';

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

  String? _cashierFilter;
  PaymentMethod? _paymentMethodFilter;
  double? _minTotal;
  double? _maxTotal;

  int? _sortColumnIndex;
  bool _sortAscending = true;

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
    final expenseState = ref.watch(expenseProvider);
    
    final filteredSales = salesHistory.where((sale) {
      final matchesSearch = _searchQuery.isEmpty || 
                           sale.id.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                           sale.customerName?.toLowerCase().contains(_searchQuery.toLowerCase()) == true;
      
      final matchesStatus = _statusFilter == null || sale.status == _statusFilter;
      
      bool matchesDate = true;
      if (_startDate != null && _endDate != null) {
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        matchesDate = sale.timestamp.isAfter(start.subtract(const Duration(seconds: 1))) && 
                      sale.timestamp.isBefore(end.add(const Duration(seconds: 1)));
      }

      final matchesCashier = _cashierFilter == null || sale.cashierName == _cashierFilter;

      final matchesPayment = _paymentMethodFilter == null || 
                            sale.payments.any((p) => p.method == _paymentMethodFilter);

      final matchesMinTotal = _minTotal == null || sale.totalAmount >= _minTotal!;
      final matchesMaxTotal = _maxTotal == null || sale.totalAmount <= _maxTotal!;

      return matchesSearch && matchesStatus && matchesDate && matchesCashier && matchesPayment && matchesMinTotal && matchesMaxTotal;
    }).toList();

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
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'OVERVIEW', icon: Icon(Icons.analytics_outlined)),
                      Tab(text: 'TRANSACTIONS', icon: Icon(Icons.history_rounded)),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(context, filteredSales, expenseState.records),
                        _buildTransactionsTab(context, filteredSales),
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

  Widget _buildOverviewTab(BuildContext context, List<SaleRecord> sales, List<dynamic> expenses) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(context, sales, expenses),
          const SizedBox(height: AppSpacing.xl),
          _buildRevenueChart(context, sales),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab(BuildContext context, List<SaleRecord> filteredSales) {
    final theme = Theme.of(context);
    final Map<String, ({double qty, String category})> productStatsMap = {};
    double totalSales = 0;
    double totalProfit = 0;

    for (var sale in filteredSales) {
      if (sale.status == SaleStatus.cancelled) continue;
      totalSales += sale.totalAmount;
      totalProfit += (sale.totalAmount - sale.totalCost);
      for (var item in sale.items) {
        final existing = productStatsMap[item.product.name];
        productStatsMap[item.product.name] = (
          qty: (existing?.qty ?? 0) + item.quantity,
          category: item.product.category
        );
      }
    }

    final sortedProducts = productStatsMap.entries.toList()
      ..sort((a, b) => b.value.qty.compareTo(a.value.qty));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, filteredSales),
          const SizedBox(height: AppSpacing.xl),
          _buildFilters(),
          const SizedBox(height: AppSpacing.xl),
          
          // New Visual Insights
          Row(
            children: [
              Expanded(child: _reportCard(context, 'Period Sales', '₵ ${totalSales.toStringAsFixed(2)}', Icons.payments, Colors.blue)),
              const SizedBox(width: AppSpacing.m),
              Expanded(child: _reportCard(context, 'Period Profit', '₵ ${totalProfit.toStringAsFixed(2)}', Icons.trending_up, Colors.green)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          Text('SALES TREND', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 12),
          _buildSalesTrendChart(filteredSales, theme),
          const SizedBox(height: AppSpacing.xl),

          if (sortedProducts.isNotEmpty) ...[
            Text('HIGHEST PURCHASED PRODUCTS', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 12),
            _buildTopProductsList(sortedProducts, theme),
            const SizedBox(height: AppSpacing.xl),
          ],

          _buildSalesTable(filteredSales),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final staff = ref.watch(userProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Wrap(
                  spacing: AppSpacing.m,
                  runSpacing: AppSpacing.m,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Search: Receipt ID / Customer
                    SizedBox(
                      width: constraints.maxWidth < 600 ? constraints.maxWidth : 220,
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: InputDecoration(
                          hintText: 'Invoice / Customer...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                          isDense: true,
                        ),
                      ),
                    ),
                    
                    // Sold By (Staff)
                    SizedBox(
                      width: constraints.maxWidth < 600 ? constraints.maxWidth : 180,
                      child: DropdownButtonFormField<String>(
                        initialValue: _cashierFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Sold By', border: OutlineInputBorder(), isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Staff')),
                          ...staff.map((u) => DropdownMenuItem(value: u.name, child: Text(u.name, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) => setState(() => _cashierFilter = v),
                      ),
                    ),

                    // Payment Method
                    SizedBox(
                      width: constraints.maxWidth < 600 ? constraints.maxWidth : 160,
                      child: DropdownButtonFormField<PaymentMethod>(
                        initialValue: _paymentMethodFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Payment', border: OutlineInputBorder(), isDense: true),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Methods')),
                          ...PaymentMethod.values.map((m) => DropdownMenuItem(value: m, child: Text(m.name.toUpperCase()))),
                        ],
                        onChanged: (v) => setState(() => _paymentMethodFilter = v),
                      ),
                    ),

                    // Status
                    SizedBox(
                      width: constraints.maxWidth < 600 ? constraints.maxWidth : 160,
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

                    // Date
                    OutlinedButton.icon(
                      onPressed: () => _showDateFilterOptions(context),
                      icon: const Icon(Icons.date_range),
                      label: Text(_startDate == null
                          ? 'Filter Date'
                          : _startDate!.day == _endDate!.day && _startDate!.month == _endDate!.month && _startDate!.year == _endDate!.year
                              ? DateFormat('MM/dd').format(_startDate!)
                              : '${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}'),
                    ),

                    if (_startDate != null || _statusFilter != null || _searchQuery.isNotEmpty || _cashierFilter != null || _paymentMethodFilter != null || _minTotal != null || _maxTotal != null)
                      IconButton(
                        onPressed: () => setState(() {
                          _startDate = null;
                          _endDate = null;
                          _statusFilter = null;
                          _searchQuery = '';
                          _cashierFilter = null;
                          _paymentMethodFilter = null;
                          _minTotal = null;
                          _maxTotal = null;
                        }),
                        icon: const Icon(Icons.clear_all, color: Colors.red),
                        tooltip: 'Clear All Filters',
                      ),
                  ],
                ),
                
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),

                // Amount Range Filter
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.m,
                  runSpacing: AppSpacing.s,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.payments_outlined, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text('Amount Range (GHS):', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth < 600 ? (constraints.maxWidth - 40) / 2 : 100,
                          child: TextField(
                            decoration: const InputDecoration(hintText: 'Min', isDense: true, border: UnderlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() => _minTotal = double.tryParse(v)),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text('-', style: TextStyle(color: Colors.grey)),
                        ),
                        SizedBox(
                          width: constraints.maxWidth < 600 ? (constraints.maxWidth - 40) / 2 : 100,
                          child: TextField(
                            decoration: const InputDecoration(hintText: 'Max', isDense: true, border: UnderlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) => setState(() => _maxTotal = double.tryParse(v)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<SaleRecord> filteredSales) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      
      final headerText = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Transaction History',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'Detailed breakdown of all shop revenue (${filteredSales.length} items)',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      );

      final exportButton = ElevatedButton.icon(
        onPressed: () => ReceiptService.printSalesReport(filteredSales),
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

      if (isMobile) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headerText,
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(child: exportButton),
                if (printSelectedButton != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: printSelectedButton),
                ],
              ],
            ),
          ],
        );
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: headerText),
          const SizedBox(width: 16),
          if (printSelectedButton != null) ...[
            printSelectedButton,
            const SizedBox(width: 12),
          ],
          exportButton,
        ],
      );
    });
  }

  Widget _buildSummaryCards(BuildContext context, List<SaleRecord> sales, List<dynamic> expenses) {
    final totalRevenue = sales.where((s) => s.status != SaleStatus.cancelled).fold(0.0, (sum, sale) => sum + sale.totalAmount);
    final totalExpenses = expenses.fold(0.0, (sum, e) => sum + (e.amount as double));
    final netProfit = totalRevenue - totalExpenses;

    return LayoutBuilder(builder: (context, constraints) {
      final bool useColumn = constraints.maxWidth < 900;
      
      if (useColumn) {
        return Column(
          children: [
            _reportCard(context, 'Gross Volume', '₵ ${totalRevenue.toStringAsFixed(2)}', Icons.payments, Colors.blue),
            const SizedBox(height: AppSpacing.m),
            _reportCard(context, 'Total Expenses', '₵ ${totalExpenses.toStringAsFixed(2)}', Icons.trending_down, Colors.red),
            const SizedBox(height: AppSpacing.m),
            _reportCard(context, 'Net Profit', '₵ ${netProfit.toStringAsFixed(2)}', Icons.account_balance_wallet, Colors.green),
          ],
        );
      }
      
      return Row(
        children: [
          Expanded(child: _reportCard(context, 'Gross Volume', '₵ ${totalRevenue.toStringAsFixed(2)}', Icons.payments, Colors.blue)),
          const SizedBox(width: AppSpacing.m),
          Expanded(child: _reportCard(context, 'Total Expenses', '₵ ${totalExpenses.toStringAsFixed(2)}', Icons.trending_down, Colors.red)),
          const SizedBox(width: AppSpacing.m),
          Expanded(child: _reportCard(context, 'Net Profit', '₵ ${netProfit.toStringAsFixed(2)}', Icons.account_balance_wallet, Colors.green)),
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
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.m),
          Text(
            title,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart(BuildContext context, List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Last 7 days data
    final now = DateTime.now();
    final List<double> dailyRevenue = List.filled(7, 0.0);
    final List<String> labels = [];

    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: 6 - i));
      labels.add(DateFormat('E').format(date));
      
      final daySales = sales.where((s) => 
        s.timestamp.day == date.day && 
        s.timestamp.month == date.month && 
        s.timestamp.year == date.year &&
        s.status != SaleStatus.cancelled
      );
      
      dailyRevenue[i] = daySales.fold(0.0, (sum, s) => sum + s.totalAmount);
    }

    double maxRevenue = dailyRevenue.reduce((a, b) => a > b ? a : b);
    if (maxRevenue == 0) maxRevenue = 1000;

    return Container(
      height: 300,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly Revenue Trend', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) => Text(labels[val.toInt()], style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(7, (i) => FlSpot(i.toDouble(), dailyRevenue[i])),
                    isCurved: true,
                    color: theme.colorScheme.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (spot) => theme.colorScheme.surface,
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem('₵${s.y.toStringAsFixed(2)}', TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold))).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTable(List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Apply Sorting
    if (_sortColumnIndex != null) {
      sales.sort((a, b) {
        int result = 0;
        switch (_sortColumnIndex) {
          case 0: result = a.id.compareTo(b.id); break;
          case 1: result = a.timestamp.compareTo(b.timestamp); break;
          case 2: result = (a.customerName ?? '').compareTo(b.customerName ?? ''); break;
          case 3: result = a.cashierName.compareTo(b.cashierName); break;
          case 4: result = a.totalAmount.compareTo(b.totalAmount); break;
          case 5: 
            final aMethods = a.payments.map((p) => p.method.name).join(', ');
            final bMethods = b.payments.map((p) => p.method.name).join(', ');
            result = aMethods.compareTo(bMethods); 
            break;
          case 6: result = a.status.name.compareTo(b.status.name); break;
        }
        return _sortAscending ? result : -result;
      });
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
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.s,
              children: [
                Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
                if (_selectedSaleIds.isNotEmpty)
                  TextButton.icon(
                    onPressed: _isDeletingSelected ? null : () => _confirmDeleteSelected(),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: Text('Delete Selected (${_selectedSaleIds.length})', style: const TextStyle(color: Colors.red)),
                  ),
              ],
            ),
          ),
          if (sales.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.xl), child: Text('No transactions found.')))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 900),
                child: DataTable(
                  columnSpacing: 24,
                  horizontalMargin: 12,
                  showCheckboxColumn: true,
                  sortColumnIndex: _sortColumnIndex,
                  sortAscending: _sortAscending,
                  headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 12),
                  columns: [
                    DataColumn(label: const Text('Invoice ID'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                    DataColumn(label: const Text('Date'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                    DataColumn(label: const Text('Customer'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                    DataColumn(label: const Text('Sold By'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                    DataColumn(label: const Text('Total'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                    DataColumn(label: const Text('Payment'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                    DataColumn(label: const Text('Status'), onSort: (idx, asc) => setState(() { _sortColumnIndex = idx; _sortAscending = asc; })),
                  ],
                  rows: sales.map<DataRow>((sale) {
                    final isSelected = _selectedSaleIds.contains(sale.id);
                    final paymentMethods = sale.payments.map((p) {
                      switch (p.method) {
                        case PaymentMethod.cash: return 'CASH';
                        case PaymentMethod.mobileMoney: return 'MOMO';
                        case PaymentMethod.bankDeposit: return 'BANK';
                      }
                    }).toSet().join(', ');

                    return DataRow(
                      selected: isSelected,
                      onSelectChanged: (val) {
                      setState(() {
                        if (val == true) {
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
                            child: Text(sale.id, style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                          )
                        ),
                        DataCell(Text(DateFormat('MMM dd, HH:mm').format(sale.timestamp))),
                        DataCell(
                          SizedBox(
                            width: 100,
                            child: Text(
                              sale.customerName ?? 'Walk-in',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 100,
                            child: Text(
                              sale.cashierName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        DataCell(Text('₵ ${sale.totalAmount.toStringAsFixed(2)}')),
                        DataCell(
                          Text(paymentMethods, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        ),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(sale.status).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                sale.status.name.toUpperCase(),
                                style: TextStyle(
                                  color: _getStatusColor(sale.status),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (sale.balance > 0.01) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.all(2),
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
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDateFilterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Today'),
            onTap: () {
              final now = DateTime.now();
              setState(() {
                _startDate = now;
                _endDate = now;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Yesterday'),
            onTap: () {
              final yesterday = DateTime.now().subtract(const Duration(days: 1));
              setState(() {
                _startDate = yesterday;
                _endDate = yesterday;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Specific Day'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate ?? DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _startDate = picked;
                  _endDate = picked;
                });
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Date Range'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: (_startDate != null && _endDate != null) 
                  ? DateTimeRange(start: _startDate!, end: _endDate!) 
                  : null,
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
          ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }

  void _showSaleDetails(BuildContext context, SaleRecord sale) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal during sub-actions
      builder: (detailsContext) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(detailsContext);
          
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.receipt_long, color: Colors.white),
                              const SizedBox(width: AppSpacing.m),
                              Expanded(
                                child: Text(
                                  'Transaction ${sale.id}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.of(detailsContext).pop(),
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
                                    Text('${sale.cashierName} (${sale.cashierId})', 
                                      style: const TextStyle(fontSize: 13),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('DATE', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                  Text(DateFormat('MMM dd, HH:mm').format(sale.timestamp), style: const TextStyle(fontSize: 13)),
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
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.product.category.toUpperCase(), style: TextStyle(color: theme.colorScheme.primary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                      Text(item.product.name, 
                                        style: TextStyle(color: theme.colorScheme.onSurface),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: Text('${WeightConverter.formatShort(item.quantity, unit: item.product.unit)} x ₵${item.priceAtSale.toStringAsFixed(2)}', 
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
                          _detailRow(detailsContext, 'NET INVOICE VALUE', '₵${sale.netInvoiceValue.toStringAsFixed(2)}', isBold: true, color: theme.colorScheme.primary),
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
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpacing.s,
                      runSpacing: AppSpacing.s,
                      children: [
                        if (sale.status != SaleStatus.cancelled && sale.status != SaleStatus.reversed)
                          TextButton.icon(
                            onPressed: () {
                              Navigator.of(detailsContext).pop();
                              _showEditSaleDialog(context, sale);
                            },
                            icon: const Icon(Icons.edit_note, color: Colors.blue),
                            label: const Text('Edit Receipt', style: TextStyle(color: Colors.blue)),
                          )
                        else
                          const SizedBox.shrink(),
                        
                        // NEW: Reverse Transaction Button
                        if (sale.status != SaleStatus.reversed)
                          TextButton.icon(
                            onPressed: () => _confirmReverseTransaction(detailsContext, sale),
                            icon: const Icon(Icons.history_rounded, color: Colors.red),
                            label: const Text('Reverse Transaction', style: TextStyle(color: Colors.red)),
                          ),

                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(onPressed: () => Navigator.of(detailsContext).pop(), child: const Text('Close')),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(detailsContext).pop();
                                _showReceiptOptionsDialog(context, sale, ref);
                              },
                              icon: const Icon(Icons.more_vert, size: 18),
                              label: const Text('Options'),
                              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
                            ),
                          ],
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

  void _showReceiptOptionsDialog(BuildContext context, SaleRecord sale, WidgetRef ref) {
    final currentBranch = ref.read(currentBranchProvider);
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppColors.primaryMaroon),
              SizedBox(width: 12),
              Text('RECEIPT OPTIONS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 16)),
            ],
          ),
          content: isProcessing 
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _receiptOptionTile(
                    context,
                    icon: Icons.print_rounded,
                    title: 'PRINT RECEIPT',
                    subtitle: 'Send to thermal printer',
                    onTap: () async {
                      setState(() => isProcessing = true);
                      await ReceiptService.printReceipt(sale);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 10),
                  _receiptOptionTile(
                    context,
                    icon: Icons.sms_rounded,
                    title: 'SEND VIA SMS',
                    subtitle: sale.customerPhone ?? 'Enter custom number',
                    enabled: true,
                    onTap: () async {
                      String? targetPhone = sale.customerPhone;
                      if (targetPhone == null || targetPhone.isEmpty) {
                        targetPhone = await PhonePromptDialog.show(context);
                      }

                      if (targetPhone != null && targetPhone.isNotEmpty) {
                        setState(() => isProcessing = true);
                        final success = await SmsService.sendReceiptSms(
                          sale, 
                          branchName: currentBranch?.name,
                          customPhone: targetPhone,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? 'SMS Sent' : 'SMS Failed'),
                              backgroundColor: success ? Colors.green : Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _receiptOptionTile(
                    context,
                    icon: Icons.share_rounded,
                    title: 'SHARE PDF (WHATSAPP)',
                    subtitle: 'Share via WhatsApp or Email',
                    onTap: () async {
                      setState(() => isProcessing = true);
                      await ReceiptService.shareReceipt(sale);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptOptionTile(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap, bool enabled = true}) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: enabled ? onTap : null,
      enabled: enabled,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: theme.colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      tileColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1))),
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
                Text('Edit Transaction ${sale.id.substring(0, 8)}'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modify item quantities or prices. Changes will update the database.', 
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
                                decoration: const InputDecoration(labelText: 'Qty', isDense: true),
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
                                decoration: const InputDecoration(labelText: 'Price', isDense: true, prefixText: '₵'),
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
                  
                  ref.read(notificationProvider.notifier).addNotification(
                    'RECEIPT UPDATED',
                    'Receipt ${sale.id} was edited by Admin.',
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transaction updated and saved to database.'), backgroundColor: Colors.green),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteSelected() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete ${_selectedSaleIds.length} transactions?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              setState(() => _isDeletingSelected = true);
              Navigator.pop(context);
              await ref.read(saleHistoryProvider.notifier).deleteSales(_selectedSaleIds.toList());
              setState(() {
                _isDeletingSelected = false;
                _selectedSaleIds.clear();
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmReverseTransaction(BuildContext detailsContext, SaleRecord sale) {
    showDialog(
      context: detailsContext,
      barrierDismissible: false,
      builder: (confContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 12),
            Text('Reverse Transaction?'),
          ],
        ),
        content: Text(
          'Are you sure you want to REVERSE this transaction (${sale.id})?\n\n'
          '• The record status will be updated to REVERSED.\n'
          '• Sold items will be returned to stock.\n'
          '• Sales analytics will be rectified immediately.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confContext).pop(),
            child: const Text('NO, KEEP IT'),
          ),
          ElevatedButton(
            onPressed: () async {
              // 1. Close both dialogs safely
              Navigator.of(confContext).pop(); 
              Navigator.of(detailsContext).pop(); 
              
              try {
                await ref.read(saleHistoryProvider.notifier).reverseSale(sale.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Transaction reversed. Stock restored and analytics rectified.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Reverse failed: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('YES, REVERSE'),
          ),
        ],
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

  Color _getStatusColor(SaleStatus status) {
    switch (status) {
      case SaleStatus.completed: return Colors.green;
      case SaleStatus.rectified: return Colors.blue;
      case SaleStatus.pendingCorrection: return Colors.orange;
      case SaleStatus.cancelled: return Colors.red;
      case SaleStatus.reversed: return Colors.red.shade900;
      case SaleStatus.awaitingDeposit: return Colors.purple;
    }
  }

  Widget _buildSalesTrendChart(List<SaleRecord> sales, ThemeData theme) {
    if (sales.isEmpty) return const SizedBox.shrink();

    // Group by day for the last 7 days or filtered range
    final List<DateTime> dates = [];
    final now = DateTime.now();
    bool isSingleDay = false;
    
    if (_startDate != null && _endDate != null) {
      DateTime d = _startDate!;
      while (d.isBefore(_endDate!.add(const Duration(days: 1)))) {
        dates.add(DateTime(d.year, d.month, d.day));
        d = d.add(const Duration(days: 1));
      }
      if (dates.length == 1) isSingleDay = true;
    } else {
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        dates.add(DateTime(d.year, d.month, d.day));
      }
    }

    final List<double> chartData;
    final List<String> labels;

    if (isSingleDay) {
      final targetDate = dates.first;
      final hours = [8, 10, 12, 14, 16, 18, 20];
      chartData = hours.map((h) {
        return sales
            .where((s) => s.timestamp.year == targetDate.year && 
                          s.timestamp.month == targetDate.month && 
                          s.timestamp.day == targetDate.day &&
                          s.timestamp.hour >= h && s.timestamp.hour < h + 2 &&
                          s.isActive)
            .fold(0.0, (sum, s) => sum + s.totalAmount);
      }).toList();
      labels = hours.map((h) => '${h > 12 ? h - 12 : h}${h >= 12 ? 'pm' : 'am'}').toList();
    } else {
      chartData = dates.map((date) {
        return sales
            .where((s) => s.timestamp.year == date.year && s.timestamp.month == date.month && s.timestamp.day == date.day && s.isActive)
            .fold(0.0, (sum, s) => sum + s.totalAmount);
      }).toList();
      labels = dates.map((d) => DateFormat('E').format(d).substring(0, 1)).toList();
    }

    final maxTotal = chartData.isEmpty ? 100.0 : (chartData.reduce((a, b) => a > b ? a : b) + 50.0);

    return Container(
      height: 250,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: theme.dividerColor),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxTotal,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '₵${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < labels.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        labels[index],
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(chartData.length, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: chartData[index],
                  color: theme.colorScheme.primary,
                  width: isSingleDay ? 24 : (chartData.length > 10 ? 8 : 16),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTopProductsList(List<MapEntry<String, ({double qty, String category})>> sortedProducts, ThemeData theme) {
    final totalQty = sortedProducts.fold(0.0, (sum, e) => sum + e.value.qty);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: sortedProducts.take(10).map((e) {
          final double percentage = totalQty > 0 ? (e.value.qty / totalQty) : 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(e.value.category.toUpperCase(), style: TextStyle(fontSize: 9, color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    Text('${e.value.qty.toStringAsFixed(1)} units', 
                      style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    minHeight: 8,
                    backgroundColor: theme.dividerColor,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
