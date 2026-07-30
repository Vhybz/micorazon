import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../services/butcher_service.dart';
import '../../models/butcher_models.dart';
import '../../widgets/role_pop_scope.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(slaughterLogsProvider);
    final wasteAsync = ref.watch(butcherWasteProvider);

    return RolePopScope(
      currentRoute: 'butcher:reports',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: AppSpacing.l),
            
            logsAsync.when(
              data: (logs) {
                final waste = wasteAsync.value ?? [];
                return _buildAnalyticsContent(context, logs, waste);
              },
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Center(child: Text('Error loading reports: $err', style: const TextStyle(color: Colors.red))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Operational Analytics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      Text('Butcher unit efficiency and yield analysis', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                if (!isMobile) _buildHeaderButtons(context),
              ],
            ),
            if (isMobile) ...[
              const SizedBox(height: AppSpacing.m),
              _buildHeaderButtons(context),
            ],
          ],
        );
      }
    );
  }

  Widget _buildHeaderButtons(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: () {}, 
          icon: const Icon(Icons.filter_list, size: 16),
          label: const Text('Filter', style: TextStyle(fontSize: 12)),
        ),
        ElevatedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Generating PDF Report...'))
            );
          },
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Export PDF', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsContent(BuildContext context, List<SlaughterLog> logs, List<Map<String, dynamic>> waste) {
    final completed = logs.where((l) => l.status == SlaughterStatus.completed || l.status == SlaughterStatus.processed).toList();
    
    double avgYieldRate = 0;
    if (completed.isNotEmpty) {
      final totalIntake = completed.fold(0.0, (sum, l) => sum + l.liveWeight);
      final totalYield = completed.fold(0.0, (sum, l) => sum + l.meatWeight);
      avgYieldRate = totalIntake > 0 ? (totalYield / totalIntake) * 100 : 0;
    }

    final totalWasteWeight = waste.fold(0.0, (sum, w) => sum + (double.tryParse(w['weight']?.toString() ?? '0') ?? 0.0));
    final totalIntakeAll = logs.fold(0.0, (sum, l) => sum + l.liveWeight);
    final wasteRatio = totalIntakeAll > 0 ? (totalWasteWeight / totalIntakeAll) * 100 : 0.0;

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        GridView.count(
          crossAxisCount: isMobile ? 2 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.m,
          mainAxisSpacing: AppSpacing.m,
          childAspectRatio: isMobile ? 1.2 : 1.8,
          children: [
            _buildResponsiveKPI(
              context,
              title: 'Avg. Yield Rate', 
              value: '${avgYieldRate.toStringAsFixed(1)}%', 
              icon: Icons.auto_graph, 
              color: Colors.green, 
            ),
            _buildResponsiveKPI(
              context,
              title: 'Total Waste', 
              value: '${totalWasteWeight.toStringAsFixed(1)} kg', 
              icon: Icons.delete_sweep_outlined, 
              color: Colors.red, 
            ),
            _buildResponsiveKPI(
              context,
              title: 'Waste Ratio', 
              value: '${wasteRatio.toStringAsFixed(1)}%', 
              icon: Icons.analytics_outlined, 
              color: Colors.orange, 
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool isTablet = constraints.maxWidth < 900;
            if (isTablet) {
              return Column(
                children: [
                  _buildYieldEfficiencyCard(context, completed),
                  const SizedBox(height: AppSpacing.l),
                  _buildRecentAnimalsCard(context, logs),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildYieldEfficiencyCard(context, completed),
                ),
                const SizedBox(width: AppSpacing.l),
                Expanded(
                  flex: 1,
                  child: _buildRecentAnimalsCard(context, logs),
                ),
              ],
            );
          }
        ),
      ],
    );
  }

  Widget _buildYieldEfficiencyCard(BuildContext context, List<SlaughterLog> logs) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yield Efficiency by Animal Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
            const SizedBox(height: AppSpacing.m),
            if (logs.isEmpty)
              Center(child: Padding(padding: const EdgeInsets.all(40), child: Text('No data for analysis yet.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))))
            else
              ...AnimalType.values.map((type) {
                final animals = logs.where((l) => l.type == type).toList();
                if (animals.isEmpty) return const SizedBox.shrink();
                
                final totalWeight = animals.fold(0.0, (sum, a) => sum + a.liveWeight);
                final totalYield = animals.fold(0.0, (sum, a) => sum + a.meatWeight);
                final efficiency = totalWeight > 0 ? (totalYield / totalWeight) : 0.0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(type.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Text('${(efficiency * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accentGreen)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: efficiency,
                          minHeight: 10,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          color: AppColors.accentGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Sample size: ${animals.length} animals', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentAnimalsCard(BuildContext context, List<SlaughterLog> logs) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Feedstocks', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            const SizedBox(height: AppSpacing.m),
            if (logs.isEmpty)
              Text('No records.', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant))
            else
              ...logs.take(5).map((l) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                  radius: 16,
                  child: Icon(Icons.pets, size: 14, color: theme.colorScheme.primary),
                ),
                title: Text(l.tagNumber ?? l.id.substring(l.id.length - 8).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
                subtitle: Text(l.type.displayName, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                trailing: Text('${l.liveWeight.toInt()} kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveKPI(BuildContext context, {required String title, required String value, required IconData icon, required Color color}) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
