import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../services/sale_provider.dart';
import '../../services/sms_service.dart';
import '../../services/receipt_service.dart';
import '../../services/branch_provider.dart';
import '../../models/sale_model.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/role_pop_scope.dart';

class DebtManagementScreen extends ConsumerStatefulWidget {
  const DebtManagementScreen({super.key});

  @override
  ConsumerState<DebtManagementScreen> createState() => _DebtManagementScreenState();
}

class _DebtManagementScreenState extends ConsumerState<DebtManagementScreen> {
  String _searchQuery = '';
  bool _showPaidInvoices = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final salesHistory = ref.watch(saleHistoryProvider);
    
    // Filter logic
    final filteredSales = salesHistory.where((s) {
      if (s.status == SaleStatus.cancelled) return false;
      
      final isDebt = s.balance > 0.01;
      
      // A sale is a "Cleared Debt" if it's fully paid AND has more than 1 payment 
      // OR a payment reference indicating a manual collection.
      final isClearedDebt = s.balance <= 0.01 && 
          (s.payments.length > 1 || s.payments.any((p) => p.reference?.contains('Collection') ?? false));

      if (_showPaidInvoices) {
        if (!isClearedDebt) return false;
      } else {
        if (!isDebt) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesName = s.customerName?.toLowerCase().contains(query) ?? false;
        final matchesPhone = s.customerPhone?.contains(query) ?? false;
        final matchesId = s.id.toLowerCase().contains(query);
        return matchesName || matchesPhone || matchesId;
      }

      return true;
    }).toList();

    // Sort by most recent first
    filteredSales.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Grouping by Debtor
    final Map<String, double> debtorBalances = {};
    final Map<String, String> debtorNames = {};
    for (var s in salesHistory) {
      if (s.status == SaleStatus.cancelled || s.balance <= 0.01 || s.customerPhone == null) continue;
      debtorBalances[s.customerPhone!] = (debtorBalances[s.customerPhone!] ?? 0) + s.balance;
      debtorNames[s.customerPhone!] = s.customerName ?? 'Unknown';
    }
    final debtors = debtorBalances.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final totalDebt = salesHistory
        .where((s) => s.status != SaleStatus.cancelled)
        .fold(0.0, (sum, s) => sum + (s.balance > 0.01 ? s.balance : 0));
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/debts';

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'Debt & Credit Tracker', showMenuButton: true),
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
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildDebtSummary(context, totalDebt, salesHistory.where((s) => s.balance > 0).length),
                    ),
                    if (debtors.isNotEmpty && !_showPaidInvoices) ...[
                      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
                      SliverToBoxAdapter(child: _buildDebtorsList(theme, debtors, debtorNames)),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
                    SliverToBoxAdapter(child: _buildControls(theme)),
                    const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.m)),
                    if (filteredSales.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(context),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildDebtTile(context, filteredSales[index]),
                            childCount: filteredSales.length,
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

  Widget _buildDebtorsList(ThemeData theme, List<MapEntry<String, double>> debtors, Map<String, String> names) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text('DEBTORS BY CUSTOMER', 
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text('${debtors.length} customers', 
              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: debtors.length,
            itemBuilder: (context, index) {
              final d = debtors[index];
              final name = names[d.key]!;
              return Container(
                width: 180,
                margin: const EdgeInsets.only(right: AppSpacing.m, bottom: 4),
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.m),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(d.key, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                    const Divider(height: 12),
                    Text('₵${d.value.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w900, fontSize: 14)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildControls(ThemeData theme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 600;
    
    return Flex(
      direction: isSmall ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: isSmall ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: isSmall ? double.infinity : screenWidth * 0.4,
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search Name, Phone or Invoice #',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
            ),
          ),
        ),
        if (isSmall) const SizedBox(height: AppSpacing.m) else const SizedBox(width: AppSpacing.m),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            FilterChip(
              label: const Text('Show Fully Paid', style: TextStyle(fontSize: 12)),
              selected: _showPaidInvoices,
              onSelected: (v) => setState(() => _showPaidInvoices = v),
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              checkmarkColor: theme.colorScheme.primary,
            ),
            if (isSmall) 
              Text('${ref.watch(saleHistoryProvider).where((s) => s.balance > 0).length} records', 
                style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }

  Widget _buildDebtSummary(BuildContext context, double totalDebt, int debtCount) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;
    final salesHistory = ref.watch(saleHistoryProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.account_balance_wallet, color: Colors.white, size: isMobile ? 32 : 48),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Current Total Debt', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(
                      '₵${totalDebt.toStringAsFixed(2)}',
                      style: TextStyle(color: Colors.white, fontSize: isMobile ? 24 : 32, fontWeight: FontWeight.bold),
                    ),
                    Text('Across $debtCount pending transactions', style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
              ),
              if (!isMobile)
                ElevatedButton.icon(
                  onPressed: () {
                    if (_showPaidInvoices) {
                      final clearedDebts = salesHistory.where((s) => 
                        s.balance <= 0.01 && 
                        (s.payments.length > 1 || s.payments.any((p) => p.reference?.contains('Collection') ?? false))
                      ).toList();
                      ReceiptService.printPaidInvoicesReport(clearedDebts);
                    } else {
                      ReceiptService.printDebtReport(salesHistory.where((s) => s.balance > 0).toList());
                    }
                  },
                  icon: const Icon(Icons.picture_as_pdf),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: theme.colorScheme.primary),
                  label: Text(_showPaidInvoices ? 'Cleared Debts Report' : 'Debt Report'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            height: 120,
            child: _buildTrendChart(salesHistory),
          ),
          if (isMobile) ...[
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  if (_showPaidInvoices) {
                    final clearedDebts = salesHistory.where((s) => 
                      s.balance <= 0.01 && 
                      (s.payments.length > 1 || s.payments.any((p) => p.reference?.contains('Collection') ?? false))
                    ).toList();
                    ReceiptService.printPaidInvoicesReport(clearedDebts);
                  } else {
                    ReceiptService.printDebtReport(salesHistory.where((s) => s.balance > 0).toList());
                  }
                },
                icon: const Icon(Icons.picture_as_pdf),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: theme.colorScheme.primary),
                label: Text(_showPaidInvoices ? 'Generate Cleared Debts Report' : 'Generate Debt Report'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendChart(List<SaleRecord> sales) {
    final activeSales = sales.where((s) => s.status != SaleStatus.cancelled).toList();
    if (activeSales.isEmpty) return const Center(child: Text('No debt data for trend', style: TextStyle(color: Colors.white54)));

    // Group debt by day for the last 7 days
    final now = DateTime.now();
    final last7Days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    
    double maxDebt = 0;
    final spots = last7Days.asMap().entries.map((entry) {
      final date = entry.value;
      final totalDebtOnDay = activeSales
          .where((s) => s.timestamp.year == date.year && s.timestamp.month == date.month && s.timestamp.day == date.day)
          .fold(0.0, (sum, s) => sum + (s.balance > 0.01 ? s.balance : 0));
      
      if (totalDebtOnDay > maxDebt) maxDebt = totalDebtOnDay;
      return FlSpot(entry.key.toDouble(), totalDebtOnDay);
    }).toList();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Colors.white,
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '₵${s.y.toStringAsFixed(2)}',
              const TextStyle(color: AppColors.primaryMaroon, fontWeight: FontWeight.bold, fontSize: 12),
            )).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (val, meta) {
                final index = val.toInt();
                if (index >= 0 && index < 7) {
                  final date = last7Days[index];
                  return Text(
                    DateFormat('E').format(date).toUpperCase(), 
                    style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.bold)
                  );
                }
                return const Text('');
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 0,
        maxY: maxDebt == 0 ? 100 : maxDebt * 1.5, // Give some headroom
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: Colors.white,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 4,
                color: AppColors.primaryMaroon,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.3),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtTile(BuildContext context, SaleRecord sale) {
    final theme = Theme.of(context);
    final isPaid = sale.balance <= 0.01;
    final ageInDays = DateTime.now().difference(sale.timestamp).inDays;
    
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: BorderSide(color: isPaid ? Colors.green.withValues(alpha: 0.2) : theme.dividerColor),
      ),
      elevation: 0,
      borderOnForeground: true,
      child: ListTile(
        contentPadding: const EdgeInsets.all(AppSpacing.m),
        leading: CircleAvatar(
          backgroundColor: isPaid ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
          child: Icon(isPaid ? Icons.check_circle_outline : Icons.person, color: isPaid ? Colors.green : Colors.orange),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                sale.customerName ?? 'Walk-in Customer', 
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!isPaid && ageInDays > 7)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text('Overdue', style: TextStyle(color: Colors.red.shade800, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice: ${sale.id} • ${DateFormat('MMM dd, HH:mm').format(sale.timestamp)}', 
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (sale.customerPhone != null)
              Text('Phone: ${sale.customerPhone}', style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: SizedBox(
          width: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(isPaid ? 'Fully Paid' : 'Balance Due', 
                style: TextStyle(fontSize: 9, color: isPaid ? Colors.green : theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.right,
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₵${sale.balance.toStringAsFixed(2)}',
                  style: TextStyle(color: isPaid ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        onTap: () => _showCollectionDialog(context, sale),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Theme.of(context).disabledColor),
          const SizedBox(height: 16),
          Text('No matching records found.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
          Text('Try adjusting your search or filters.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  void _showCollectionDialog(BuildContext context, SaleRecord sale) {
    final theme = Theme.of(context);
    final amountController = TextEditingController();
    bool isSaving = false;
    final isPaid = sale.balance <= 0.01;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 450,
            color: theme.colorScheme.surface,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Modern Header
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    color: theme.colorScheme.primary.withValues(alpha: 0.05),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                          child: Icon(
                            isPaid ? Icons.check_circle_outline : Icons.payments_outlined, 
                            color: theme.colorScheme.primary
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isPaid ? 'Transaction Completed' : 'Record Collection',
                                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Invoice #${sale.id.substring(sale.id.length - 8).toUpperCase()}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (sale.customerPhone != null && !isPaid)
                          IconButton.filledTonal(
                            onPressed: () {
                              final currentBranch = ref.read(currentBranchProvider);
                              final String? branchName = currentBranch != null 
                                  ? '${currentBranch.name} (${currentBranch.location})' 
                                  : null;
                              
                              SmsService.sendDebtReminderSms(sale, branchName: branchName);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Reminder sent to customer!'))
                              );
                            },
                            icon: const Icon(Icons.sms_outlined),
                            tooltip: 'Send SMS Reminder',
                          ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Financial Summary Blocks
                        Row(
                          children: [
                            _summaryBlock('Total Bill', '₵${sale.totalAmount.toStringAsFixed(2)}', Colors.blue, theme),
                            const SizedBox(width: AppSpacing.s),
                            _summaryBlock('Paid', '₵${(sale.totalAmount - sale.balance).toStringAsFixed(2)}', Colors.green, theme),
                            const SizedBox(width: AppSpacing.s),
                            _summaryBlock('Balance', '₵${sale.balance.toStringAsFixed(2)}', Colors.red, theme, isProminent: true),
                          ],
                        ),
                        
                        const SizedBox(height: AppSpacing.l),
                        
                        // Customer Details Section
                        Text('CUSTOMER INFORMATION', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.s),
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.m),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(AppRadius.m),
                            border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            children: [
                              _infoRow(Icons.person_outline, 'Name', sale.customerName ?? 'Guest Customer', theme),
                              const Divider(height: 16),
                              _infoRow(Icons.phone_outlined, 'Phone', sale.customerPhone ?? 'No Contact', theme),
                              const Divider(height: 16),
                              _infoRow(Icons.calendar_today_outlined, 'Date', DateFormat('MMM dd, yyyy HH:mm').format(sale.timestamp), theme),
                            ],
                          ),
                        ),

                        if (!isPaid) ...[
                          const SizedBox(height: AppSpacing.l),
                          Text('RECORD NEW PAYMENT', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                          const SizedBox(height: AppSpacing.s),
                          TextField(
                            controller: amountController,
                            autofocus: true,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9.,]*$'))],
                            decoration: InputDecoration(
                              hintText: 'Enter amount...',
                              prefixIcon: const Icon(Icons.add_card),
                              prefixText: '₵ ',
                              filled: true,
                              fillColor: theme.colorScheme.primary.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.m),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.m),
                                borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                              ),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ],

                        const SizedBox(height: AppSpacing.l),
                        Text('PAYMENT HISTORY', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                        const SizedBox(height: AppSpacing.s),
                        if (sale.payments.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No payments recorded.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                          )
                        else
                          ...sale.payments.map((p) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(AppRadius.s),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.history, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.method.name.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                      Text(p.reference ?? "Direct Payment", style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                Text('₵${p.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                          )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context), 
              child: Text(isPaid ? 'Close' : 'Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
            ),
            if (!isPaid)
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  final amountText = amountController.text.replaceAll(',', '.');
                  final amount = double.tryParse(amountText) ?? 0;
                  if (amount <= 0) return;
                  if (amount > sale.balance + 0.01) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Amount exceeds balance.')));
                    return;
                  }
                  
                  setState(() => isSaving = true);
                  
                  try {
                    final newPayment = PaymentDetail(
                      method: PaymentMethod.cash, 
                      amount: amount,
                      reference: 'Manual Collection ${DateFormat('yyMMdd').format(DateTime.now())}',
                    );
                    
                    final updatedPayments = [...sale.payments, newPayment];
                    final updatedSale = sale.copyWith(
                      payments: updatedPayments,
                    );

                    await ref.read(saleHistoryProvider.notifier).updateSale(updatedSale);
                    
                    // Send specialized Debt Payment SMS
                    if (sale.customerPhone != null) {
                      await SmsService.sendDebtPaymentSms(
                        phone: sale.customerPhone!,
                        name: sale.customerName ?? 'Valued Customer',
                        invoiceId: sale.id,
                        amountPaid: amount,
                        remainingBalance: updatedSale.balance,
                      );
                    }
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Payment of ₵${amount.toStringAsFixed(2)} recorded! SMS sent.'), 
                          backgroundColor: Colors.green,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentGreen, 
                  foregroundColor: Colors.white,
                  minimumSize: const Size(140, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
                ),
                child: isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Record Payment'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryBlock(String label, String value, Color color, ThemeData theme, {bool isProminent = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s, horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isProminent ? color.withValues(alpha: 0.05) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(
            color: isProminent ? color.withValues(alpha: 0.3) : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isProminent ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(
                fontSize: isProminent ? 15 : 13, 
                fontWeight: FontWeight.bold, 
                color: isProminent ? color : theme.colorScheme.onSurface
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
              Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
