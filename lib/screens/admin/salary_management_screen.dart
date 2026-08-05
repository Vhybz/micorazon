import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
    
    // Fix: Sort users by creation date (First Come First Serve) to prevent shuffling
    final users = allUsers.where((u) => !u.isDeleted).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/salaries';

    final now = DateTime.now();
    
    // Logic for salary alerts (Due within 3 days or today)
    final dueSoon = users.where((u) {
      if (u.isDeleted || u.status != AccountStatus.approved || u.salaryDay == null) return false;
      
      // Check if already paid this month
      if (u.lastSalaryDate != null) {
        if (u.lastSalaryDate!.month == now.month && u.lastSalaryDate!.year == now.year) return false;
      }

      final int day = u.salaryDay!;
      // Alert if day is today or within next 3 days
      return (day >= now.day && day <= now.day + 3) || (now.day > day && now.day - day <= 1);
    }).toList();

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
                      if (dueSoon.isNotEmpty) ...[
                        _buildAlertBanner(theme, dueSoon),
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

  Widget _buildAlertBanner(ThemeData theme, List<UserAccount> dueSoon) {
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
                  'There are ${dueSoon.length} staff members with salaries due today or very soon. Please review the payroll grid.',
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
        if (constraints.maxWidth < 600) aspectRatio = 0.85; // Taller on mobile
        else if (constraints.maxWidth < 900) aspectRatio = 1.0;

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

  void _showEditSalaryDialog(BuildContext context, WidgetRef ref, UserAccount staff) {
    final amountController = TextEditingController(text: staff.salaryAmount?.toString() ?? '');
    final dayController = TextEditingController(text: staff.salaryDay?.toString() ?? '');
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

                  await ref.read(userProvider.notifier).updateSalary(
                    staff.id,
                    amount: amount,
                    day: day,
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
    final deductionController = TextEditingController(text: pendingAdvances.toStringAsFixed(2));
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
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 1, 12),
                      helpText: 'SELECT TARGET MONTH',
                      fieldLabelText: 'Month',
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedTargetMonth = DateTime(picked.year, picked.month, 1);
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryMaroon.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppRadius.s),
                      border: Border.all(color: AppColors.primaryMaroon.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 20, color: AppColors.primaryMaroon),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('MAPPING PAYMENT TO:', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.primaryMaroon)),
                              Text(DateFormat('MMMM yyyy').format(selectedTargetMonth), 
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                        ),
                        const Icon(Icons.edit, size: 16, color: AppColors.primaryMaroon),
                      ],
                    ),
                  ),
                ),
                
                if (!isAdvance && pendingAdvances > 0) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Deduct Advances', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text('Current outstanding: ₵${pendingAdvances.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10)),
                    value: deductAdvances,
                    dense: true,
                    activeColor: AppColors.primaryMaroon,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) {
                      setDialogState(() {
                        deductAdvances = val ?? false;
                        if (deductAdvances) {
                          final deductVal = double.tryParse(deductionController.text) ?? 0;
                          amountController.text = (baseSalary - deductVal).clamp(0.0, double.infinity).toStringAsFixed(2);
                        } else {
                          amountController.text = baseSalary.toStringAsFixed(2);
                        }
                      });
                    },
                  ),
                  if (deductAdvances) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: deductionController,
                      decoration: const InputDecoration(
                        labelText: 'Deduction Amount',
                        prefixText: '₵ ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      onChanged: (v) {
                        final deductVal = double.tryParse(v) ?? 0;
                        setDialogState(() {
                          amountController.text = (baseSalary - deductVal).clamp(0.0, double.infinity).toStringAsFixed(2);
                        });
                      },
                    ),
                  ],
                ],

                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Amount Payable', 
                    prefixText: '₵ ', 
                    border: OutlineInputBorder(),
                    helperText: 'Actual cash amount to be handed over.',
                    helperStyle: TextStyle(fontSize: 9),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  enabled: !isProcessing,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: isAdvance ? 'Reason for Advance (Optional)' : 'Payment Note (Optional)',
                    hintText: isAdvance ? 'e.g., Medical, School Fees' : 'e.g., Bonus included',
                    border: const OutlineInputBorder(),
                  ),
                  enabled: !isProcessing,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                const Text('Staff will be notified via SMS.', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context), 
              child: const Text('CANCEL')
            ),
            ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (amount <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid amount.')));
                  return;
                }

                setDialogState(() => isProcessing = true);

                try {
                  await ref.read(userProvider.notifier).updateSalary(
                    staff.id, 
                    amount: staff.salaryAmount, 
                    day: staff.salaryDay, 
                    lastPaid: isAdvance ? staff.lastSalaryDate : DateTime.now(),
                    isAdvance: isAdvance,
                    addSalaryPaid: isAdvance ? 0 : amount,
                    addAdvanceTaken: isAdvance ? amount : 0,
                  );

                  String note = isAdvance ? 'Salary Advance' : 'Full Monthly Salary';
                  note += ' (${DateFormat('MMMM yyyy').format(selectedTargetMonth)})';

                  if (!isAdvance && deductAdvances) {
                    final deductVal = double.tryParse(deductionController.text) ?? 0;
                    note += ' (Deducted ₵${deductVal.toStringAsFixed(2)} in advances)';
                  }
                  
                  if (noteController.text.trim().isNotEmpty) {
                    note += ' - ${noteController.text.trim()}';
                  }

                  final record = SalaryRecord(
                    id: UuidUtils.generate(),
                    userId: staff.id,
                    amount: amount,
                    isAdvance: isAdvance,
                    date: DateTime.now(),
                    targetMonth: selectedTargetMonth,
                    note: note,
                  );
                  
                  await ref.read(salaryHistoryProvider.notifier).addPayment(record);
                  
                  await SmsService.sendSalarySms(
                    phone: staff.phone ?? '', 
                    firstName: staff.firstName, 
                    amount: amount, 
                    isAdvance: isAdvance,
                    note: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                    targetMonth: selectedTargetMonth,
                  );
                  
                  await ReceiptService.printPayslip(
                    staff, 
                    amount, 
                    isAdvance, 
                    note: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
                    targetMonth: selectedTargetMonth,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Salary processed for ${staff.name}'),
                        backgroundColor: Colors.green,
                      )
                    );
                  }
                } catch (e) {
                  debugPrint('Payment Processing Error: $e');
                  if (context.mounted) {
                    setDialogState(() => isProcessing = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('CONFIRM & NOTIFY'),
            ),
          ],
        ),
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
                                      if (p.note != null)
                                        Text(p.note!, style: const TextStyle(fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
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
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_note, size: 18, color: Colors.blue),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                            SizedBox(width: 8),
                                            Text('Delete', style: TextStyle(color: Colors.red)),
                                          ],
                                        ),
                                      ),
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
                onPressed: () => _showMonthSelector(context, ref, staff),
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text('GENERATE STATEMENT'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showEditPaymentDialog(BuildContext context, WidgetRef ref, SalaryRecord record, UserAccount staff) {
    final amountController = TextEditingController(text: record.amount.toStringAsFixed(2));
    final noteController = TextEditingController(text: record.note);
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
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₵ ', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                setState(() => isSaving = true);
                try {
                  final amount = double.tryParse(amountController.text) ?? record.amount;
                  final updated = SalaryRecord(
                    id: record.id,
                    userId: record.userId,
                    amount: amount,
                    isAdvance: record.isAdvance,
                    date: record.date,
                    targetMonth: record.targetMonth,
                    note: noteController.text,
                  );
                  await ref.read(salaryHistoryProvider.notifier).updatePayment(updated);
                  
                  // Resend SMS for update
                  await SmsService.sendSalarySms(
                    phone: staff.phone ?? '', 
                    firstName: staff.firstName, 
                    amount: amount, 
                    isAdvance: updated.isAdvance,
                    note: updated.note,
                    targetMonth: updated.targetMonth,
                    isUpdate: true,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment record updated.')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() => isSaving = false);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
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
        title: const Text('Delete Payment Record?'),
        content: const Text('This will permanently remove this record from history. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(salaryHistoryProvider.notifier).deletePayment(record.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment record deleted.'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  void _showMonthSelector(BuildContext context, WidgetRef ref, UserAccount staff) async {
    final String targetId = staff.id.trim().toLowerCase();
    await ref.read(salaryHistoryProvider.notifier).loadAll();
    if (!context.mounted) return;

    final allPayments = ref.read(salaryHistoryProvider);
    var workerPayments = allPayments.where((p) {
      final String pId = p.userId.trim().toLowerCase();
      return pId == targetId || pId.contains(targetId) || targetId.contains(pId);
    }).toList();
    
    final Set<String> uniqueMonthsSet = {};
    final List<DateTime> availableMonths = [];
    
    for (var p in workerPayments) {
      final key = "${p.targetMonth.year}-${p.targetMonth.month}";
      if (!uniqueMonthsSet.contains(key)) {
        uniqueMonthsSet.add(key);
        availableMonths.add(DateTime(p.targetMonth.year, p.targetMonth.month, 1));
      }
    }
    
    availableMonths.sort((a, b) => b.compareTo(a));
    final List<DateTime> selectedMonths = [];

    if (availableMonths.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No payment history found for ${staff.firstName}.'))
        );
      }
      return;
    }

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: const Text('Select Payment Months', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Showing months with recorded payments for ${staff.firstName}:', 
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 16),
                SizedBox(
                  width: 300,
                  height: 250,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableMonths.length,
                    itemBuilder: (context, index) {
                      final month = availableMonths[index];
                      final isSelected = selectedMonths.any((m) => m.year == month.year && m.month == month.month);
                      return CheckboxListTile(
                        title: Text(DateFormat('MMMM yyyy').format(month), style: const TextStyle(fontSize: 14)),
                        value: isSelected,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val!) {
                              selectedMonths.add(month);
                            } else {
                              selectedMonths.removeWhere((m) => m.year == month.year && m.month == month.month);
                            }
                          });
                        },
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
              ElevatedButton(
                onPressed: selectedMonths.isEmpty ? null : () {
                  final filtered = workerPayments.where((p) {
                    return selectedMonths.any((m) => m.year == p.targetMonth.year && m.month == p.targetMonth.month);
                  }).toList();

                  filtered.sort((a, b) => b.date.compareTo(a.date));
                  
                  final period = selectedMonths.length == 1 
                      ? DateFormat('MMMM yyyy').format(selectedMonths.first)
                      : 'Multiple Months';

                  ReceiptService.printSalaryHistory(staff, filtered, period: period);
                  Navigator.pop(context);
                },
                child: const Text('PRINT STATEMENT'),
              ),
            ],
          ),
        ),
      );
    }
  }
}
