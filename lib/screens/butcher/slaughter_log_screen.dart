import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../services/butcher_service.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../services/label_service.dart';
import '../../widgets/status_chip.dart';
import '../../models/butcher_models.dart';
import '../../services/user_provider.dart';
import '../../models/user_model.dart';

class SlaughterLogScreen extends ConsumerStatefulWidget {
  const SlaughterLogScreen({super.key});

  @override
  ConsumerState<SlaughterLogScreen> createState() => _SlaughterLogScreenState();
}

class _SlaughterLogScreenState extends ConsumerState<SlaughterLogScreen> {
  String _searchQuery = '';
  AnimalType? _filterType;

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(slaughterLogsProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSmartControls(),
          const SizedBox(height: AppSpacing.l),
          Expanded(
            child: Card(
              child: logsAsync.when(
                data: (List<SlaughterLog> logs) {
                  final filteredLogs = logs.where((log) {
                    final matchesSearch = log.id.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                                          (log.tagNumber?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
                                          log.animalId.toLowerCase().contains(_searchQuery.toLowerCase());
                    final matchesFilter = _filterType == null || log.type == _filterType;
                    return matchesSearch && matchesFilter;
                  }).toList();

                  if (filteredLogs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 48, color: AppColors.textLight),
                          const SizedBox(height: AppSpacing.m),
                          Text('No logs found matching your criteria', style: const TextStyle(color: AppColors.textLight)),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: () => ref.read(slaughterLogsProvider.notifier).loadLogs(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh Now'),
                          ),
                        ],
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        horizontalMargin: AppSpacing.m,
                        columnSpacing: AppSpacing.m,
                        columns: const [
                          DataColumn(label: Text('ID')),
                          DataColumn(label: Text('Tag #')),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Qty')),
                          DataColumn(label: Text('Live Wt.')),
                          DataColumn(label: Text('Meat Wt.')),
                          DataColumn(label: Text('Yield %')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: filteredLogs.map((SlaughterLog log) => DataRow(cells: [
                          DataCell(SizedBox(width: 80, child: Text(log.id.substring(0,8), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                          DataCell(SizedBox(width: 100, child: Text(log.tagNumber ?? 'UUID: ${log.animalId.substring(0,8)}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                          DataCell(Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log.type.displayName, style: const TextStyle(fontSize: 11)),
                              if (log.chickenRangeLabel != null)
                                Text(log.chickenRangeLabel!, 
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.blueGrey))
                              else if (log.type == AnimalType.hardChicken || log.type == AnimalType.softChicken)
                                const Text('NO RANGE - EDIT REQ', 
                                  style: TextStyle(fontSize: 8, color: Colors.red, fontWeight: FontWeight.bold)),
                            ],
                          )),
                          DataCell(Text(log.quantity > 1 ? '${log.quantity}' : '1', style: const TextStyle(fontSize: 10))),
                          DataCell(Text('${log.liveWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10))),
                          DataCell(Text('${log.meatWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10))),
                          DataCell(Text('${log.yieldPercentage.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentGreen))),
                          DataCell(Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              StatusChip(
                                label: log.status.name.toUpperCase(),
                                color: log.status == SlaughterStatus.completed 
                                    ? Colors.green 
                                    : (log.status == SlaughterStatus.slaughtering 
                                        ? Colors.red 
                                        : (log.status == SlaughterStatus.cleaned ? Colors.blue : Colors.orange)),
                              ),
                              if (log.slaughteredBy != null || log.portionedBy != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    log.portionedBy != null ? 'Portioned by: ${log.portionedBy}' : 'Butcher: ${log.slaughteredBy}',
                                    style: const TextStyle(fontSize: 8, fontStyle: FontStyle.italic, color: Colors.grey),
                                  ),
                                ),
                            ],
                          )),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActions(log),
                              const SizedBox(width: 8),
                              _buildIntakeMenu(context, ref, log),
                              if (log.status == SlaughterStatus.completed)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: ElevatedButton.icon(
                                    onPressed: () => LabelService.printSlaughterLabel(log),
                                    icon: const Icon(Icons.print, size: 12),
                                    label: const Text('REPRINT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryMaroon,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                            ],
                          )),
                        ])).toList(),
                      ),
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntakeMenu(BuildContext context, WidgetRef ref, SlaughterLog log) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();
    
    final activeRole = user.activePrimaryRole;
    final canManage = activeRole == UserRole.admin || activeRole == UserRole.superAdmin || activeRole == UserRole.butcher;
    
    // Only allow edit/delete if not processed
    if (!canManage || log.status == SlaughterStatus.processed) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'edit') {
          ref.read(editingSlaughterLogProvider.notifier).state = log;
          ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.animalIntake);
        } else if (val == 'delete') {
          _confirmDeleteIntake(context, ref, log);
        }
      },
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('Edit Intake'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Record', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  void _confirmDeleteIntake(BuildContext context, WidgetRef ref, SlaughterLog log) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Intake Record?'),
        content: Text('Are you sure you want to delete the intake record for Tag #${log.tagNumber}? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              try {
                await ref.read(slaughterLogsProvider.notifier).deleteIntake(log);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Record deleted successfully'), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
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

  Widget _buildActions(SlaughterLog log) {
    if (log.status == SlaughterStatus.processed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_rounded, color: Colors.blue, size: 14),
            SizedBox(width: 8),
            Text('PROCESSED', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
      );
    }

    if (log.status == SlaughterStatus.completed) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: 18),
          SizedBox(width: 4),
          Text('SLAUGHTERED', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      );
    }

    final notifier = ref.read(slaughterLogsProvider.notifier);
    
    // Unified Step-by-Step Progression Button
    final IconData icon;
    final String label;
    final Color color;
    final VoidCallback onPressed;

    switch (log.status) {
      case SlaughterStatus.pending:
        icon = Icons.play_arrow;
        label = 'SLAUGHTER';
        color = Colors.red;
        onPressed = () => notifier.updateStatus(log.id, SlaughterStatus.slaughtering);
        break;
      case SlaughterStatus.slaughtering:
        icon = Icons.cleaning_services;
        label = 'CLEAN';
        color = Colors.blue;
        onPressed = () => notifier.updateStatus(log.id, SlaughterStatus.cleaned);
        break;
      case SlaughterStatus.cleaned:
        icon = Icons.done_all;
        label = 'CARCASS';
        color = Colors.green;
        onPressed = () {
          ref.read(activeSlaughterLogProvider.notifier).state = log;
          ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.carcassBreakdown);
        };
        break;
      default:
        return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Flexible(
        child: Text(label, 
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        minimumSize: const Size(90, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildSmartControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isMobile = constraints.maxWidth < 600;
        return Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppRadius.m),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
            ],
          ),
          child: isMobile 
            ? Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search by ID or Animal ID...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  DropdownButtonFormField<AnimalType>(
                    initialValue: _filterType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: 'All Animals',
                      prefixIcon: const Icon(Icons.filter_list, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Animals', overflow: TextOverflow.ellipsis)),
                      ...AnimalType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _filterType = v),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search by ID or Animal ID...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<AnimalType>(
                      initialValue: _filterType,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'All Animals',
                        prefixIcon: const Icon(Icons.filter_list, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All Animals', overflow: TextOverflow.ellipsis)),
                        ...AnimalType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.displayName, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() => _filterType = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.m),
                  IconButton(
                    onPressed: () => ref.read(slaughterLogsProvider.notifier).loadLogs(),
                    icon: const Icon(Icons.refresh_rounded, color: AppColors.primaryMaroon),
                    tooltip: 'Refresh Logs',
                  ),
                ],
              ),
        );
      }
    );
  }
}
