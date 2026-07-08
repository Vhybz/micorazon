import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../services/butcher_service.dart';
import '../../widgets/status_chip.dart';
import '../../services/label_service.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../models/butcher_models.dart';
import '../../widgets/responsive_layout.dart';

class BatchManagementScreen extends ConsumerStatefulWidget {
  const BatchManagementScreen({super.key});

  @override
  ConsumerState<BatchManagementScreen> createState() => _BatchManagementScreenState();
}

class _BatchManagementScreenState extends ConsumerState<BatchManagementScreen> {
  String _searchQuery = '';
  String? _statusFilter;
  String? _typeFilter;

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(meatBatchesProvider);
    final recentCuts = ref.watch(recentCutsProvider).value ?? [];
    final wasteRecords = ref.watch(butcherWasteProvider).value ?? [];
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Batch Management Hub', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('Audit yield, track aging, and manage production lifecycle.', 
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              if (ResponsiveLayout.isMobile(context))
                IconButton(
                  onPressed: () => _showGlobalAuditDialog(context, ref),
                  icon: const Icon(Icons.analytics_outlined, color: AppColors.primaryMaroon),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _showGlobalAuditDialog(context, ref),
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Production Audit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          
          _buildFilters(theme),
          const SizedBox(height: AppSpacing.l),

          Expanded(
            child: batchesAsync.when(
              data: (batches) {
                final filteredBatches = batches.where((b) {
                  final matchesSearch = b.id.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                                      b.meatType.toLowerCase().contains(_searchQuery.toLowerCase());
                  final matchesStatus = _statusFilter == null || b.status == _statusFilter;
                  final matchesType = _typeFilter == null || b.meatType == _typeFilter;
                  return matchesSearch && matchesStatus && matchesType;
                }).toList();

                if (filteredBatches.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 48, color: theme.disabledColor),
                        const SizedBox(height: 16),
                        const Text('No matching batches found.'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredBatches.length,
                  itemBuilder: (context, index) {
                    final batch = filteredBatches[index];
                    final batchCuts = recentCuts.where((c) => c.batchId == batch.id).toList();
                    final batchWaste = wasteRecords.where((w) => w['batch_id'] == batch.id);
                    
                    final processedWeight = batchCuts.fold(0.0, (sum, c) => sum + c.weight);
                    final wastedWeight = batchWaste.fold(0.0, (sum, w) => sum + (double.tryParse(w['weight']?.toString() ?? '0') ?? 0));
                    final totalAccounted = processedWeight + wastedWeight;
                    final yieldEfficiency = (totalAccounted / batch.weight) * 100;
                    
                    final agingDays = DateTime.now().difference(batch.createdAt).inDays;
                    final isAging = agingDays > 7;

                    return _buildBatchAuditCard(context, batch, yieldEfficiency, agingDays, isAging);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  ThemeData get theme => Theme.of(context);

  Widget _buildFilters(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Wrap(
        spacing: AppSpacing.m,
        runSpacing: AppSpacing.m,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: ResponsiveLayout.isMobile(context) ? double.infinity : 250,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search Batch ID...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
              ),
            ),
          ),
          _filterDropdown('Status', _statusFilter, ['transporting', 'received', 'preparing', 'mincing', 'cutting', 'packaging', 'frozen'], (v) => setState(() => _statusFilter = v)),
          _filterDropdown('Meat Type', _typeFilter, ['Beef', 'Pork', 'Chicken', 'Goat', 'Sheep'], (v) => setState(() => _typeFilter = v)),
          if (_searchQuery.isNotEmpty || _statusFilter != null || _typeFilter != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _searchQuery = '';
                _statusFilter = null;
                _typeFilter = null;
              }),
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear'),
            ),
        ],
      ),
    );
  }

  Widget _filterDropdown(String label, String? value, List<String> options, Function(String?) onChanged) {
    final bool isMobile = ResponsiveLayout.isMobile(context);
    return SizedBox(
      width: isMobile ? 140 : 160,
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          ...options.map((o) => DropdownMenuItem(
            value: o, 
            child: Text(o.toUpperCase(), 
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            )
          )),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildBatchAuditCard(BuildContext context, MeatBatch batch, double yieldEff, int aging, bool isAging) {
    final Color yieldColor = yieldEff > 95 ? Colors.green : (yieldEff > 85 ? Colors.orange : Colors.red);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: InkWell(
        onTap: () => _showBatchPassport(context, batch),
        borderRadius: BorderRadius.circular(AppRadius.m),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Row(
            children: [
              _buildAgingIndicator(aging, isAging),
              const SizedBox(width: AppSpacing.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(batch.meatType.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        const SizedBox(width: 12),
                        StatusChip(label: batch.status.toUpperCase(), color: _getStatusColor(batch.status)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('BATCH: ${batch.id}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _miniInfo(Icons.scale_outlined, '${batch.weight}kg Intake'),
                        const SizedBox(width: 16),
                        _miniInfo(Icons.calendar_today_outlined, DateFormat('MMM dd').format(batch.createdAt)),
                        const SizedBox(width: 16),
                        _miniInfo(Icons.person_outline, batch.source.owner),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('YIELD EFFICIENCY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                  Text('${yieldEff.toStringAsFixed(1)}%', 
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: yieldColor)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print_outlined, size: 20),
                        onPressed: () => LabelService.printBatchLabel(batch),
                        tooltip: 'Print Batch Label',
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgingIndicator(int days, bool isAging) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: isAging ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: isAging ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$days', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isAging ? Colors.red : Colors.green)),
          const Text('DAYS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _miniInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return Colors.green;
      case 'transporting': return Colors.blue;
      case 'received': return Colors.teal;
      case 'frozen': return Colors.cyan;
      default: return Colors.orange;
    }
  }

  void _showBatchPassport(BuildContext context, MeatBatch batch) {
    final recentCuts = ref.read(recentCutsProvider).value ?? [];
    final wasteRecords = ref.read(butcherWasteProvider).value ?? [];
    final batchCuts = recentCuts.where((c) => c.batchId == batch.id).toList();
    final batchWaste = wasteRecords.where((w) => w['batch_id'] == batch.id).toList();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        titlePadding: EdgeInsets.zero,
        title: Container(
          padding: const EdgeInsets.all(AppSpacing.l),
          decoration: const BoxDecoration(
            color: AppColors.primaryMaroon,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.l)),
          ),
          child: Row(
            children: [
              const Icon(Icons.assignment_outlined, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Batch Digital Passport', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('ID: ${batch.id}', style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace')),
                  ],
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
            ],
          ),
        ),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPassportSection('ORIGIN & INTAKE', [
                  _passportRow('Animal Type', batch.meatType),
                  _passportRow('Intake Weight', '${batch.weight} kg'),
                  _passportRow('Source Farm', batch.source.name),
                  _passportRow('Supplier/Owner', batch.source.owner),
                  _passportRow('Received On', DateFormat('MMMM dd, yyyy HH:mm').format(batch.createdAt)),
                ]),
                const Divider(height: 32),
                _buildPassportSection('PRODUCTION BREAKDOWN', [
                  if (batchCuts.isEmpty) 
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No parts recorded yet.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)))
                  else
                    ...batchCuts.map((c) => _passportRow(c.name, '${c.weight} kg')),
                ]),
                const Divider(height: 32),
                _buildPassportSection('WASTE & LOSS', [
                  if (batchWaste.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No waste recorded.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12)))
                  else
                    ...batchWaste.map((w) => _passportRow(w['reason'] ?? 'Loss', '${w['weight']} kg')),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          if (batch.status == 'completed')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.stockTransfer);
              },
              icon: const Icon(Icons.local_shipping_outlined, color: Colors.white),
              label: const Text('PREPARE STOCK TRANSFER', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
            )
          else
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.stockTransfer);
              },
              icon: const Icon(Icons.local_shipping_outlined, color: Colors.blue),
              label: const Text('Move to Transfer', style: TextStyle(color: Colors.blue)),
            ),
          TextButton.icon(
            onPressed: () => LabelService.printBatchLabel(batch),
            icon: const Icon(Icons.print),
            label: const Text('Master Label'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPassportSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: AppColors.primaryMaroon, letterSpacing: 1.1)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _passportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _showGlobalAuditDialog(BuildContext context, WidgetRef ref) {
    // This could show a summary of all active meat sitting in storage
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Production Audit Summary'),
        content: const Text('This module provides a cross-batch analysis of total inventory yield. Coming soon in v2.2.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }
}
