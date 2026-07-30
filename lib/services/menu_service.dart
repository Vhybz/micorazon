import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/app_sidebar.dart';
import '../models/user_model.dart';
import 'user_provider.dart';
import 'transfer_provider.dart';

class MenuService {
  static List<SidebarItem> getMenuItemsForUser(UserAccount user, {bool inButcherShell = false, int? pendingTransfersCount}) {
    final List<SidebarItem> items = [];
    final roles = user.activeRoles;
    
    // Check if user is Admin or Super Admin
    final isAdmin = roles.contains(UserRole.admin) || roles.contains(UserRole.superAdmin);

    // List of all possible admin items
    final List<SidebarItem> adminItems = [
      SidebarItem(icon: Icons.dashboard_rounded, label: 'Admin Dashboard', route: '/admin'),
      SidebarItem(icon: Icons.admin_panel_settings_rounded, label: 'Staff Management', route: '/admin/staff'),
      SidebarItem(icon: Icons.bar_chart_rounded, label: 'Sales Analytics', route: '/admin/sales'),
      SidebarItem(icon: Icons.inventory_2_rounded, label: 'Master Stock Control', route: '/admin/stock'),
      SidebarItem(icon: Icons.account_balance_wallet_rounded, label: 'Debt Tracker', route: '/admin/debts'),
      SidebarItem(icon: Icons.receipt_long_rounded, label: 'Business Expenses', route: '/admin/expenses'),
      SidebarItem(icon: Icons.people_outline_rounded, label: 'Customer Directory', route: '/admin/customers'),
      SidebarItem(icon: Icons.account_balance_rounded, label: 'GRA Tax Compliance', route: '/admin/tax'),
      SidebarItem(icon: Icons.payments_rounded, label: 'Salary Management', route: '/admin/salaries'),
      SidebarItem(icon: Icons.folder_open_rounded, label: 'Compliance Documents', route: '/admin/documents'),
      SidebarItem(icon: Icons.history_rounded, label: 'Company Recents', route: '/admin/recents'),
      SidebarItem(icon: Icons.security_update_good_rounded, label: 'System Audit Trail', route: '/admin/audit'),
      SidebarItem(icon: Icons.qr_code_scanner_rounded, label: 'Verify Incoming Stock', route: '/cashier/verify-stock'),
      SidebarItem(icon: Icons.build_circle_rounded, label: 'System Maintenance', route: '/admin/maintenance'),
    ];

    // 1. Admin Module
    if (roles.contains(UserRole.superAdmin) || isAdmin) {
      for (final item in adminItems) {
        // Super Admins always see everything.
        if (roles.contains(UserRole.superAdmin)) {
          items.add(SidebarItem(
            icon: item.icon,
            label: item.label,
            route: item.route,
            isCatchy: user.newlyAddedPermissions.contains(item.route),
            badgeCount: item.route == '/cashier/verify-stock' ? pendingTransfersCount : null,
          ));
          continue;
        }

        // Logic for regular Admin:
        // Always show standard tools, show others if not restricted.
        final bool isSystemTool = item.route == '/admin' || 
                                  item.route == '/admin/tax' ||
                                  item.route == '/admin/documents' ||
                                  item.route == '/admin/salaries' ||
                                  item.route == '/admin/staff' ||
                                  item.route == '/admin/recents' || 
                                  item.route == '/admin/audit' || 
                                  item.route == '/admin/maintenance' ||
                                  item.route == '/admin/settings';
        
        final hasSpecificRestrictions = user.enabledPermissions.isNotEmpty && 
                                         user.enabledPermissions.any((p) => p.startsWith('/admin'));

        if (isSystemTool || !hasSpecificRestrictions || user.enabledPermissions.contains(item.route)) {
          items.add(SidebarItem(
            icon: item.icon,
            label: item.label,
            route: item.route,
            isCatchy: user.newlyAddedPermissions.contains(item.route),
            badgeCount: item.route == '/cashier/verify-stock' ? pendingTransfersCount : null,
          ));
        }
      }
    }
 else {
      // Check if non-admin has been granted specific admin duties
      for (final item in adminItems) {
        if (user.enabledPermissions.contains(item.route)) {
          items.add(SidebarItem(
            icon: item.icon,
            label: item.label,
            route: item.route,
            isCatchy: user.newlyAddedPermissions.contains(item.route),
            badgeCount: item.route == '/cashier/verify-stock' ? pendingTransfersCount : null,
          ));
        }
      }
    }

    // 2. Cashier Module
    final hasCashierAccess = roles.contains(UserRole.superAdmin) || 
                             roles.contains(UserRole.cashier) || 
                             user.enabledPermissions.contains('/cashier');
    
    if (hasCashierAccess) {
      items.add(SidebarItem(
        icon: Icons.point_of_sale_rounded, 
        label: 'Cashier POS', 
        route: '/cashier', 
        isCatchy: user.newlyAddedPermissions.contains('/cashier'),
      ));

      items.add(SidebarItem(
        icon: Icons.qr_code_scanner_rounded,
        label: 'Verify Incoming Stock',
        route: '/cashier/verify-stock',
        badgeCount: (pendingTransfersCount ?? 0) > 0 ? pendingTransfersCount : null,
      ));
      
      // NEW: Cashiers get Daily Sales Report access
      if (roles.contains(UserRole.cashier)) {
        items.add(SidebarItem(
          icon: Icons.bar_chart_rounded,
          label: 'Daily Sales Report',
          route: '/admin/sales', // Reusing sales report screen
        ));
      }
    }

    // 3. Butcher Module
    final hasButcherAccess = roles.contains(UserRole.superAdmin) || 
                             roles.contains(UserRole.butcher) || 
                             user.enabledPermissions.contains('/butcher');

    if (hasButcherAccess) {
      if (inButcherShell) {
        items.addAll([
          SidebarItem(icon: Icons.dashboard_rounded, label: 'Butcher Home', route: 'butcher:dashboard'),
          SidebarItem(icon: Icons.assignment_rounded, label: 'Processing Orders', route: 'butcher:orders'),
          SidebarItem(icon: Icons.pets_rounded, label: 'Animal Intake', route: 'butcher:animalIntake'),
          SidebarItem(icon: Icons.history_edu_rounded, label: 'Slaughter Logs', route: 'butcher:slaughterLog'),
          SidebarItem(icon: Icons.outdoor_grill, label: 'Meat Processing', route: 'butcher:meatProcessing'),
          SidebarItem(icon: Icons.layers_rounded, label: 'Batch Management', route: 'butcher:batchManagement'),
          SidebarItem(icon: Icons.local_shipping_rounded, label: 'Stock Transfer', route: 'butcher:stockTransfer'),
          SidebarItem(icon: Icons.inventory_2_rounded, label: 'Internal Inventory', route: 'butcher:inventory'),
          SidebarItem(icon: Icons.bar_chart_rounded, label: 'Operational Reports', route: 'butcher:reports'),
          SidebarItem(icon: Icons.receipt_long_rounded, label: 'Unit Expenses', route: 'butcher:expenses'),
          SidebarItem(icon: Icons.delete_outline_rounded, label: 'Waste Management', route: 'butcher:wasteManagement'),
          SidebarItem(icon: Icons.folder_open_rounded, label: 'Documents', route: 'butcher:documents'),
        ]);
      } else {
        items.add(SidebarItem(
          icon: Icons.restaurant_rounded, 
          label: 'Butcher Operations', 
          route: '/butcher', 
          isCatchy: user.newlyAddedPermissions.contains('/butcher'),
        ));
      }
    }

    // 4. System Access (Always visible to all users)
    items.add(SidebarItem(icon: Icons.info_outline_rounded, label: 'About System', route: '/about'));
    items.add(SidebarItem(icon: Icons.settings_rounded, label: 'User Settings', route: '/settings'));
    // Removed "My Profile" as requested. Details are now inside System Settings.

    // Special: Super Admin Root Access
    if (roles.contains(UserRole.superAdmin)) {
      items.add(SidebarItem(icon: Icons.security, label: 'Root Access (Restore)', route: '/admin/super', isCatchy: true));
    }

    return _deduplicateItems(items);
  }

  static List<Map<String, String>> getAllAvailableDuties() {
    return [
      {'route': '/admin', 'label': 'Admin Dashboard'},
      {'route': '/admin/sales', 'label': 'Sales Analytics'},
      {'route': '/admin/expenses', 'label': 'Business Expenses'},
      {'route': '/admin/customers', 'label': 'Customer Directory'},
      {'route': '/admin/documents', 'label': 'Compliance Documents'},
      {'route': '/admin/debts', 'label': 'Debt Tracker'},
      {'route': '/admin/stock', 'label': 'Master Stock Control'},
      {'route': '/admin/salaries', 'label': 'Salary Management'},
      {'route': '/admin/staff', 'label': 'Staff Management'},
      {'route': '/admin/recents', 'label': 'Company Recents'},
      {'route': '/admin/maintenance', 'label': 'System Maintenance'},
      {'route': '/cashier', 'label': 'Cashier POS Access'},
      {'route': '/butcher', 'label': 'Butcher Operations Access'},
      {'route': '/settings', 'label': 'System Settings'},
    ];
  }

  static List<SidebarItem> _deduplicateItems(List<SidebarItem> items) {
    final seen = <String>{};
    return items.where((item) => seen.add(item.route)).toList();
  }

  static void navigate(BuildContext context, String route, String currentRoute) {
    if (route == currentRoute) return;
    
    // Ensure we are using the correct Navigator context
    final navigator = Navigator.of(context);
    navigator.pushReplacementNamed(route);
  }

  static String getHomeRoute(UserAccount user) {
    switch (user.activePrimaryRole) {
      case UserRole.admin:
        return '/admin';
      case UserRole.butcher:
        return '/butcher';
      case UserRole.cashier:
        return '/cashier';
      case UserRole.superAdmin:
        return '/admin/super';
    }
  }
}

/// A reactive provider for menu items based on the current user
final menuItemsProvider = Provider<List<SidebarItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final pendingCount = ref.watch(pendingIncomingTransfersProvider).length;
  return MenuService.getMenuItemsForUser(user, pendingTransfersCount: pendingCount);
});

/// A reactive provider for butcher unit menu items
final butcherMenuItemsProvider = Provider<List<SidebarItem>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  final pendingCount = ref.watch(pendingIncomingTransfersProvider).length;
  return MenuService.getMenuItemsForUser(user, inButcherShell: true, pendingTransfersCount: pendingCount);
});
