import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/user_provider.dart';
import '../../services/product_service.dart';
import '../../services/system_provider.dart';
import '../../models/user_model.dart';
import '../../models/product.dart';
import '../../models/system_models.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/passcode_guard.dart';
import '../../services/offline_sync_service.dart';
import '../../services/sale_provider.dart';
import '../../services/auth_provider.dart';

class SuperAdminScreen extends ConsumerWidget {
  const SuperAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(userProvider);
    final productsAsync = ref.watch(productsFutureProvider);
    final auditLogs = ref.watch(auditLogProvider);
    final isLockdown = ref.watch(systemLockdownProvider);
    
    final pendingUsers = users.where((u) => u.status == AccountStatus.pending).toList();

    return PasscodeGuard(
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0B), // Cyber/Dark theme for Super Admin
        appBar: MainAppBar(
          title: 'ROOT ACCESS: SUPER ADMIN', 
          showMenuButton: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: () async {
                await GlobalLogout.perform(ref);
                if (context.mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
              tooltip: 'Log Out System',
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(auditLogProvider.notifier).refreshLogs(),
              tooltip: 'Sync Global State',
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusHeader(context, isLockdown),
              const SizedBox(height: AppSpacing.xl),
              
              if (pendingUsers.isNotEmpty) ...[
                _buildApprovalSection(context, ref, pendingUsers),
                const SizedBox(height: AppSpacing.xl),
              ],

              _buildSectionTitle('Data Recovery Hub', Icons.restore_from_trash, Colors.green),
              const SizedBox(height: AppSpacing.m),
              productsAsync.when(
                data: (products) => _buildDeletedProductsList(context, ref, products.where((p) => p.isDeleted).toList()),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading stock: $e', style: const TextStyle(color: Colors.red)),
              ),

              const SizedBox(height: AppSpacing.xl),
              _buildSectionTitle('System Control Panel', Icons.settings_input_component, Colors.blue),
              const SizedBox(height: AppSpacing.m),
              _buildControlPanel(context, ref, isLockdown),
              
              const SizedBox(height: AppSpacing.xl),
              _buildSectionTitle('Live Activity Stream', Icons.analytics_outlined, Colors.purple),
              const SizedBox(height: AppSpacing.m),
              _buildGlobalLogs(auditLogs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildApprovalSection(BuildContext context, WidgetRef ref, List<UserAccount> pending) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.m),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Awaiting Account Approvals', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...pending.map((user) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(child: Text(user.firstName[0])),
            title: Text(user.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: Text(user.email, style: const TextStyle(color: Colors.white54, fontSize: 10), overflow: TextOverflow.ellipsis),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  onPressed: () => ref.read(userProvider.notifier).approveUser(user.id),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red), 
                  onPressed: () => ref.read(userProvider.notifier).deleteUser(user.id),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildDeletedProductsList(BuildContext context, WidgetRef ref, List<Product> deleted) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1E), borderRadius: BorderRadius.circular(AppRadius.m), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Deleted Stock Items', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const Divider(color: Colors.white10, height: 24),
          if (deleted.isEmpty) 
            const Padding(padding: EdgeInsets.all(20), child: Text('No deleted products.', style: TextStyle(color: Colors.white24, fontSize: 12)))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: deleted.length,
              itemBuilder: (context, index) {
                final product = deleted[index];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(product.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(product.category, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  trailing: IconButton(
                    icon: const Icon(Icons.settings_backup_restore, color: Colors.blue, size: 20),
                    tooltip: 'Restore Product',
                    onPressed: () => ref.read(productsFutureProvider.notifier).restoreProduct(product.id),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(BuildContext context, bool isLockdown) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: (isLockdown ? Colors.orange : Colors.red).withValues(alpha: 0.1),
        border: Border.all(color: (isLockdown ? Colors.orange : Colors.red).withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.m),
      ),
      child: Row(
        children: [
          Icon(isLockdown ? Icons.gpp_maybe : Icons.security, color: isLockdown ? Colors.orange : Colors.red, size: 32),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLockdown ? 'Emergency Lockdown Active' : 'Elevated Privileges Active', 
                  style: TextStyle(color: isLockdown ? Colors.orange : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)
                ),
                Text(
                  isLockdown 
                    ? 'All system access is currently restricted to Root.' 
                    : 'System-wide data recovery and root configuration enabled.', 
                  style: const TextStyle(color: Colors.white70, fontSize: 11)
                ),
              ],
            ),
          ),
          if (!ResponsiveLayout.isMobile(context))
            const Text('ID: SU-ROOT-001', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildControlPanel(BuildContext context, WidgetRef ref, bool isLockdown) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth < 600 ? constraints.maxWidth : (constraints.maxWidth - AppSpacing.m) / 2;
        return Wrap(
          spacing: AppSpacing.m,
          runSpacing: AppSpacing.m,
          children: [
            _controlBtn(
              context,
              'Purge Cache', 
              Icons.cleaning_services, 
              Colors.orange, 
              width,
              onTap: () => _confirmPurge(context),
            ),
            _controlBtn(
              context,
              'Database Backup', 
              Icons.backup, 
              Colors.blue, 
              width,
              onTap: () => _handleBackup(context, ref),
            ),
            _controlBtn(
              context,
              'Staff Directory', 
              Icons.people_outline, 
              Colors.purple, 
              width,
              onTap: () => Navigator.pushReplacementNamed(context, '/admin/staff'),
            ),
            _controlBtn(
              context,
              isLockdown ? 'End Lockdown' : 'System Lockdown', 
              isLockdown ? Icons.gpp_good : Icons.gpp_maybe, 
              isLockdown ? Colors.green : Colors.red, 
              width,
              onTap: () => _toggleLockdown(context, ref, isLockdown),
            ),
          ],
        );
      }
    );
  }

  Widget _controlBtn(BuildContext context, String label, IconData icon, Color color, double width, {required VoidCallback onTap}) {
    return SizedBox(
      width: width,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A1A1E),
          foregroundColor: color,
          elevation: 0,
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
        ),
      ),
    );
  }

  Widget _buildGlobalLogs(List<AuditLog> logs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: Colors.white10),
      ),
      child: logs.isEmpty 
        ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No recent global activity.', style: TextStyle(color: Colors.white24, fontSize: 12))))
        : ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.take(10).length,
            separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 24),
            itemBuilder: (context, index) {
              final log = logs[index];
              return _logEntry(
                log.userName ?? 'System', 
                log.action.replaceAll('_', ' '), 
                DateFormat('HH:mm:ss').format(log.timestamp)
              );
            },
          ),
    );
  }

  Widget _logEntry(String user, String action, String time) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('[$time]', style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace')),
        const SizedBox(width: 8),
        Text(user, style: const TextStyle(color: AppColors.primaryMaroon, fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(width: 8),
        Expanded(child: Text(action, style: const TextStyle(color: Colors.white70, fontSize: 11))),
      ],
    );
  }

  void _confirmPurge(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('Purge System Cache?', style: TextStyle(color: Colors.orange)),
        content: const Text(
          'This will clear all local data on this device and force a fresh sync from the cloud. Continue?',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await OfflineSyncService.clearAllCache();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared. Restarting data engines...'), backgroundColor: Colors.orange),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('PURGE'),
          ),
        ],
      ),
    );
  }

  void _toggleLockdown(BuildContext context, WidgetRef ref, bool currentStatus) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: Text(currentStatus ? 'End System Lockdown?' : 'ACTIVATE LOCKDOWN?', 
          style: TextStyle(color: currentStatus ? Colors.green : Colors.red)),
        content: Text(
          currentStatus 
            ? 'This will restore standard access for all staff members.'
            : 'DANGER: This will force every device in the company to the security lock screen immediately. Only Root can undo this.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              ref.read(systemLockdownProvider.notifier).state = !currentStatus;
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(currentStatus ? 'Lockdown Terminated.' : 'SYSTEM-WIDE LOCKDOWN ACTIVE.'),
                  backgroundColor: currentStatus ? Colors.green : Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: currentStatus ? Colors.green : Colors.red, 
              foregroundColor: Colors.white
            ),
            child: Text(currentStatus ? 'RESTORE ACCESS' : 'EXECUTE LOCKDOWN'),
          ),
        ],
      ),
    );
  }

  void _handleBackup(BuildContext context, WidgetRef ref) {
    final sales = ref.read(saleHistoryProvider);
    final users = ref.read(userProvider);

    final StringBuffer csv = StringBuffer();
    csv.writeln('Mi-Corazon System Backup - ${DateTime.now()}');
    csv.writeln('\n--- SALES HISTORY ---');
    csv.writeln('ID,Date,Total,Status,SoldBy');
    for (var s in sales) {
      csv.writeln('${s.id},${s.timestamp},${s.totalAmount},${s.status.name},${s.cashierName}');
    }

    csv.writeln('\n--- STAFF DIRECTORY ---');
    csv.writeln('Name,Role,Branch,Status');
    for (var u in users) {
      csv.writeln('${u.name},${u.role.name},${u.branchCode},${u.status.name}');
    }

    Clipboard.setData(ClipboardData(text: csv.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Full system state copied to clipboard as CSV.')),
    );
  }
}
