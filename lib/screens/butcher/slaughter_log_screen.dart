import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../services/butcher_service.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../services/label_service.dart';
import '../../widgets/status_chip.dart';
import '../../models/butcher_models.dart';

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
                          DataColumn(label: Text('Live Wt.')),
                          DataColumn(label: Text('Meat Wt.')),
                          DataColumn(label: Text('Yield %')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: filteredLogs.map((SlaughterLog log) => DataRow(cells: [
                          DataCell(SizedBox(width: 80, child: Text(log.id.substring(0,8), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                          DataCell(SizedBox(width: 100, child: Text(log.tagNumber ?? 'UUID: ${log.animalId.substring(0,8)}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                          DataCell(Text(log.type.displayName, style: const TextStyle(fontSize: 11))),
                          DataCell(Text('${log.liveWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10))),
                          DataCell(Text('${log.meatWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontSize: 10))),
                          DataCell(Text('${log.yieldPercentage.toStringAsFixed(1)}%',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accentGreen))),
                          DataCell(StatusChip(
                            label: log.status.name.toUpperCase(),
                            color: log.status == SlaughterStatus.completed 
                                ? Colors.green 
                                : (log.status == SlaughterStatus.slaughtering 
                                    ? Colors.red 
                                    : (log.status == SlaughterStatus.cleaned ? Colors.blue : Colors.orange)),
                          )),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildActions(log),
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

  Widget _buildActions(SlaughterLog log) {
    if (log.status == SlaughterStatus.processed) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified, color: Colors.blue, size: 18),
          SizedBox(width: 4),
          Text('PROCESSED', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
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
