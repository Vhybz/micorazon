import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../services/system_provider.dart';
import '../../models/user_model.dart';
import '../../models/system_models.dart';
import '../../widgets/role_pop_scope.dart';

class AuditTrailScreen extends ConsumerStatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  ConsumerState<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends ConsumerState<AuditTrailScreen> {
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedAction;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    // Security Guard: Ensure only Admins or Super Admins can access
    final roles = user.activeRoles;
    final hasAccess = roles.contains(UserRole.admin) || roles.contains(UserRole.superAdmin);
    
    if (!hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final auditLogs = ref.watch(auditLogProvider);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/audit';
    final menuItems = ref.watch(menuItemsProvider);

    final filteredLogs = _filterLogs(auditLogs);

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: MainAppBar(
          title: 'System Audit Trail',
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(auditLogProvider.notifier).refreshLogs(),
              tooltip: 'Refresh Logs',
            ),
          ],
        ),
        drawer: isDesktop ? null : Drawer(
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
              child: Column(
                children: [
                  _buildFilterBar(theme),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => ref.read(auditLogProvider.notifier).refreshLogs(),
                      child: filteredLogs.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppSpacing.l),
                              itemCount: filteredLogs.length,
                              itemBuilder: (context, index) => _buildAuditTile(filteredLogs[index]),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        spacing: AppSpacing.m,
        runSpacing: AppSpacing.m,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 250,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search actions or staff...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
              ),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedAction,
              decoration: const InputDecoration(labelText: 'Action Type', isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('All Actions')),
                ...['SALE_CREATED', 'SALE_REVERSED', 'STOCK_ADJUSTED', 'PRODUCT_UPDATED', 'USER_PROMOTED', 'USER_SIGNED_IN', 'USER_SIGNED_OUT']
                    .map((a) => DropdownMenuItem(value: a, child: Text(a.replaceAll('_', ' ')))),
              ],
              onChanged: (v) => setState(() => _selectedAction = v),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _showDateFilterOptions,
            icon: const Icon(Icons.date_range),
            label: Text(_startDate == null 
              ? 'Filter Date' 
              : _startDate!.day == _endDate!.day && _startDate!.month == _endDate!.month && _startDate!.year == _endDate!.year
                ? DateFormat('MM/dd').format(_startDate!)
                : '${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}'),
          ),
          if (_startDate != null || _selectedAction != null || _searchQuery.isNotEmpty)
            IconButton(
              onPressed: () => setState(() {
                _startDate = null;
                _endDate = null;
                _selectedAction = null;
                _searchQuery = '';
              }),
              icon: const Icon(Icons.clear_all),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditTile(AuditLog log) {
    final Color actionColor = _getActionColor(log.action);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(_getActionIcon(log.action), color: actionColor, size: 20),
        ),
        title: Text(log.action.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(
          'By ${log.userName ?? 'System'} • ${DateFormat('MMM dd, HH:mm').format(log.timestamp)}',
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Entity Type', log.entityType),
                if (log.entityId != null) _infoRow('Entity ID', log.entityId!),
                const Divider(height: 24),
                if (log.newData != null) ...[
                  const Text('Changes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  _buildDataCompare(log.oldData, log.newData!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataCompare(Map<String, dynamic>? oldData, Map<String, dynamic> newData) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.s),
      ),
      child: Column(
        children: newData.entries.map((e) {
          final oldValue = oldData?[e.key];
          final newValue = e.value;
          if (oldValue == newValue) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: Text(e.key, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey))),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (oldValue != null)
                        Text('From: $oldValue', style: const TextStyle(fontSize: 11, color: Colors.red, decoration: TextDecoration.lineThrough)),
                      Text('To: $newValue', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Expanded(
            child: Text(
              value, 
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              softWrap: true,
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }

  List<AuditLog> _filterLogs(List<AuditLog> logs) {
    return logs.where((log) {
      final matchesSearch = log.userName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false ||
                           log.action.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                           (log.entityId?.contains(_searchQuery) ?? false);
      final matchesAction = _selectedAction == null || log.action == _selectedAction;
      
      bool matchesDate = true;
      if (_startDate != null && _endDate != null) {
        final start = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        matchesDate = log.timestamp.isAfter(start.subtract(const Duration(seconds: 1))) && 
                      log.timestamp.isBefore(end.add(const Duration(seconds: 1)));
      }
      return matchesSearch && matchesAction && matchesDate;
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  Future<void> _showDateFilterOptions() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Today'),
            onTap: () {
              final now = DateTime.now();
              setState(() {
                _startDate = now;
                _endDate = now;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Yesterday'),
            onTap: () {
              final yesterday = DateTime.now().subtract(const Duration(days: 1));
              setState(() {
                _startDate = yesterday;
                _endDate = yesterday;
              });
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Specific Day'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await showDatePicker(
                context: context,
                initialDate: _startDate ?? DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _startDate = picked;
                  _endDate = picked;
                });
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Date Range'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: (_startDate != null && _endDate != null) 
                  ? DateTimeRange(start: _startDate!, end: _endDate!) 
                  : null,
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() {
                  _startDate = picked.start;
                  _endDate = picked.end;
                });
              }
            },
          ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }

  Color _getActionColor(String action) {
    if (action.contains('REVERTED') || action.contains('DELETE') || action.contains('SIGNED_OUT')) return Colors.red;
    if (action.contains('CREATED') || action.contains('RESTORED') || action.contains('SIGNED_IN')) return Colors.green;
    if (action.contains('UPDATED') || action.contains('ADJUSTED')) return Colors.blue;
    return Colors.orange;
  }

  IconData _getActionIcon(String action) {
    if (action.contains('SALE')) return Icons.receipt_long;
    if (action.contains('STOCK')) return Icons.inventory_2;
    if (action.contains('SIGNED_IN')) return Icons.login_rounded;
    if (action.contains('SIGNED_OUT')) return Icons.logout_rounded;
    if (action.contains('USER')) return Icons.person;
    return Icons.history;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security_rounded, size: 64, color: Theme.of(context).dividerColor),
          const SizedBox(height: 16),
          const Text('No audit logs found matching your filters.', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
