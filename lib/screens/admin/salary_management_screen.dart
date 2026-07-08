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

class SalaryManagementScreen extends ConsumerWidget {
  const SalaryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    // Keep history loaded and active
    ref.watch(salaryHistoryProvider); 

    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final users = ref.watch(userProvider);
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
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: constraints.maxWidth < 600 ? 0.95 : 1.5, // Even taller for mobile
          ),
          itemCount: staffList.length,
          itemBuilder: (context, index) {
            final staff = staffList[index];
            // Ensure cards take minimum needed space
            return IntrinsicHeight(
              child: _buildSalaryCard(context, ref, staff),
            );
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
      elevation: isDueSoon && !isPaidThisMonth ? 8 : 1,
      shadowColor: isDueSoon ? Colors.red.withValues(alpha: 0.3) : Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDueSoon && !isPaidThisMonth 
          ? const BorderSide(color: Colors.red, width: 2) 
          : BorderSide(color: theme.dividerColor),
      ),
      child: Container(
        padding: const EdgeInsets.all(12), // Reduced from 16
        child: Column(
          mainAxisSize: MainAxisSize.min, // Changed from default
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, // Reduced from 40
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2), width: 1),
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
                const SizedBox(width: 8), // Reduced from 12
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(staff.role.name.toUpperCase(), style: TextStyle(fontSize: 8, color: theme.colorScheme.primary, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
                if (isPaidThisMonth)
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                IconButton(
                  icon: const Icon(Icons.edit_note, size: 18, color: Colors.blue),
                  onPressed: () => _showEditSalaryDialog(context, ref, staff),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Edit Salary Settings',
                ),
              ],
            ),
            const Divider(height: 16), // Reduced from 24
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BASE SALARY', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(staff.salaryAmount != null ? '₵${staff.salaryAmount!.toStringAsFixed(0)}' : 'NOT SET', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: staff.salaryAmount == null ? Colors.red : Colors.black)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('PAY DAY', style: TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text(staff.salaryDay != null ? 'Day ${staff.salaryDay}' : 'N/A', 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8), // Reduced from 12
            Row(
              children: [
                _salaryActionButton(
                  context, 
                  label: 'ADVANCE', 
                  color: Colors.orange, 
                  onPressed: () => _handlePayment(context, ref, staff, isAdvance: true)
                ),
                const SizedBox(width: 4), // Reduced from 8
                _salaryActionButton(
                  context, 
                  label: isPaidThisMonth ? 'PAID' : 'PAY', 
                  color: isPaidThisMonth ? Colors.grey : Colors.green, 
                  onPressed: isPaidThisMonth ? null : () => _handlePayment(context, ref, staff, isAdvance: false)
                ),
              ],
            ),
            const SizedBox(height: 6), // Reduced from 8
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showMonthSelector(context, ref, staff),
                    icon: const Icon(Icons.history_rounded, size: 12),
                    label: const Text('HISTORY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      side: BorderSide(color: theme.dividerColor),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ReceiptService.printPayslip(
                      staff, 
                      staff.salaryAmount ?? 0.0, 
                      false
                    ),
                    icon: const Icon(Icons.receipt_rounded, size: 12),
                    label: const Text('REPRINT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      side: BorderSide(color: theme.dividerColor),
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

  void _showMonthSelector(BuildContext context, WidgetRef ref, UserAccount staff) async {
    final String targetId = staff.id.trim().toLowerCase();
    
    // 1. Force a cloud refresh before searching to ensure we aren't looking at old local cache
    await ref.read(salaryHistoryProvider.notifier).loadAll();
    
    if (!context.mounted) return;

    // 2. Search with normalized IDs and partial matching for safety
    final allPayments = ref.read(salaryHistoryProvider);
    var workerPayments = allPayments.where((p) {
      final String pId = p.userId.trim().toLowerCase();
      // Match if exact OR if one contains the other (Supabase sometimes prefixes UUIDs)
      return pId == targetId || pId.contains(targetId) || targetId.contains(pId);
    }).toList();
    
    debugPrint('Salary History Diagnostic:');
    debugPrint(' - Searching for Staff ID: "$targetId"');
    debugPrint(' - Total records in database: ${allPayments.length}');
    debugPrint(' - Matching records found: ${workerPayments.length}');

    // Extract unique Year-Month combinations that actually have payments
    final Set<String> uniqueMonthsSet = {};
    final List<DateTime> availableMonths = [];
    
    for (var p in workerPayments) {
      final key = "${p.date.year}-${p.date.month}";
      if (!uniqueMonthsSet.contains(key)) {
        uniqueMonthsSet.add(key);
        availableMonths.add(DateTime(p.date.year, p.date.month, 1));
      }
    }
    
    availableMonths.sort((a, b) => b.compareTo(a)); // Newest months first
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
            title: Text('Select Payment Months', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    return selectedMonths.any((m) => m.year == p.date.year && m.month == p.date.month);
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

  Widget _salaryActionButton(BuildContext context, {required String label, required Color color, VoidCallback? onPressed}) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color, 
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10), // Slightly smaller padding
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
    // When not an advance, calculate deductions automatically
    double initialAmount = isAdvance ? 0.0 : (staff.salaryAmount ?? 0.0);
    double totalAdvancesDetected = 0.0;

    if (!isAdvance && staff.salaryAmount != null) {
      final allPayments = ref.read(salaryHistoryProvider);
      final lastFullSalaryDate = staff.lastSalaryDate ?? DateTime(2000);
      
      // Calculate advances taken since last full salary
      // We use a small buffer for the date to avoid missing same-day advances if any, 
      // but usually lastSalaryDate is the end of the previous cycle.
      totalAdvancesDetected = allPayments
          .where((p) => p.userId == staff.id && p.isAdvance && p.date.isAfter(lastFullSalaryDate))
          .fold(0.0, (sum, p) => sum + p.amount);
          
      if (totalAdvancesDetected > 0) {
        initialAmount = (staff.salaryAmount! - totalAdvancesDetected).clamp(0.0, double.infinity);
      }
    }

    final amountController = TextEditingController(text: initialAmount > 0 ? initialAmount.toStringAsFixed(2) : '');
    bool isProcessing = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Text(isAdvance ? 'Salary Advance' : 'Confirm Payment'), // Shortened title
          content: SingleChildScrollView( // Prevent keyboard overflow
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paying ${staff.name}'),
                if (totalAdvancesDetected > 0 && !isAdvance) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.s),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Base Salary:', style: TextStyle(fontSize: 11)),
                            Text('₵${staff.salaryAmount!.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Advances Taken:', style: TextStyle(fontSize: 11, color: Colors.red)),
                            Text('-₵${totalAdvancesDetected.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Proposed Net:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            Text('₵${initialAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₵ ', border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                  enabled: !isProcessing,
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

                setState(() => isProcessing = true);

                try {
                  // 1. Save to database (Status update in user profile)
                  await ref.read(userProvider.notifier).updateSalary(
                    staff.id, 
                    amount: staff.salaryAmount, 
                    day: staff.salaryDay, 
                    lastPaid: isAdvance ? staff.lastSalaryDate : DateTime.now(),
                    isAdvance: isAdvance,
                  );

                  // 2. Record individual payment history
                  String note = isAdvance ? 'Salary Advance' : 'Full Monthly Salary';
                  if (!isAdvance && totalAdvancesDetected > 0) {
                    note += ' (Deducted ₵${totalAdvancesDetected.toStringAsFixed(2)} in advances)';
                  }

                  final record = SalaryRecord(
                    id: UuidUtils.generate(),
                    userId: staff.id,
                    amount: amount,
                    isAdvance: isAdvance,
                    date: DateTime.now(),
                    note: note,
                  );
                  
                  await ref.read(salaryHistoryProvider.notifier).addPayment(record);
                  
                  // 3. Send Official Salary SMS
                  await SmsService.sendSalarySms(
                    phone: staff.phone ?? '', 
                    firstName: staff.firstName, 
                    amount: amount, 
                    isAdvance: isAdvance
                  );
                  
                  // 4. Automatically print payslip
                  await ReceiptService.printPayslip(staff, amount, isAdvance);

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
                    setState(() => isProcessing = false);
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
}
