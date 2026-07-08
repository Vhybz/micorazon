import 'package:flutter/material.dart';
import '../../widgets/app_sidebar.dart';
import '../../models/user_model.dart';

List<SidebarItem> getAdminMenuItems(UserAccount? user) {
  final defaultCoreRoutes = {'/admin', '/admin/settings', '/admin/staff', '/admin/salaries'};

  final allItems = [
    SidebarItem(icon: Icons.dashboard_rounded, label: 'Dashboard', route: '/admin'),
    SidebarItem(icon: Icons.admin_panel_settings_rounded, label: 'Staff Management', route: '/admin/staff'),
    SidebarItem(icon: Icons.bar_chart_rounded, label: 'Sales Reports', route: '/admin/sales'),
    SidebarItem(icon: Icons.analytics_outlined, label: 'Butcher Analytics', route: '/admin/butcher'),
    SidebarItem(icon: Icons.receipt_long_rounded, label: 'Business Expenses', route: '/admin/expenses'),
    SidebarItem(icon: Icons.people_outline_rounded, label: 'Customer Directory', route: '/admin/customers'),
    SidebarItem(icon: Icons.account_balance_wallet_rounded, label: 'Debt Tracker', route: '/admin/debts'),
    SidebarItem(icon: Icons.inventory_2_rounded, label: 'Inventory Control', route: '/admin/stock'),
    SidebarItem(icon: Icons.payments_rounded, label: 'Salary Management', route: '/admin/salaries'),
    SidebarItem(icon: Icons.settings_suggest_rounded, label: 'System Settings', route: '/admin/settings'),
  ];

  if (user == null) return allItems;

  return allItems.where((item) {
    return user.enabledPermissions.contains(item.route);
  }).map((item) {
    // If it's enabled but not a "core" route, mark it as catchy to stand out
    final isCatchy = !defaultCoreRoutes.contains(item.route);
    return SidebarItem(
      icon: item.icon,
      label: item.label,
      route: item.route,
      isCatchy: isCatchy,
    );
  }).toList();
}

void navigateAdmin(BuildContext context, String route, String currentRoute) {
  if (route == currentRoute) return;
  Navigator.pushReplacementNamed(context, route);
}
