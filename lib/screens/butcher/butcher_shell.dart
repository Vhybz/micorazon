import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../services/sms_service.dart';
import '../../services/notification_service.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../models/user_model.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/birthday_service.dart';
import '../../widgets/passcode_guard.dart';
import 'butcher_dashboard.dart';
import 'animal_intake_screen.dart';
import 'slaughter_log_screen.dart';
import 'meat_processing_screen.dart';
import 'stock_transfer_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
import 'waste_management_screen.dart';
import 'documents_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'carcass_breakdown_screen.dart';
import '../profile_screen.dart';
import 'how_to_use_screen.dart';
import 'butcher_expense_screen.dart';
import 'batch_management_screen.dart';

class ButcherShell extends ConsumerWidget {
  const ButcherShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    // Check for Birthday
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        BirthdayService.checkAndShowBirthdayWish(context, user);
      }
    });

    // Instant Permission Guard: Redirect to Login/Admin if access is revoked
    final roles = user.activeRoles;
    final hasAccess = roles.contains(UserRole.butcher) || roles.contains(UserRole.superAdmin) || user.enabledPermissions.contains('/butcher');
    
    if (!hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final currentScreen = ref.watch(butcherNavProvider);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final menuItems = ref.watch(butcherMenuItemsProvider);

    return RolePopScope(
      currentRoute: '/butcher',
      child: PopScope(
        canPop: currentScreen == ButcherScreen.dashboard,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (currentScreen != ButcherScreen.dashboard) {
            ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.dashboard);
          }
        },
        child: PasscodeGuard(
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: MainAppBar(
              title: _getScreenTitle(currentScreen),
              onProfileTap: () => ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.profile),
              actions: [
                IconButton(
                  icon: const Icon(Icons.report_gmailerrorred_rounded, color: Colors.orange),
                  tooltip: 'Report Issue to Admin',
                  onPressed: () => _showButcherReportDialog(context, ref),
                ),
              ],
            ),
            drawer: isDesktop ? null : Drawer(child: _buildSidebar(ref, currentScreen, user, context, menuItems)),
            body: Row(
              children: [
                if (isDesktop) _buildSidebar(ref, currentScreen, user, context, menuItems),
                Expanded(
                  child: Container(
                    color: theme.scaffoldBackgroundColor,
                    child: SafeArea(
                      top: false,
                      bottom: true,
                      child: _buildContent(currentScreen),
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

  String _getScreenTitle(ButcherScreen screen) {
    switch (screen) {
      case ButcherScreen.dashboard: return 'Butcher Dashboard';
      case ButcherScreen.animalIntake: return 'Animal Intake';
      case ButcherScreen.slaughterLog: return 'Slaughter Logs';
      case ButcherScreen.meatProcessing: return 'Meat Processing';
      case ButcherScreen.stockTransfer: return 'Stock Transfer';
      case ButcherScreen.inventory: return 'Butcher Inventory';
      case ButcherScreen.orders: return 'Processing Orders';
      case ButcherScreen.wasteManagement: return 'Waste Management';
      case ButcherScreen.documents: return 'Documents & Compliance';
      case ButcherScreen.reports: return 'Operational Reports';
      case ButcherScreen.expenses: return 'Unit Expenses';
      case ButcherScreen.settings: return 'Workstation Settings';
      case ButcherScreen.profile: return 'Personal Profile';
      case ButcherScreen.howToUse: return 'How to Use System';
      case ButcherScreen.carcassBreakdown: return 'Carcass Breakdown Station';
      case ButcherScreen.batchManagement: return 'Batch Management Hub';
    }
  }

  Widget _buildSidebar(WidgetRef ref, ButcherScreen current, UserAccount user, BuildContext context, List<SidebarItem> menuItems) {
    const currentRoute = '/butcher';
    return AppSidebar(
      userId: user.id,
      userName: user.name,
      userRole: user.activePrimaryRole.name.toUpperCase(),
      currentRoute: _getCurrentInternalRoute(current),
      items: menuItems,
      onTap: (route) {
        if (route.startsWith('butcher:')) {
          final screenStr = route.split(':')[1];
          final screen = ButcherScreen.values.byName(screenStr);
          ref.read(butcherNavProvider.notifier).setScreen(screen);
        } else {
          MenuService.navigate(context, route, currentRoute);
        }
      },
    );
  }

  String _getCurrentInternalRoute(ButcherScreen current) {
    return 'butcher:${current.name}';
  }

  Widget _buildContent(ButcherScreen screen) {
    switch (screen) {
      case ButcherScreen.dashboard: return ButcherDashboard();
      case ButcherScreen.animalIntake: return AnimalIntakeScreen();
      case ButcherScreen.slaughterLog: return SlaughterLogScreen();
      case ButcherScreen.meatProcessing: return MeatProcessingScreen();
      case ButcherScreen.stockTransfer: return StockTransferScreen();
      case ButcherScreen.inventory: return InventoryScreen();
      case ButcherScreen.orders: return OrdersScreen();
      case ButcherScreen.wasteManagement: return WasteManagementScreen();
      case ButcherScreen.expenses: return ButcherExpenseScreen();
      case ButcherScreen.documents: return DocumentsScreen(isNested: true);
      case ButcherScreen.reports: return ReportsScreen();
      case ButcherScreen.settings: return SettingsScreen();
      case ButcherScreen.profile: return ProfileView();
      case ButcherScreen.howToUse: return HowToUseScreen();
      case ButcherScreen.carcassBreakdown: return CarcassBreakdownScreen();
      case ButcherScreen.batchManagement: return BatchManagementScreen();
    }
  }

  void _showButcherReportDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Issue to Admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reporting equipment failure, stock discrepancies, or safety issues will immediately alert the Administrator via SMS.', 
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Describe the issue...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                final user = ref.read(currentUserProvider);
                final userName = user?.name ?? 'Butcher';
                
                // Simulate SMS and Notification
                await SmsService.notifyAdmin(
                  title: 'BUTCHER UNIT ALERT',
                  message: '$userName reported an issue: ${controller.text}',
                );

                ref.read(notificationProvider.notifier).addNotification(
                  'BUTCHER UNIT ALERT',
                  '$userName reported an issue: ${controller.text}',
                );
                
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Report sent. Admin notified via SMS.'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Send Urgent Report'),
          ),
        ],
      ),
    );
  }
}
