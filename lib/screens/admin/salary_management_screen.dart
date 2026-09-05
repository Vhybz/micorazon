import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants.dart';
import '../../models/user_model.dart';
import '../../services/user_provider.dart';
import '../../services/sms_service.dart';
import '../../services/receipt_service.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/menu_service.dart';
import '../../services/salary_provider.dart';
import '../../models/salary_model.dart';
import '../../core/uuid_utils.dart';
import '../../widgets/role_pop_scope.dart';
import '../../widgets/passcode_guard.dart';

class SalaryManagementScreen extends ConsumerWidget {
  const SalaryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    // Keep history loaded and active
    ref.watch(salaryHistoryProvider); 

    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final allUsers = ref.watch(userProvider);
    final salaryHistory = ref.watch(salaryHistoryProvider);
    
    // Fix: Sort users by creation date (First Come First Serve) to prevent shuffling
    final users = allUsers.where((u) => !u.isDeleted).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Extract External Workers from history
    final externalWorkersMap = <String, List<SalaryRecord>>{};
    for (final p in salaryHistory) {
      if (p.isExternal && p.externalName != null) {
        externalWorkersMap.putIfAbsent(p.externalName!, () => []).add(p);
      }
    }

    // Logic for salary alerts (Staff + External)
    final now = DateTime.now();
    
    final staffDueSoon = users.where((u) {
      if (u.isDeleted || u.status != AccountStatus.approved || u.salaryDay == null) return false;
      if (u.lastSalaryDate != null) {
        if (u.lastSalaryDate!.month == now.month && u.lastSalaryDate!.year == now.year) return false;
      }
      final int day = u.salaryDay!;
      return (day >= now.day && day <= now.day + 3) || (now.day > day && now.day - day <= 1);
    }).toList();

    final externalDueSoon = <String>[];
    externalWorkersMap.forEach((name, records) {
      final sorted = List<SalaryRecord>.from(records)..sort((a, b) => b.date.compareTo(a.date));
      final latest = sorted.first;
      
      if (latest.externalBaseSalary != null && latest.externalPayDay != null) {
        // Check if paid this month
        final alreadyPaid = records.any((r) => !r.isAdvance && r.targetMonth.month == now.month && r.targetMonth.year == now.year);
        if (!alreadyPaid) {
          final int day = latest.externalPayDay!;
          if ((day >= now.day && day <= now.day + 3) || (now.day > day && now.day - day <= 1)) {
            externalDueSoon.add(name);
          }
        }
      }
    });

    final totalDueCount = staffDueSoon.length + externalDueSoon.length;
      
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/salaries';

    return RolePopScope(
      currentRoute: currentRoute,
      child: PasscodeGuard(
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: const MainAppBar(title: 'Payroll & Salaries', showMenuButton: true),
          drawer: isDesktop ? null : Drawer(
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (totalDueCount > 0) ...[
                        _buildAlertBanner(theme, staffDueSoon, externalDueSoon),
                        const SizedBox(height: AppSpacing.l),
                      ],
                      _buildHeader(theme, users.length),
                      const SizedBox(height: AppSpacing.m),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => ReceiptService.printSalaryReport(users),
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: const Text('Print Payroll List'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _handleExternalPayment(context, ref),
                            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                            label: const Text('ADD EXTERNAL WORKER'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _showGlobalHistoryDetails(context, ref),
                            icon: const Icon(Icons.account_balance_rounded, size: 18),
                            label: const Text('Global Ledger'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Syncing payment history...'), duration: Duration(seconds: 1)));
                              await ref.read(userProvider.notifier).loadUsers();
                              await ref.read(salaryHistoryProvider.notifier).loadAll();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History synced with database.'), backgroundColor: Colors.green));
                              }
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Sync Staff Data'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      if (users.isEmpty)
                        _buildEmptyState(theme)
                      else
                        _buildPaymentGrid(context, ref, users),

                      if (externalWorkersMap.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        const Divider(),
                        const SizedBox(height: AppSpacing.xl),
                        _buildSectionHeader(theme, 'Casual & External Workers', 'People paid for one-off tasks or contract work.'),
                        const SizedBox(height: AppSpacing.m),
                        _buildExternalWorkerGrid(context, ref, externalWorkersMap),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertBanner(ThemeData theme, List<UserAccount> staffDue, List<String> externalDue) {
    final total = staffDue.length + externalDue.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notification_important_rounded, color: Colors.red),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Incoming Salary Settling', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                Text(
                  'There are $total workers (Staff & Casual) with salaries due today or very soon. Please review the payroll grid.',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payroll Management',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        Text(
          'Overseeing compensation for $total authorized team members.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          Icon(Icons.people_outline_rounded, size: 80, color: theme.dividerColor),
          const SizedBox(height: 16),
          const Text('No Staff Registered', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Text('Register staff in Account Management to see them here.'),
        ],
      ),
    );
  }

  Widget _buildPaymentGrid(BuildContext context, WidgetRef ref, List<UserAccount> staffList) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200 ? 3 : (constraints.maxWidth > 800 ? 2 : 1);
        
        // Dynamic aspect ratio calculation to prevent overflow
        // Desktop cards need more vertical room for all the buttons and stats
        double aspectRatio = 1.1; 
        if (constraints.maxWidth < 600) {
          aspectRatio = 0.85; // Taller on mobile
        } else if (constraints.maxWidth < 900) {
          aspectRatio = 1.0;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: aspectRatio,
          ),
          itemCount: staffList.length,
          itemBuilder: (context, index) {
            final staff = staffList[index];
            return _buildSalaryCard(context, ref, staff);
          },
        );
      },
    );
  }

  Widget _buildSalaryCard(BuildContext context, WidgetRef ref, UserAccount staff) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    
    bool isDueSoon = false;
    bool isPaidThisMonth = false;
    
    if (staff.salaryDay != null) {
      final int day = staff.salaryDay!;
      isDueSoon = (day >= now.day && day <= now.day + 3) || (now.day > day && now.day - day <= 1);
    }
    
    if (staff.lastSalaryDate != null) {
      isPaidThisMonth = staff.lastSalaryDate!.month == now.month && staff.lastSalaryDate!.year == now.year;
    }

    return Card(
      elevation: isDueSoon && !isPaidThisMonth ? 8 : 2,
      shadowColor: isDueSoon ? Colors.red.withValues(alpha: 0.3) : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDueSoon && !isPaidThisMonth 
          ? const BorderSide(color: Colors.red, width: 2) 
          : BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2), width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                  ),
                  child: ClipOval(
                    child: staff.photoUrl != null && staff.photoUrl!.isNotEmpty
                        ? Image.network(
                            staff.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _fallbackAvatar(staff, theme),
                          )
                        : _fallbackAvatar(staff, theme),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(staff.role.name.toUpperCase(), style: TextStyle(fontSize: 9, color: theme.colorScheme.primary, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    ],
                  ),
                ),
                if (isPaidThisMonth)
                  const Icon(Icons.verified_rounded, color: Colors.green, size: 24),
                IconButton(
                  icon: const Icon(Icons.settings_suggest_rounded, size: 22, color: Colors.blue),
                  onPressed: () => _showEditSalaryDialog(context, ref, staff),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Configure Salary',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Financial Summary Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LIFETIME PAID', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text('₵${staff.totalSalaryPaid.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 24, color: theme.dividerColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TOTAL ADVANCES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text('₵${staff.totalAdvancesTaken.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BASE MONTHLY', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(staff.salaryAmount != null ? '₵${staff.salaryAmount!.toStringAsFixed(0)}' : 'NOT SET', 
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: staff.salaryAmount == null ? Colors.red : Colors.black)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('NEXT PAY DAY', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(staff.salaryDay != null ? 'Day ${staff.salaryDay}' : 'N/A', 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _salaryActionButton(
                  context, 
                  label: 'ISSUE ADVANCE', 
                  color: Colors.orange.shade800, 
                  onPressed: () => _handlePayment(context, ref, staff, isAdvance: true)
                ),
                const SizedBox(width: 8),
                _salaryActionButton(
                  context, 
                  label: isPaidThisMonth ? 'SALARY PAID' : 'PAY SALARY', 
                  color: isPaidThisMonth ? Colors.grey : Colors.green.shade700, 
                  onPressed: isPaidThisMonth ? null : () => _handlePayment(context, ref, staff, isAdvance: false)
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showSalaryHistoryDetails(context, ref, staff),
                    icon: const Icon(Icons.history_edu_rounded, size: 18),
                    label: const Text('PAYMENT HISTORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryMaroon,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.primaryMaroon),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => ReceiptService.printPayslip(
                      staff, 
                      staff.salaryAmount ?? 0.0, 
                      false,
                      targetMonth: staff.lastSalaryDate,
                    ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('REPRINT SLIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primaryMaroon,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.primaryMaroon),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _salaryActionButton(BuildContext context, {required String label, required Color color, VoidCallback? onPressed}) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color, 
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 2,
          shadowColor: color.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  Widget _fallbackAvatar(UserAccount staff, ThemeData theme) {
    return Container(
      color: theme.colorScheme.primary.withValues(alpha: 0.1),
      child: Center(
        child: Text(
          staff.firstName[0], 
          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
        ),
        Text(
          subtitle,
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildExternalWorkerGrid(BuildContext context, WidgetRef ref, Map<String, List<SalaryRecord>> externalWorkersMap) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200 ? 3 : (constraints.maxWidth > 800 ? 2 : 1);
        double aspectRatio = 1.1; 
        if (constraints.maxWidth < 600) aspectRatio = 0.85;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: aspectRatio,
          ),
          itemCount: externalWorkersMap.length,
          itemBuilder: (context, index) {
            final name = externalWorkersMap.keys.elementAt(index);
            final records = externalWorkersMap[name]!;
            return _buildExternalWorkerCard(context, ref, name, records);
          },
        );
      },
    );
  }

  Widget _buildExternalWorkerCard(BuildContext context, WidgetRef ref, String name, List<SalaryRecord> records) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    
    // Sort to get latest info
    final sorted = List<SalaryRecord>.from(records)..sort((a, b) => b.date.compareTo(a.date));
    final latest = sorted.first;
    final double totalPaid = records.fold(0.0, (sum, r) => sum + r.amount);

    bool isDueSoon = false;
    bool isPaidThisMonth = records.any((r) => !r.isAdvance && r.targetMonth.month == now.month && r.targetMonth.year == now.year);
    
    if (latest.externalPayDay != null) {
      final int day = latest.externalPayDay!;
      isDueSoon = (day >= now.day && day <= now.day + 3) || (now.day > day && now.day - day <= 1);
    }

    return Card(
      elevation: isDueSoon && !isPaidThisMonth ? 8 : 2,
      shadowColor: isDueSoon ? Colors.red.withValues(alpha: 0.3) : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDueSoon && !isPaidThisMonth 
          ? const BorderSide(color: Colors.red, width: 2) 
          : BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2), width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                  ),
                  child: ClipOval(
                    child: latest.externalPhotoUrl != null && latest.externalPhotoUrl!.isNotEmpty
                        ? Image.network(
                            latest.externalPhotoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.orange.withValues(alpha: 0.1),
                              child: Center(child: Text(name[0], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                            ),
                          )
                        : Container(
                            color: Colors.orange.withValues(alpha: 0.1),
                            child: Center(child: Text(name[0], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const Text('EXTERNAL WORKER', style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    ],
                  ),
                ),
                if (isPaidThisMonth)
                  const Icon(Icons.verified_rounded, color: Colors.green, size: 24),
                IconButton(
                  icon: const Icon(Icons.settings_suggest_rounded, size: 22, color: Colors.blue),
                  onPressed: () => _showEditExternalWorkerDialog(context, ref, name, records),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Configure Worker',
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Financial Summary Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('LIFETIME PAID', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text('₵${totalPaid.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 24, color: theme.dividerColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TOTAL ADVANCES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                        Text('₵${records.where((r) => r.isAdvance).fold(0.0, (sum, r) => sum + r.amount).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BASE MONTHLY', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(latest.externalBaseSalary != null ? '₵${latest.externalBaseSalary!.toStringAsFixed(0)}' : 'NOT SET', 
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: latest.externalBaseSalary == null ? Colors.red : Colors.black)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('NEXT PAY DAY', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(latest.externalPayDay != null ? 'Day ${latest.externalPayDay}' : 'N/A', 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _salaryActionButton(
                  context, 
                  label: 'ISSUE ADVANCE', 
                  color: Colors.orange.shade800, 
                  onPressed: () => _handleExternalPayment(context, ref, initialName: name, isAdvance: true)
                ),
                const SizedBox(width: 8),
                _salaryActionButton(
                  context, 
                  label: isPaidThisMonth ? 'SALARY PAID' : 'PAY WORKER', 
                  color: isPaidThisMonth ? Colors.grey : Colors.green.shade700, 
                  onPressed: isPaidThisMonth ? null : () => _handleExternalPayment(context, ref, initialName: name, isAdvance: false)
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showExternalWorkerHistory(context, ref, name, records),
                    icon: const Icon(Icons.history_edu_rounded, size: 18),
                    label: const Text('HISTORY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.orange.shade800),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => ReceiptService.printPayslip(
                      UserAccount(
                        id: 'EXTERNAL', 
                        firstName: name, 
                        surname: '', 
                        email: latest.externalEmail ?? '', 
                        phone: latest.externalPhone,
                        role: UserRole.cashier,
                      ), 
                      latest.amount, 
                      false, 
                      note: latest.displayNote, 
                      targetMonth: latest.targetMonth,
                    ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('REPRINT SLIP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: Colors.orange.shade800),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExternalWorkerHistory(BuildContext context, WidgetRef ref, String name, List<SalaryRecord> records) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final sorted = List<SalaryRecord>.from(records)..sort((a, b) => b.date.compareTo(a.date));
        final double total = records.fold(0.0, (sum, r) => sum + r.amount);

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Row(
            children: [
              const Icon(Icons.history_rounded, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(child: Text('Payment History: $name', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            width: MediaQuery.of(context).size.width * 0.9,
            height: 400,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppRadius.m),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL PAID', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      Text('₵${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final r = sorted[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor)),
                        child: ListTile(
                          dense: true,
                          title: Text('₵${r.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Paid: ${DateFormat('MMM dd, yyyy').format(r.date)}\nFor: ${DateFormat('MMMM yyyy').format(r.targetMonth)}', style: const TextStyle(fontSize: 10)),
                          trailing: IconButton(
                            icon: const Icon(Icons.print_outlined, size: 20),
                            onPressed: () => ReceiptService.printPayslip(
                              UserAccount(id: 'EXTERNAL', firstName: name, surname: '', email: r.externalEmail ?? '', phone: r.externalPhone, role: UserRole.cashier), 
                              r.amount, 
                              false, 
                              note: r.displayNote, 
                              targetMonth: r.targetMonth
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE'))],
        );
      },
    );
  }

  void _showEditExternalWorkerDialog(BuildContext context, WidgetRef ref, String currentName, List<SalaryRecord> records) {
    final sorted = List<SalaryRecord>.from(records)..sort((a, b) => b.date.compareTo(a.date));
    final latest = sorted.first;

    final nameController = TextEditingController(text: currentName);
    final phoneController = TextEditingController(text: latest.externalPhone ?? '');
    final emailController = TextEditingController(text: latest.externalEmail ?? '');
    final amountController = TextEditingController(text: latest.externalBaseSalary?.toString() ?? '');
    final dayController = TextEditingController(text: latest.externalPayDay?.toString() ?? '');
    final adjustmentController = TextEditingController();

    bool isSaving = false;
    Uint8List? pickedImageBytes;
    String? currentPhotoUrl = latest.externalPhotoUrl;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final photoUrl = currentPhotoUrl;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: Text('Worker Settings: $currentName'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar Picker (Same as Profile Screen)
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.orange, width: 2),
                          ),
                          child: ClipOval(
                            child: pickedImageBytes != null
                                ? Image.memory(pickedImageBytes!, fit: BoxFit.cover)
                                : (photoUrl != null && photoUrl.isNotEmpty
                                    ? Image.network(
                                        photoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_outline, size: 40, color: Colors.orange),
                                      )
                                    : const Icon(Icons.person_outline, size: 40, color: Colors.orange)),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: () async {
                              final picker = ImagePicker();
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 512,
                                maxHeight: 512,
                                imageQuality: 70,
                              );
                              if (image != null) {
                                final bytes = await image.readAsBytes();
                                setDialogState(() => pickedImageBytes = bytes);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Worker Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneController,
                          decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder(), isDense: true),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), isDense: true),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text('SALARY CONTRACT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amountController,
                          decoration: const InputDecoration(labelText: 'Base Salary (₵)', border: OutlineInputBorder(), isDense: true),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dayController,
                          decoration: const InputDecoration(labelText: 'Pay Day (1-31)', border: OutlineInputBorder(), isDense: true),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const Text('LIFETIME ADJUSTMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: adjustmentController,
                    decoration: const InputDecoration(
                      labelText: 'Add Past Payment (₵)', 
                      border: OutlineInputBorder(), 
                      isDense: true,
                      helperText: 'Increases the Lifetime Paid total.',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isSaving ? null : () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  setDialogState(() => isSaving = true);
                  try {
                    final newName = nameController.text.trim();
                    final baseSalary = double.tryParse(amountController.text);
                    final payDay = int.tryParse(dayController.text);
                    final adjustment = double.tryParse(adjustmentController.text) ?? 0.0;

                    String? finalPhotoUrl = currentPhotoUrl;

                    // 1. Upload new photo if picked
                    if (pickedImageBytes != null) {
                      final String identifier = '${newName}_${phoneController.text.trim()}'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
                      finalPhotoUrl = await ref.read(userProvider.notifier).uploadExternalPhoto(identifier, pickedImageBytes!);
                    }

                    // 2. Prepare updated metadata
                    final metadata = {
                      'external_worker': {
                        'name': newName,
                        'phone': phoneController.text.trim(),
                        'email': emailController.text.trim(),
                        'photo_url': finalPhotoUrl,
                        'base_salary': baseSalary,
                        'pay_day': payDay,
                      },
                      'user_note': latest.displayNote,
                    };

                    final encodedMetadata = json.encode(metadata);

                    // 2. Update all records for this worker
                    final notifier = ref.read(salaryHistoryProvider.notifier);
                    for (final r in records) {
                      await notifier.updatePayment(r.copyWith(
                        note: encodedMetadata,
                      ));
                    }

                    // 3. Handle Lifetime Adjustment (create a historical record if needed)
                    if (adjustment > 0) {
                      await notifier.addPayment(SalaryRecord(
                        id: UuidUtils.generate(),
                        userId: 'EXTERNAL',
                        amount: adjustment,
                        isAdvance: false,
                        date: DateTime.now().subtract(const Duration(days: 365)), // Mark as old
                        targetMonth: DateTime.now(),
                        note: json.encode({
                          ...metadata,
                          'user_note': 'Manual Balance Adjustment (Migration/Correction)',
                        }),
                      ));
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Worker settings updated successfully.'), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
                      setDialogState(() => isSaving = false);
                    }
                  }
                },
                child: isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('SAVE SETTINGS'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditSalaryDialog(BuildContext context, WidgetRef ref, UserAccount staff) {
    final amountController = TextEditingController(text: staff.salaryAmount?.toString() ?? '');
    final dayController = TextEditingController(text: staff.salaryDay?.toString() ?? '');
    final lifetimePaidController = TextEditingController();
    final lifetimeAdvanceController = TextEditingController();

    final theme = Theme.of(context);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Text('Salary Setup: ${staff.firstName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Base Monthly Salary',
                    prefixText: '₵ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: dayController,
                  decoration: const InputDecoration(
                    labelText: 'Payment Day (1-31)',
                    hintText: 'e.g. 30',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const Text('LIFETIME ADJUSTMENTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: lifetimePaidController,
                  decoration: const InputDecoration(
                    labelText: 'Add to Lifetime Paid (₵)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lifetimeAdvanceController,
                  decoration: const InputDecoration(
                    labelText: 'Add to Lifetime Advances (₵)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                setState(() => isSaving = true);
                try {
                  final double? amount = double.tryParse(amountController.text);
                  final int? day = int.tryParse(dayController.text);
                  final double addPaid = double.tryParse(lifetimePaidController.text) ?? 0.0;
                  final double addAdvance = double.tryParse(lifetimeAdvanceController.text) ?? 0.0;

                  await ref.read(userProvider.notifier).updateSalary(
                    staff.id,
                    amount: amount,
                    day: day,
                    addSalaryPaid: addPaid,
                    addAdvanceTaken: addAdvance,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Salary configuration updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('Salary Setup Error: $e');
                  if (context.mounted) {
                    setState(() => isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving salary: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: isSaving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('SAVE SETTINGS'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleExternalPayment(BuildContext context, WidgetRef ref, {String? initialName, bool isAdvance = false}) {
    final nameController = TextEditingController(text: initialName);
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    bool isProcessing = false;
    bool currentIsAdvance = isAdvance;
    Uint8List? pickedImageBytes;
    final now = DateTime.now();
    DateTime selectedTargetMonth = DateTime(now.year, now.month, 1);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: const Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: Colors.orange),
                SizedBox(width: 12),
                Text('Add External Worker'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pay a worker who is NOT in the system. Details will be saved in the audit trail.', 
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 16),
                  
                  // Image Picker for External Worker
                  Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.orange, width: 2),
                          ),
                          child: ClipOval(
                            child: pickedImageBytes != null
                              ? Image.memory(pickedImageBytes!, fit: BoxFit.cover)
                              : const Icon(Icons.person_outline, size: 40, color: Colors.orange),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: () async {
                              final picker = ImagePicker();
                              final XFile? image = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 512,
                                maxHeight: 512,
                                imageQuality: 70,
                              );
                              if (image != null) {
                                final bytes = await image.readAsBytes();
                                setDialogState(() => pickedImageBytes = bytes);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Worker Name*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneController,
                          decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_outlined), isDense: true),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.alternate_email_rounded), isDense: true),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(labelText: 'Amount (₵)*', border: OutlineInputBorder(), prefixIcon: Icon(Icons.payments_outlined)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  
                  // Advance Toggle
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark as Salary Advance', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Funds given ahead of work completion.', style: TextStyle(fontSize: 10)),
                    value: currentIsAdvance,
                    activeThumbColor: Colors.orange,
                    onChanged: (v) => setDialogState(() => currentIsAdvance = v),
                  ),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: const Text('For Month', style: TextStyle(fontSize: 12)),
                    subtitle: Text(DateFormat('MMMM yyyy').format(selectedTargetMonth), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedTargetMonth,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTargetMonth = DateTime(picked.year, picked.month, 1));
                        }
                      },
                      child: const Text('Change'),
                    ),
                  ),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'General Note', border: OutlineInputBorder(), hintText: 'e.g. Repairs, Casual Work...'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: isProcessing ? null : () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: isProcessing ? null : () async {
                  final name = nameController.text.trim();
                  final amount = double.tryParse(amountController.text) ?? 0.0;
                  
                  if (name.isEmpty || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and valid Amount are required.')));
                    return;
                  }

                  setDialogState(() => isProcessing = true);
                  
                  try {
                    String? uploadedUrl;
                    final String recordId = UuidUtils.generate();

                    // Upload Image if picked
                    if (pickedImageBytes != null) {
                      // Use stable identifier for external worker to allow picture management/cleanup
                      final String identifier = '${name}_${phoneController.text.trim()}'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase();
                      uploadedUrl = await ref.read(userProvider.notifier).uploadExternalPhoto(identifier, pickedImageBytes!);
                    }

                    final metadata = {
                      'external_worker': {
                        'name': name,
                        'phone': phoneController.text.trim(),
                        'email': emailController.text.trim(),
                        'photo_url': uploadedUrl,
                      },
                      'user_note': noteController.text.trim(),
                    };

                    final record = SalaryRecord(
                      id: recordId,
                      userId: 'EXTERNAL',
                      amount: amount,
                      isAdvance: currentIsAdvance,
                      date: DateTime.now(),
                      targetMonth: selectedTargetMonth,
                      note: json.encode(metadata),
                    );

                    await ref.read(salaryHistoryProvider.notifier).addPayment(record);
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      _showExternalPaymentSuccess(context, ref, record);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save payment: $e')));
                      setDialogState(() => isProcessing = false);
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
                child: isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('CONFIRM PAYMENT'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showExternalPaymentSuccess(BuildContext context, WidgetRef ref, SalaryRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.check_circle, color: Colors.green, size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Payment Recorded Successfully!', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('₵${record.amount.toStringAsFixed(2)} paid to ${record.externalName}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ReceiptService.printPayslip(
                UserAccount(
                  id: 'EXTERNAL', 
                  firstName: record.externalName ?? 'External', 
                  surname: 'Worker', 
                  email: record.externalEmail ?? '', 
                  phone: record.externalPhone,
                  role: UserRole.cashier,
                ), 
                record.amount, 
                record.isAdvance, 
                note: record.displayNote, 
                targetMonth: record.targetMonth
              );
            },
            icon: const Icon(Icons.print),
            label: const Text('Print Payslip'),
          ),
        ],
      ),
    );
  }

  void _showGlobalHistoryDetails(BuildContext context, WidgetRef ref) async {
    await ref.read(salaryHistoryProvider.notifier).loadAll();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final allPayments = ref.watch(salaryHistoryProvider);
          final allUsers = ref.read(userProvider);
          
          final sortedPayments = List<SalaryRecord>.from(allPayments)
            ..sort((a, b) => b.date.compareTo(a.date));

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: const Row(
              children: [
                Icon(Icons.account_balance_rounded, color: AppColors.primaryMaroon),
                SizedBox(width: 12),
                Text('Global Payment Ledger'),
              ],
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 700),
              width: MediaQuery.of(context).size.width * 0.9,
              height: 600,
              child: Column(
                children: [
                  Expanded(
                    child: sortedPayments.isEmpty 
                      ? const Center(child: Text('No payment history found.'))
                      : ListView.builder(
                          itemCount: sortedPayments.length,
                          itemBuilder: (context, index) {
                            final p = sortedPayments[index];
                            final staff = p.isExternal ? null : allUsers.firstWhere((u) => u.id == p.userId, orElse: () => UserAccount(id: p.userId, firstName: 'Unknown', surname: 'User', email: '', role: UserRole.cashier));
                            
                            final displayName = p.isExternal ? (p.externalName ?? 'External Worker') : (staff?.name ?? 'Unknown');
                            final displayRole = p.isExternal ? 'EXTERNAL' : (staff?.role.name.toUpperCase() ?? 'STAFF');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: theme.dividerColor)),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: p.isExternal ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                                  backgroundImage: p.isExternal && p.externalPhotoUrl != null ? NetworkImage(p.externalPhotoUrl!) : null,
                                  child: p.isExternal && p.externalPhotoUrl == null ? const Icon(Icons.person_outline, size: 18, color: Colors.orange) : (p.isExternal ? null : const Icon(Icons.badge_outlined, size: 18, color: Colors.blue)),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold))),
                                    Text('₵${p.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(displayRole, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: p.isExternal ? Colors.orange : Colors.blue)),
                                        const SizedBox(width: 8),
                                        Text(DateFormat('MMM dd, yyyy').format(p.date), style: const TextStyle(fontSize: 9, color: Colors.grey)),
                                      ],
                                    ),
                                    if (p.displayNote != null && p.displayNote!.isNotEmpty)
                                      Text(p.displayNote!, style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.print_outlined, size: 20),
                                  onPressed: () {
                                    ReceiptService.printPayslip(
                                      p.isExternal 
                                        ? UserAccount(id: 'EXTERNAL', firstName: p.externalName ?? 'External', surname: 'Worker', email: p.externalEmail ?? '', phone: p.externalPhone, role: UserRole.cashier)
                                        : staff!, 
                                      p.amount, 
                                      p.isAdvance, 
                                      note: p.displayNote, 
                                      targetMonth: p.targetMonth
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
            ],
          );
        },
      ),
    );
  }

  void _handlePayment(BuildContext context, WidgetRef ref, UserAccount staff, {required bool isAdvance}) {
    final allPayments = ref.read(salaryHistoryProvider);
    final lastFullSalaryDate = staff.lastSalaryDate ?? DateTime(2000);
    
    // 1. Calculations
    final double lifetimeSalaryPaid = allPayments
        .where((p) => p.userId == staff.id && !p.isAdvance)
        .fold(0.0, (sum, p) => sum + p.amount);
        
    final double lifetimeAdvancesTaken = allPayments
        .where((p) => p.userId == staff.id && p.isAdvance)
        .fold(0.0, (sum, p) => sum + p.amount);

    final double pendingAdvances = allPayments
        .where((p) => p.userId == staff.id && p.isAdvance && p.date.isAfter(lastFullSalaryDate))
        .fold(0.0, (sum, p) => sum + p.amount);

    final double baseSalary = staff.salaryAmount ?? 0.0;
    
    final amountController = TextEditingController(text: isAdvance ? '' : baseSalary.toStringAsFixed(2));
    final noteController = TextEditingController();
    
    bool isProcessing = false;
    bool deductAdvances = !isAdvance && pendingAdvances > 0; 
    final now = DateTime.now();
    DateTime selectedTargetMonth = DateTime(now.year, now.month, 1);

    // Initial amount update if deducting
    if (deductAdvances) {
      amountController.text = (baseSalary - pendingAdvances).clamp(0.0, double.infinity).toStringAsFixed(2);
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Text(isAdvance ? 'Salary Advance' : 'Confirm Payment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paying ${staff.name}'),
                const SizedBox(height: 16),

                // Lifetime Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(AppRadius.s),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LIFETIME SALARY', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text('₵${lifetimeSalaryPaid.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green)),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 20, color: Colors.grey.withValues(alpha: 0.3)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('LIFETIME ADVANCES', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text('₵${lifetimeAdvancesTaken.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Payment Date (Uneditable)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(AppRadius.s),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available, size: 20, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('PAYMENT DATE (TODAY):', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text(DateFormat('MMMM dd, yyyy').format(now), 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54)),
                          ],
                        ),
                      ),
                      const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Target Month Selector (Editable)
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedTargetMonth,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedTargetMonth = DateTime(picked.year, picked.month, 1));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.s),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      color: Colors.blue.withValues(alpha: 0.05),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, size: 20, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('PAYMENT FOR MONTH:', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blue)),
                              Text(DateFormat('MMMM yyyy').format(selectedTargetMonth), 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
                            ],
                          ),
                        ),
                        const Icon(Icons.edit_calendar_rounded, size: 16, color: Colors.blue),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                if (!isAdvance && pendingAdvances > 0) ...[
                  Row(
                    children: [
                      Checkbox(
                        value: deductAdvances, 
                        onChanged: (v) {
                          setDialogState(() {
                            deductAdvances = v ?? false;
                            if (deductAdvances) {
                              amountController.text = (baseSalary - pendingAdvances).clamp(0.0, double.infinity).toStringAsFixed(2);
                            } else {
                              amountController.text = baseSalary.toStringAsFixed(2);
                            }
                          });
                        }
                      ),
                      const Expanded(
                        child: Text('Deduct Pending Advances', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      Text('₵${pendingAdvances.toStringAsFixed(0)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: isAdvance ? 'Advance Amount' : 'Payment Amount',
                    prefixText: '₵ ',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Note (Optional)',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Paid via MoMo',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final double amount = double.tryParse(amountController.text) ?? 0.0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount')));
                  return;
                }

                setDialogState(() => isProcessing = true);

                try {
                  final record = SalaryRecord(
                    id: UuidUtils.generate(),
                    userId: staff.id,
                    amount: amount,
                    isAdvance: isAdvance,
                    date: DateTime.now(),
                    targetMonth: selectedTargetMonth,
                    note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                  );

                  // 1. Add to history
                  await ref.read(salaryHistoryProvider.notifier).addPayment(record);
                  
                  // 2. Update user profile stats
                  await ref.read(userProvider.notifier).updateSalary(
                    staff.id,
                    lastPaid: isAdvance ? staff.lastSalaryDate : DateTime.now(),
                    isAdvance: isAdvance,
                    addSalaryPaid: isAdvance ? 0 : amount,
                    addAdvanceTaken: isAdvance ? amount : 0,
                  );

                  // 3. Send SMS if possible
                  if (staff.phone != null && staff.phone!.isNotEmpty) {
                    await SmsService.sendSalarySms(
                      phone: staff.phone!,
                      firstName: staff.firstName,
                      amount: amount,
                      isAdvance: isAdvance,
                      targetMonth: selectedTargetMonth,
                    );
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    _showPaymentSuccess(context, ref, staff, record);
                  }
                } catch (e) {
                  if (context.mounted) {
                    setDialogState(() => isProcessing = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isAdvance ? Colors.orange.shade800 : Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              child: isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isAdvance ? 'ISSUE ADVANCE' : 'CONFIRM PAYMENT'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentSuccess(BuildContext context, WidgetRef ref, UserAccount staff, SalaryRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 50),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Payment Successful!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 8),
            Text('₵${record.amount.toStringAsFixed(2)} has been recorded for ${staff.firstName}.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ReceiptService.printPayslip(staff, record.amount, record.isAdvance, note: record.note, targetMonth: record.targetMonth);
            }, 
            icon: const Icon(Icons.print_rounded),
            label: const Text('PRINT PAYSLIP'),
          ),
        ],
      ),
    );
  }

  void _showSalaryHistoryDetails(BuildContext context, WidgetRef ref, UserAccount staff) async {
    await ref.read(salaryHistoryProvider.notifier).loadAll();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final allPayments = ref.watch(salaryHistoryProvider);
          final workerPayments = allPayments.where((p) => p.userId == staff.id).toList();
          workerPayments.sort((a, b) => b.date.compareTo(a.date));

          final double totalSalary = workerPayments.where((p) => !p.isAdvance).fold(0.0, (sum, p) => sum + p.amount);
          final double totalAdvance = workerPayments.where((p) => p.isAdvance).fold(0.0, (sum, p) => sum + p.amount);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: Row(
              children: [
                const Icon(Icons.history_rounded, color: AppColors.primaryMaroon),
                const SizedBox(width: 12),
                Expanded(child: Text('Payment History: ${staff.firstName}', overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              width: MediaQuery.of(context).size.width * 0.9,
              height: 500,
              child: Column(
                children: [
                  // Totals Summary
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppRadius.m),
                      border: Border.all(color: AppColors.primaryMaroon.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TOTAL SALARY PAID', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                              Text('₵${totalSalary.toStringAsFixed(2)}', 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 30, color: Colors.grey.withValues(alpha: 0.2)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('TOTAL ADVANCE TAKEN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                              Text('₵${totalAdvance.toStringAsFixed(2)}', 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Expanded(
                    child: workerPayments.isEmpty 
                      ? const Center(child: Text('No payment history found.'))
                      : ListView.builder(
                          itemCount: workerPayments.length,
                          itemBuilder: (context, index) {
                            final p = workerPayments[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: theme.dividerColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8.0),
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: p.isAdvance ? Colors.orange.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                                    child: Icon(p.isAdvance ? Icons.trending_up : Icons.check_circle, 
                                      color: p.isAdvance ? Colors.orange : Colors.green, size: 18),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text('₵${p.amount.toStringAsFixed(2)}', 
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(DateFormat('MMMM yyyy').format(p.targetMonth), 
                                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryMaroon)),
                                    ],
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      if (p.displayNote != null)
                                        Text(p.displayNote!, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      Text('Paid: ${DateFormat('MMM dd, yyyy').format(p.date)}', 
                                        style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    padding: EdgeInsets.zero,
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        _showEditPaymentDialog(context, ref, p, staff);
                                      } else if (val == 'delete') {
                                        _confirmDeletePayment(context, ref, p);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit Record')),
                                      const PopupMenuItem(value: 'delete', child: Text('Delete Record', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CLOSE')),
              ElevatedButton.icon(
                onPressed: () => ReceiptService.printSalaryHistory(staff, workerPayments, period: 'Lifetime Statement'), 
                icon: const Icon(Icons.print_rounded),
                label: const Text('PRINT STATEMENT'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditPaymentDialog(BuildContext context, WidgetRef ref, SalaryRecord record, UserAccount staff) {
    final amountController = TextEditingController(text: record.amount.toString());
    final noteController = TextEditingController(text: record.displayNote);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Payment Record'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount (₵)', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                setState(() => isSaving = true);
                final updated = record.copyWith(
                  amount: double.tryParse(amountController.text) ?? record.amount,
                  note: record.isExternal 
                    ? json.encode({
                        'external_worker': {
                          'name': record.externalName,
                          'phone': record.externalPhone,
                          'email': record.externalEmail,
                          'photo_url': record.externalPhotoUrl,
                          'base_salary': record.externalBaseSalary,
                          'pay_day': record.externalPayDay,
                        },
                        'user_note': noteController.text.trim(),
                      })
                    : noteController.text.trim(),
                );
                await ref.read(salaryHistoryProvider.notifier).updatePayment(updated);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePayment(BuildContext context, WidgetRef ref, SalaryRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Payment?'),
        content: const Text('This will permanently remove this record from the audit trail.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(salaryHistoryProvider.notifier).deletePayment(record.id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
}
