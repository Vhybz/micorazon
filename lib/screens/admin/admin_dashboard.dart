import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/main_app_bar.dart';
import 'package:intl/intl.dart';
import '../../services/sale_provider.dart';
import '../../services/expense_provider.dart';
import '../../models/sale_model.dart';
import '../../services/notification_service.dart';
import '../../services/product_service.dart';
import '../../services/butcher_service.dart';
import '../../models/butcher_models.dart';
import '../../models/system_models.dart';

import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../models/user_model.dart';
import '../../models/branch_model.dart';
import '../../services/branch_provider.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/report_service.dart';
import '../../services/birthday_service.dart';
import '../../widgets/passcode_guard.dart';

class AdminDashboard extends ConsumerStatefulWidget {
  const AdminDashboard({super.key});

  @override
  ConsumerState<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends ConsumerState<AdminDashboard> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _timer;

  final List<String> _bannerImages = [
    'assets/images/meat_art.jpg',
    'assets/images/cow_art.jpg',
    'assets/images/pork_art.jpg',
    'assets/images/cow_art2.jpg',
    'assets/images/butcher_cow.jpg',
    'assets/images/meat_on_scale.jpg',
    'assets/images/cow.jpg',
    'assets/images/pork.jpg',
    'assets/images/chicken.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients) {
        _currentPage = (_currentPage + 1) % _bannerImages.length;
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    // Check for Birthday
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        BirthdayService.checkAndShowBirthdayWish(context, user);
      }
    });

    // Instant Permission Guard: Redirect if admin access is revoked
    final roles = user.activeRoles;
    final hasAccess = roles.contains(UserRole.admin) || roles.contains(UserRole.superAdmin) || user.enabledPermissions.contains('/admin');
    
    if (!hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDesktop = ResponsiveLayout.isDesktop(context);
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(now);
    const currentRoute = '/admin';
    final menuItems = ref.watch(menuItemsProvider);
    final currentBranch = ref.watch(currentBranchProvider);

    return RolePopScope(
      currentRoute: currentRoute,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // Since Admin pages are separate routes, standard back button 
          // already goes back to this dashboard. 
          // If we are already here, we stay here.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use the menu to logout or switch accounts'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: PasscodeGuard(
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: const MainAppBar(title: 'Admin Command Center'),
            drawer: isDesktop
                ? null
                : Drawer(
                    child: AppSidebar(
                      userId: user.id,
                      userName: user.name,
                      userRole: user.activePrimaryRole.toString().split('.').last.toUpperCase(),
                      currentRoute: currentRoute,
                      items: menuItems,
                      onTap: (route) => MenuService.navigate(context, route, currentRoute),
                    ),
                  ),
            body: Row(
              children: [
                if (isDesktop)
                  AppSidebar(
                    userId: user.id,
                    userName: user.name,
                    userRole: user.activePrimaryRole.toString().split('.').last.toUpperCase(),
                    currentRoute: currentRoute,
                    items: menuItems,
                    onTap: (route) => MenuService.navigate(context, route, currentRoute),
                  ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    bottom: true,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context, dateStr, user, currentBranch),
                          const SizedBox(height: AppSpacing.l),
                          _buildBanner(context),
                          const SizedBox(height: AppSpacing.xl),
                          _buildKPIGrid(context, ref),
                          const SizedBox(height: AppSpacing.xl),
                          _buildPendingActions(context, ref),
                          const SizedBox(height: AppSpacing.xl),
                          _buildResponsiveMainContent(context, ref),
                          const SizedBox(height: AppSpacing.xl),
                          _buildInventoryMonitor(context, ref),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingActions(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(saleHistoryProvider);
    final saleRequests = sales.where((s) => s.status == SaleStatus.pendingCorrection).toList();
    
    final notifications = ref.watch(notificationProvider);
    final butcherReports = notifications.where((n) => n.title.contains('BUTCHER') && !n.isRead).toList();

    if (saleRequests.isEmpty && butcherReports.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (saleRequests.isNotEmpty) ...[
          _buildActionSection(
            context,
            ref,
            title: 'Sale Correction Requests',
            icon: Icons.receipt_long,
            color: Colors.orange,
            items: saleRequests,
            onAction: (sale) => _showRectifySaleDialog(context, ref, sale),
          ),
          const SizedBox(height: AppSpacing.l),
        ],
        if (butcherReports.isNotEmpty) ...[
          _buildActionSection(
            context,
            ref,
            title: 'Butcher Unit Reports',
            icon: Icons.warning_amber_rounded,
            color: Colors.red,
            items: butcherReports,
            onAction: (report) => _showRectifyButcherReportDialog(context, ref, report),
          ),
        ],
      ],
    );
  }

  Widget _buildActionSection(
    BuildContext context, 
    WidgetRef ref, 
    {required String title, required IconData icon, required Color color, required List items, required Function(dynamic) onAction}
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.l),
        border: Border.all(color: color.withValues(alpha: isDark ? 0.3 : 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Text(
                '$title (${items.length})',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              String displayTitle = '';
              String displaySubtitle = '';
              
              if (item is SaleRecord) {
                displayTitle = 'Mistake in Sale ${item.id}';
                displaySubtitle = 'Reported by ${item.cashierName}: ${item.correctionReason}';
              } else if (item is SystemNotification) {
                displayTitle = item.title;
                displaySubtitle = item.message;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: theme.cardTheme.color,
                child: ListTile(
                  title: Text(displayTitle, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  subtitle: Text(displaySubtitle, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmDeleteAction(context, ref, item),
                        tooltip: 'Delete/Dismiss',
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => onAction(item),
                        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
                        child: const Text('Rectify'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAction(BuildContext context, WidgetRef ref, dynamic item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Text('Confirm Deletion'),
        content: Text(item is SaleRecord 
          ? 'Are you sure you want to CANCEL this sale completely? This action is irreversible.'
          : 'Are you sure you want to DISMISS this butcher report?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go Back')),
          ElevatedButton(
            onPressed: () {
              if (item is SaleRecord) {
                ref.read(saleHistoryProvider.notifier).updateSale(item.copyWith(status: SaleStatus.cancelled));
              } else if (item is SystemNotification) {
                ref.read(notificationProvider.notifier).deleteNotification(item.id);
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Action deleted/cancelled.')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );
  }

  void _showRectifySaleDialog(BuildContext context, WidgetRef ref, SaleRecord sale) {
    final List<SaleItem> editedItems = List.from(sale.items);
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          double calculateNewTotal() => editedItems.fold(0, (sum, item) => sum + item.total);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: Text('Rectify Sale ${sale.id}'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Cashier Report: ${sale.correctionReason}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Edit Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    ...editedItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.product.name, style: const TextStyle(fontSize: 12))),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: item.quantity.toString(),
                                decoration: const InputDecoration(suffixText: 'kg', isDense: true),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 12),
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
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Original Total:', style: TextStyle(fontSize: 12)),
                        Text('₵${sale.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Corrected Total:', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('₵${calculateNewTotal().toStringAsFixed(2)}', 
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final newTotal = calculateNewTotal();
                  final rectifiedSale = sale.copyWith(
                    items: editedItems,
                    totalAmount: newTotal,
                    status: SaleStatus.rectified,
                  );
                  
                  // Update State (Future Supabase Update)
                  ref.read(saleHistoryProvider.notifier).updateSale(rectifiedSale);
                  
                  // Notify Cashier
                  ref.read(notificationProvider.notifier).addNotification(
                    'SALE RECTIFIED',
                    'Sale ${sale.id} has been rectified by Admin. Please reprint receipt for customer.',
                  );

                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sale ${sale.id} rectified. Cashier notified.'),
                      backgroundColor: AppColors.accentGreen,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
                child: const Text('Save & Notify Cashier'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRectifyButcherReportDialog(BuildContext context, WidgetRef ref, SystemNotification report) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Text('Rectify Butcher Issue'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reported: ${report.message}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Resolution Action',
                hintText: 'e.g., Equipment repaired, Stock replenished',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref.read(notificationProvider.notifier).markAsRead(report.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Butcher report resolved and archived.'), backgroundColor: AppColors.accentGreen),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentGreen, foregroundColor: Colors.white),
            child: const Text('Mark as Resolved'),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = ResponsiveLayout.isMobile(context);

    return Container(
      width: double.infinity,
      height: isMobile ? 160 : 200, 
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.l),
        child: Stack(
          children: [
            // Image Carousel
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemCount: _bannerImages.length,
              itemBuilder: (context, index) {
                return Image.asset(
                  _bannerImages[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              },
            ),
            
            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            
            // Text Content
            Padding(
              padding: EdgeInsets.all(isMobile ? AppSpacing.m : AppSpacing.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'PREMIUM SELECTION',
                      style: TextStyle(color: Colors.white, fontSize: isMobile ? 8 : 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Uncompromising Quality',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 22 : 28,
                          fontWeight: FontWeight.bold,
                          shadows: const [Shadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 2))],
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Unforgettable Taste from Mi~Corazon',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isMobile ? 12 : 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            // Carousel Indicators
            Positioned(
              bottom: 16,
              right: 24,
              child: Row(
                children: List.generate(_bannerImages.length, (index) {
                  return Container(
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: _currentPage == index ? theme.colorScheme.primary : Colors.white54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String dateStr, UserAccount user, Branch? branch) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final theme = Theme.of(context);
    
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome, ${user.firstName}',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (branch != null)
             Text('${branch.name} - ${branch.location}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Text(dateStr, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: AppSpacing.m),
          _buildActionButtons(context, isMobile),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back, ${user.firstName}',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (branch != null)
                 Text('${branch.name} - ${branch.location}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(dateStr, 
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _buildActionButtons(context, false),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, bool isMobile) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.s,
      runSpacing: AppSpacing.s,
      children: [
        ElevatedButton.icon(
          onPressed: () => _showExportReportDialog(context),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Export PDF'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.cardTheme.color,
            foregroundColor: theme.colorScheme.primary,
            side: BorderSide(color: theme.colorScheme.primary),
            elevation: 0,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20, 
              vertical: isMobile ? 10 : 15
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _handleQuickAddStaff(context),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Staff'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 2,
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20, 
              vertical: isMobile ? 10 : 15
            ),
          ),
        ),
      ],
    );
  }

  void _handleQuickAddStaff(BuildContext context) {
    // Navigate to staff management and use the callback to open dialog
    Navigator.pushReplacementNamed(context, '/admin/staff');
    // Note: In a real app, we might pass a flag in arguments to auto-open the dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Opening Staff Registration...'), duration: Duration(seconds: 1)),
    );
  }

  void _showExportReportDialog(BuildContext context) {
    final theme = Theme.of(context);
    final searchController = TextEditingController();
    
    final List<Map<String, dynamic>> reports = [
      {'title': 'Daily Sales Report', 'desc': 'Detailed list of all transactions today', 'icon': Icons.point_of_sale, 'cat': 'Financial'},
      {'title': 'Monthly Revenue Summary', 'desc': 'Financial overview for the current month', 'icon': Icons.account_balance, 'cat': 'Financial'},
      {'title': 'Inventory Audit', 'desc': 'Stock levels and low-stock warnings', 'icon': Icons.inventory_2, 'cat': 'Stock'},
      {'title': 'Slaughter & Yield Log', 'desc': 'Operational efficiency and carcass records', 'icon': Icons.precision_manufacturing, 'cat': 'Production'},
      {'title': 'Staff Performance', 'desc': 'Individual sales and processing metrics', 'icon': Icons.badge, 'cat': 'Staff'},
      {'title': 'Customer Debt Statement', 'desc': 'Outstanding balances and payment history', 'icon': Icons.money_off, 'cat': 'Customers'},
      {'title': 'Business Expense Ledger', 'desc': 'Categorized operational costs', 'icon': Icons.receipt_long, 'cat': 'Financial'},
      {'title': 'Meat Breakdown Analysis', 'desc': 'Detailed cuts and waste percentages', 'icon': Icons.restaurant, 'cat': 'Production'},
      {'title': 'Operational Reports', 'desc': 'Combined view of workstation logs', 'icon': Icons.assignment, 'cat': 'General'},
      {'title': 'System Audit Log', 'desc': 'Record of administrative changes', 'icon': Icons.history_edu, 'cat': 'Security'},
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final query = searchController.text.toLowerCase();
          final filteredReports = reports.where((r) => 
            r['title'].toLowerCase().contains(query) ||
            r['desc'].toLowerCase().contains(query) ||
            r['cat'].toLowerCase().contains(query)
          ).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: const EdgeInsets.all(AppSpacing.l),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.l)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(child: Text('Generate Report PDF', style: TextStyle(color: Colors.white, fontSize: 18))),
                ],
              ),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchController,
                      onChanged: (v) => setState(() {}),
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by title, category or description...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: query.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                          searchController.clear();
                          setState(() {});
                        }) : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(AppRadius.s),
                        ),
                        child: filteredReports.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(40), child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 48, color: Colors.grey),
                                SizedBox(height: 12),
                                Text('No matching reports found.', style: TextStyle(color: Colors.grey)),
                              ],
                            )))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filteredReports.length,
                              separatorBuilder: (context, index) => Divider(height: 1, color: theme.dividerColor),
                              itemBuilder: (context, index) {
                                final r = filteredReports[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(r['icon'], color: theme.colorScheme.primary, size: 20),
                                  ),
                                  title: Text(r['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: Text(r['desc'], style: const TextStyle(fontSize: 10), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.download_for_offline, size: 18, color: Colors.green),
                                      const SizedBox(height: 2),
                                      Text(r['cat'].toUpperCase(), style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  onTap: () async {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Generating ${r['title']}... Please wait.'),
                                        backgroundColor: AppColors.accentGreen,
                                      ),
                                    );
                                    
                                    try {
                                      if (r['title'] == 'Daily Sales Report') {
                                        final sales = ref.read(saleHistoryProvider);
                                        await ReportService.generateDailySalesReport(sales, DateTime.now());
                                      } else if (r['title'] == 'Monthly Revenue Summary') {
                                        final sales = ref.read(saleHistoryProvider);
                                        await ReportService.generateMonthlyRevenueSummary(sales, DateTime.now());
                                      } else if (r['title'] == 'Inventory Audit') {
                                        final products = ref.read(productsFutureProvider).value ?? [];
                                        await ReportService.generateInventoryAudit(products);
                                      } else if (r['title'] == 'Slaughter & Yield Log') {
                                        final logs = ref.read(slaughterLogsProvider).value ?? [];
                                        await ReportService.generateSlaughterLogReport(logs);
                                      } else if (r['title'] == 'Business Expense Ledger') {
                                        final expenses = ref.read(expenseProvider).records;
                                        await ReportService.generateExpenseLedger(expenses);
                                      } else if (r['title'] == 'Customer Debt Statement') {
                                        final sales = ref.read(saleHistoryProvider);
                                        await ReportService.generateCustomerDebtStatement(sales);
                                      } else if (r['title'] == 'Meat Breakdown Analysis') {
                                        final cuts = ref.read(recentCutsProvider).value ?? [];
                                        await ReportService.generateMeatBreakdownAnalysis(cuts);
                                      } else if (r['title'] == 'Staff Performance') {
                                        final sales = ref.read(saleHistoryProvider);
                                        final staff = ref.read(userProvider);
                                        await ReportService.generateStaffPerformanceReport(sales, staff);
                                      } else {
                                        // Default placeholder for other reports
                                        await Future.delayed(const Duration(seconds: 1));
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('This report type is coming soon in the next update!')),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error generating report: $e'), backgroundColor: Colors.red),
                                        );
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('Close Window', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKPIGrid(BuildContext context, WidgetRef ref) {
    final bool isMobile = ResponsiveLayout.isMobile(context);
    final bool isTablet = ResponsiveLayout.isTablet(context);
    
    final now = DateTime.now();
    final allSales = ref.watch(saleHistoryProvider);
    
    // Monthly Reset Logic: Filter all core metrics by current month
    final sales = allSales.where((s) => 
      s.status != SaleStatus.cancelled && 
      s.timestamp.month == now.month && 
      s.timestamp.year == now.year
    ).toList();
    
    final logsAsync = ref.watch(slaughterLogsProvider);
    final todayLogs = logsAsync.value?.where((l) {
      final date = l.slaughterTime ?? now;
      return date.day == now.day && date.month == now.month && date.year == now.year;
    }).toList() ?? [];

    final totalRevenue = sales.where((s) => s.isActive).fold(0.0, (sum, sale) => sum + sale.totalAmount);
    final totalCost = sales.where((s) => s.isActive).fold(0.0, (sum, sale) => sum + sale.totalCost);
    final grossProfit = totalRevenue - totalCost;
    
    // Total Debt should reflect all-time outstanding balance, not just the current month
    final totalDebt = allSales.where((s) => s.isActive)
        .fold(0.0, (sum, sale) => sum + (sale.balance > 0 ? sale.balance : 0));

    final totalDiscounts = sales.fold(0.0, (sum, sale) => sum + sale.totalDiscount);
    final totalWeightSold = sales.fold(0.0, (sum, sale) => sum + sale.totalQty);
    
    final expensesState = ref.watch(expenseProvider);
    final totalExpenses = expensesState.records.where((e) => 
      e.date.month == now.month && e.date.year == now.year
    ).fold(0.0, (sum, e) => sum + e.amount);

    final netProfit = grossProfit - totalExpenses;

    final theme = Theme.of(context);

    int crossAxisCount = isMobile ? 2 : (isTablet ? 4 : 4);
    double aspectRatio = isMobile ? 1.4 : 1.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              Flexible(
                child: Text('MONTHLY PERFORMANCE', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('(${DateFormat('MMMM').format(now).toUpperCase()})', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
            ],
          ),
        ),
        GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.m,
          mainAxisSpacing: AppSpacing.m,
          childAspectRatio: aspectRatio,
          children: [
            _kpiWithTrend(context, "Gross Sales", '₵${totalRevenue.toStringAsFixed(0)}', Icons.payments, Colors.blue, 'MONTH'),
            _kpiWithTrend(context, "Gross Profit", '₵${grossProfit.toStringAsFixed(0)}', Icons.show_chart, Colors.teal, 'MARGIN'),
            _kpiWithTrend(context, "Expenses", '₵${totalExpenses.toStringAsFixed(0)}', Icons.trending_down, Colors.red, 'MONTH'),
            _kpiWithTrend(context, 'Net Profit', '₵${netProfit.toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.green, 'MONTH'),
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        GridView.count(
          crossAxisCount: isMobile ? 2 : 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.m,
          mainAxisSpacing: AppSpacing.m,
          childAspectRatio: isMobile ? 1.4 : 1.6,
          children: [
            _kpiWithTrend(context, 'Total Debt', '₵${totalDebt.toStringAsFixed(0)}', Icons.money_off, Colors.red, 'TOTAL'),
            _kpiWithTrend(context, 'Promo Impact', '₵${totalDiscounts.toStringAsFixed(0)}', Icons.auto_awesome, Colors.orange, 'SAVED'),
            _kpiWithTrend(context, 'Stock Sold', '${totalWeightSold.toStringAsFixed(1)} kg', Icons.scale, theme.colorScheme.primary, 'LIVE'),
            _kpiWithTrend(context, 'Daily Slaughter', '${todayLogs.length}', Icons.precision_manufacturing, Colors.green, 'TODAY'),
          ],
        ),
      ],
    );
  }

  Widget _kpiWithTrend(BuildContext context, String title, String value, IconData icon, Color color, String trend) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isMobile = ResponsiveLayout.isMobile(context);
    final bool isPositive = trend.startsWith('+') || trend == 'SAVED' || trend == 'LIVE';

    return Container(
      padding: EdgeInsets.all(isMobile ? 4 : AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1), 
              borderRadius: BorderRadius.circular(AppRadius.s)
            ),
            child: Icon(icon, color: color, size: isMobile ? 14 : 22),
          ),
          SizedBox(width: isMobile ? 4 : AppSpacing.s),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: isMobile ? 8 : 10, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontSize: isMobile ? 12 : 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ),
                const SizedBox(height: 1),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isPositive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      trend,
                      style: TextStyle(
                        color: isPositive ? Colors.green : Colors.red,
                        fontSize: isMobile ? 6 : 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveMainContent(BuildContext context, WidgetRef ref) {
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final sales = ref.watch(saleHistoryProvider);
    final logsAsync = ref.watch(slaughterLogsProvider);
    
    final promoSales = sales.where((s) => s.totalDiscount > 0).toList();
    final totalImpact = promoSales.fold(0.0, (sum, s) => sum + s.totalDiscount);

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2, 
            child: Column(
              children: [
                _buildPerformanceChart(context, sales),
                const SizedBox(height: AppSpacing.l),
                logsAsync.when(
                  data: (logs) => _buildSlaughterTrendChart(context, logs),
                  loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => const Text('Error loading slaughter trend'),
                ),
              ],
            )
          ),
          const SizedBox(width: AppSpacing.l),
          Expanded(
            flex: 1, 
            child: Column(
              children: [
                _buildPromotionImpactCard(context, promoSales, totalImpact),
                const SizedBox(height: AppSpacing.l),
                _buildCriticalAlerts(context, ref),
              ],
            )
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildPerformanceChart(context, sales),
          const SizedBox(height: AppSpacing.l),
          logsAsync.when(
            data: (logs) => _buildSlaughterTrendChart(context, logs),
            loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => const Text('Error loading slaughter trend'),
          ),
          const SizedBox(height: AppSpacing.l),
          _buildPromotionImpactCard(context, promoSales, totalImpact),
          const SizedBox(height: AppSpacing.l),
          _buildCriticalAlerts(context, ref),
        ],
      );
    }
  }

  Widget _buildSlaughterTrendChart(BuildContext context, List<SlaughterLog> logs) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Group logs by day for the last 7 days
    final now = DateTime.now();
    final last7Days = List.generate(7, (index) {
      return now.subtract(Duration(days: 6 - index));
    });

    final dailyCounts = last7Days.map((date) {
      return logs.where((l) {
        final logDate = l.slaughterTime ?? DateTime.now();
        return logDate.year == date.year && logDate.month == date.month && logDate.day == date.day;
      }).length;
    }).toList();

    final maxCount = dailyCounts.isEmpty ? 10 : (dailyCounts.reduce((a, b) => a > b ? a : b) + 2);

    return Container(
      height: 350,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
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
                    Text('Slaughter Trend', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('Animals processed daily', 
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(dailyCounts.length, (index) {
                final count = dailyCounts[index];
                final date = last7Days[index];
                final double barHeight = count == 0 ? 5 : (count / maxCount) * 180;
                final isToday = index == 6;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        child: Text(count > 0 ? '$count' : '', 
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isToday ? Colors.orange : theme.colorScheme.onSurfaceVariant)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isToday ? Colors.orange : Colors.orange.withValues(alpha: 0.4),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DateFormat('E').format(date).substring(0, 1),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? Colors.orange : theme.colorScheme.onSurfaceVariant
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionImpactCard(BuildContext context, List<SaleRecord> promoSales, double totalImpact) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Promotion Analytics', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text('${promoSales.length} Active', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          Divider(height: 24, color: theme.dividerColor),
          Text('Total Revenue Impact (Money Saved for Customers)', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant), softWrap: true),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('₵ ${totalImpact.toStringAsFixed(2)}', 
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
          ),
          const SizedBox(height: 16),
          Text('Recent Promo Transactions:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 8),
          if (promoSales.isEmpty)
            Text('No promotions applied yet.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: theme.colorScheme.onSurfaceVariant))
          else
            ...promoSales.take(3).map((s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 6, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.appliedPromo ?? 'Discount', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface))),
                  Text('-₵${s.totalDiscount.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ],
              ),
            )),
        ],
      ),
    );
  }

  Widget _buildPerformanceChart(BuildContext context, List<SaleRecord> sales) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Generate data for the last 7 days
    final now = DateTime.now();
    final last7Days = List.generate(7, (index) {
      return now.subtract(Duration(days: 6 - index));
    });

    final dailyRevenue = last7Days.map((date) {
      final total = sales
          .where((s) => s.timestamp.year == date.year && 
                        s.timestamp.month == date.month && 
                        s.timestamp.day == date.day)
          .fold(0.0, (sum, s) => sum + s.totalAmount);
      return total;
    }).toList();

    final maxRevenue = dailyRevenue.reduce((a, b) => a > b ? a : b);
    final double chartMax = maxRevenue == 0 ? 1000 : maxRevenue * 1.2;

    // Top Selling Category Logic
    final categoryStats = <String, double>{};
    for (var sale in sales) {
      for (var item in sale.items) {
        categoryStats[item.product.category] = (categoryStats[item.product.category] ?? 0) + item.total;
      }
    }
    final sortedCategories = categoryStats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topCategory = sortedCategories.isEmpty ? 'N/A' : sortedCategories.first.key;

    return Container(
      height: 400,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System Analytics', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('Real-time revenue & category performance', 
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('TOP CATEGORY', 
                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(topCategory.toUpperCase(), 
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(dailyRevenue.length, (index) {
                final amount = dailyRevenue[index];
                final date = last7Days[index];
                final double barHeight = amount == 0 ? 5 : (amount / chartMax) * 230;
                final isToday = index == 6;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          amount > 0 ? '₵${amount.toStringAsFixed(0)}' : '',
                          style: TextStyle(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold, 
                            color: isToday ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: '₵${amount.toStringAsFixed(2)} on ${DateFormat('MMM dd').format(date)}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          height: barHeight,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isToday 
                                ? [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.7)]
                                : [Colors.blue.shade400, Colors.blue.shade200],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        DateFormat('E').format(date).substring(0, 1),
                        style: TextStyle(
                          fontSize: 12, 
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriticalAlerts(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final productsAsync = ref.watch(productsFutureProvider);
    final sales = ref.watch(saleHistoryProvider);
    final notifications = ref.watch(notificationProvider);
    
    // Calculate real alerts
    final lowStockItems = productsAsync.value?.where((p) => !p.isDeleted && p.stockQuantity < 10).toList() ?? [];
    final pendingCorrections = sales.where((s) => s.status == SaleStatus.pendingCorrection).toList();
    final unreadButcherReports = notifications.where((n) => n.title.contains('BUTCHER') && !n.isRead).toList();
    
    final now = DateTime.now();
    final users = ref.watch(userProvider);
    final pendingSalaries = users.where((u) {
      if (u.isDeleted || u.status != AccountStatus.approved) return false;
      if (u.salaryAmount == null || u.salaryDay == null) return false;
      if (now.day >= u.salaryDay!) {
        if (u.lastSalaryDate == null) return true;
        if (u.lastSalaryDate!.month != now.month || u.lastSalaryDate!.year != now.year) return true;
      }
      return false;
    }).toList();

    return Container(
      height: 400,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notification_important, color: Colors.red, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('System Alerts', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              if (lowStockItems.length + pendingCorrections.length + unreadButcherReports.length + pendingSalaries.length > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '${lowStockItems.length + pendingCorrections.length + unreadButcherReports.length + pendingSalaries.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          Expanded(
            child: (lowStockItems.isEmpty && pendingCorrections.isEmpty && unreadButcherReports.isEmpty && pendingSalaries.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 48, color: Colors.green.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        Text('System healthy. No urgent alerts.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      if (pendingSalaries.isNotEmpty)
                        _alertTile(
                          context,
                          'Payroll Due', 
                          '${pendingSalaries.length} staff members are due for salary payment.', 
                          Colors.purple, 
                          Icons.payments_rounded,
                          onTap: () => Navigator.pushNamed(context, '/admin/salaries'),
                        ),
                      ...pendingCorrections.map((s) => _alertTile(
                        context,
                        'Sale Correction Req', 
                        'Invoice ${s.id} reported by ${s.cashierName}', 
                        Colors.orange, 
                        Icons.receipt_long
                      )),
                      ...unreadButcherReports.map((n) => _alertTile(
                        context,
                        'Butcher Unit Report', 
                        n.message, 
                        Colors.red, 
                        Icons.warning_amber
                      )),
                      ...lowStockItems.map((p) => _alertTile(
                        context,
                        'Low Stock Alert', 
                        '${p.name} is critically low (${p.stockQuantity}${p.unit} left).', 
                        Colors.red.shade700, 
                        Icons.inventory_2
                      )),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _alertTile(BuildContext context, String title, String subtitle, Color color, IconData icon, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.m),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.m),
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryMonitor(BuildContext context, WidgetRef ref) {
    final isMobile = ResponsiveLayout.isMobile(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final productsAsync = ref.watch(productsFutureProvider);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Critical Stock Monitoring', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface)),
          const SizedBox(height: AppSpacing.l),
          productsAsync.when(
            data: (products) {
              final criticalStock = products
                  .where((p) => !p.isDeleted)
                  .toList()
                ..sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
              
              final top3 = criticalStock.take(3).toList();
              
              if (top3.isEmpty) return Text('No stock data available.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant));

              return isMobile
                  ? Column(
                      children: top3.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.m),
                        child: _stockIndicator(context, p.name, (p.stockQuantity / 100).clamp(0.0, 1.0), p.stockQuantity < 10 ? Colors.red : Colors.orange),
                      )).toList(),
                    )
                  : Row(
                      children: top3.map((p) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.l),
                          child: _stockIndicator(context, p.name, (p.stockQuantity / 100).clamp(0.0, 1.0), p.stockQuantity < 10 ? Colors.red : Colors.orange),
                        ),
                      )).toList(),
                    );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, error) => const Text('Error loading stock levels.'),
          ),
        ],
      ),
    );
  }

  Widget _stockIndicator(BuildContext context, String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text('${(value * 100).toInt()}%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: value,
          backgroundColor: color.withValues(alpha: 0.1),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}
