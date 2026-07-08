import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/user_provider.dart';
import '../../services/product_service.dart';
import '../../models/user_model.dart';
import '../../models/product.dart';
import '../../widgets/responsive_layout.dart';

class SuperAdminScreen extends ConsumerWidget {
  const SuperAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(userProvider);
    final productsAsync = ref.watch(productsFutureProvider);
    final isMobile = ResponsiveLayout.isMobile(context);
    
    final pendingUsers = users.where((u) => u.status == AccountStatus.pending).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0B), // Cyber/Dark theme for Super Admin
      appBar: MainAppBar(
        title: 'ROOT ACCESS: SUPER ADMIN', 
        showMenuButton: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(context),
            const SizedBox(height: AppSpacing.xl),
            
            if (pendingUsers.isNotEmpty) ...[
              _buildApprovalSection(context, ref, pendingUsers),
              const SizedBox(height: AppSpacing.xl),
            ],

            _buildSectionTitle('Data Recovery Hub', Icons.restore_from_trash, Colors.green),
            const SizedBox(height: AppSpacing.m),
            Flex(
              direction: isMobile ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: isMobile ? 0 : 1,
                  child: productsAsync.when(
                    data: (products) => _buildDeletedProductsList(context, ref, products.where((p) => p.isDeleted).toList()),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error loading stock: $e', style: const TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
            _buildSectionTitle('System Control Panel', Icons.settings_input_component, Colors.blue),
            const SizedBox(height: AppSpacing.m),
            _buildControlPanel(),
            
            const SizedBox(height: AppSpacing.xl),
            _buildSectionTitle('Live Activity Stream', Icons.analytics_outlined, Colors.purple),
            const SizedBox(height: AppSpacing.m),
            _buildGlobalLogs(),
          ],
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
            leading: CircleAvatar(child: Text(user.firstName[0])),
            title: Text(user.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(user.email, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: () => ref.read(userProvider.notifier).approveUser(user.id),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Approve'),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => ref.read(userProvider.notifier).deleteUser(user.id)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildDeletedProductsList(BuildContext context, WidgetRef ref, List<Product> deleted) {
    return Container(
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
              itemCount: deleted.length,
              itemBuilder: (context, index) {
                final product = deleted[index];
                return ListTile(
                  dense: true,
                  title: Text(product.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Widget _buildStatusHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.m),
      ),
      child: const Row(
        children: [
          Icon(Icons.security, color: Colors.red, size: 32),
          SizedBox(width: AppSpacing.m),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Elevated Privileges Active', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
              Text('System-wide data recovery and root configuration enabled.', style: TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          Spacer(),
          Text('ID: SU-ROOT-001', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      children: [
        _controlBtn('Purge Cache', Icons.cleaning_services, Colors.orange),
        _controlBtn('Database Backup', Icons.backup, Colors.blue),
        _controlBtn('Reset Passwords', Icons.lock_reset, Colors.purple),
        _controlBtn('System Lockdown', Icons.gpp_maybe, Colors.red),
      ],
    );
  }

  Widget _controlBtn(String label, IconData icon, Color color) {
    return SizedBox(
      width: 200,
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1A1A1E),
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.3)),
          padding: const EdgeInsets.all(20),
        ),
      ),
    );
  }

  Widget _buildGlobalLogs() {
    final now = DateTime.now();
    final format = DateFormat('HH:mm:ss');
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          _logEntry('Admin', 'Deleted User Maria Santos', format.format(now.subtract(const Duration(minutes: 1)))),
          _logEntry('Admin', 'Deleted Stock Item "Goat Meat"', format.format(now.subtract(const Duration(minutes: 5)))),
          _logEntry('System', 'Automatic Backup success', format.format(now.subtract(const Duration(hours: 1)))),
        ],
      ),
    );
  }

  Widget _logEntry(String user, String action, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Text('[$time]', style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Text(user, style: const TextStyle(color: AppColors.primaryMaroon, fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(width: 8),
          Expanded(child: Text(action, style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ],
      ),
    );
  }
}
