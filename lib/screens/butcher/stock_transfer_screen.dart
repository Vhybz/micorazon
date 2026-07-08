import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/uuid_utils.dart';
import '../../core/utils.dart';
import '../../widgets/status_chip.dart';
import '../../services/transfer_provider.dart';
import '../../services/butcher_service.dart';
import '../../models/transfer_models.dart';
import '../../models/butcher_models.dart';
import '../../models/branch_model.dart';
import '../../services/branch_provider.dart';
import '../../services/label_service.dart';
import '../../services/notification_service.dart';
import '../../services/product_service.dart';
import '../../services/sms_service.dart';
import '../../services/user_provider.dart';

class StockTransferScreen extends ConsumerStatefulWidget {
  const StockTransferScreen({super.key});

  @override
  ConsumerState<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends ConsumerState<StockTransferScreen> {
  String _searchQuery = '';

  Widget _buildExpiryWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.l),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: AppSpacing.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meat Freshness Alert', 
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                Text('Some items have been in the butcher house for over 24 hours. Please transfer them to the Cold Room immediately.', 
                  style: TextStyle(fontSize: 12, color: Colors.red.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNewTransferDialog() {
    showDialog(
      context: context,
      builder: (context) => const NewTransferDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transfers = ref.watch(transferProvider);
    final branchesAsync = ref.watch(branchesProvider);
    final activeBatches = ref.watch(activeBatchesProvider).value ?? [];

    final hasOldMeat = activeBatches.any((b) => 
      b.createdAt.isBefore(DateTime.now().subtract(const Duration(hours: 24)))
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasOldMeat)
            _buildExpiryWarning(),
          LayoutBuilder(
            builder: (context, constraints) {
              final useVerticalLayout = constraints.maxWidth < 700;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (useVerticalLayout) ...[
                    const Text('Stock Transfers', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text('Slaughterhouse → Retail Shop', style: TextStyle(color: AppColors.textLight)),
                    const SizedBox(height: AppSpacing.m),
                  ] else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Stock Transfers', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                              Text('Slaughterhouse → Retail Shop', style: TextStyle(color: AppColors.textLight)),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                      ],
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: useVerticalLayout ? (constraints.maxWidth - 8) / 1 : null,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final batches = ref.read(meatBatchesProvider).value ?? [];
                            if (batches.isNotEmpty) {
                              LabelService.printMultipleBatchLabels(batches);
                            }
                          },
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Batch Labels', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: useVerticalLayout ? (constraints.maxWidth - 8) / 1 : null,
                        child: ElevatedButton.icon(
                          onPressed: _showNewTransferDialog,
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('New Transfer', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryMaroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.l),
          _buildTransferSummary(context, transfers),
          const SizedBox(height: AppSpacing.l),
          _buildSearchField(Theme.of(context)),
          const SizedBox(height: AppSpacing.l),
          _buildAvailableStockGrid(context, ref),
          const SizedBox(height: AppSpacing.l),
          _buildRecentTransfers(transfers, branchesAsync.value ?? []),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.m),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'Search product or batch ID...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.m), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.transparent,
          isDense: true,
          suffixIcon: _searchQuery.isNotEmpty 
            ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _searchQuery = ''))
            : null,
        ),
      ),
    );
  }

  Widget _buildAvailableStockGrid(BuildContext context, WidgetRef ref) {
    final recentCuts = ref.watch(recentCutsProvider).value ?? [];
    final transfers = ref.watch(transferProvider);
    final theme = Theme.of(context);

    // Filter cuts that haven't been transferred yet and match search query
    final availableCuts = recentCuts.where((cut) {
      final matchesTransfer = !transfers.any((t) => t.batchId == cut.batchId && t.meatType.contains(cut.name));
      final matchesSearch = _searchQuery.isEmpty || 
                            cut.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                            cut.batchId.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesTransfer && matchesSearch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ready for Transfer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const Text('Items recorded in processing but not yet dispatched', style: TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 12),
        if (availableCuts.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(AppRadius.m),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
            ),
            child: const Center(
              child: Text('No processed parts awaiting transfer.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width < 600 ? 1 : 2,
              mainAxisExtent: 100,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: availableCuts.length,
            itemBuilder: (context, index) {
              final cut = availableCuts[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.m),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.inventory_2, color: theme.colorScheme.primary, size: 20),
                  ),
                  title: Text(cut.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${cut.weight}kg • From Batch ${cut.batchId.substring(0,8)}', style: const TextStyle(fontSize: 10)),
                  trailing: ElevatedButton(
                    onPressed: () => _showQuickTransferDialog(context, ref, cut),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('TRANSFER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _showQuickTransferDialog(BuildContext context, WidgetRef ref, MeatCut cut) {
    String? destination;
    final branches = ref.read(branchesProvider).value ?? [];
    if (branches.isNotEmpty) destination = branches.first.code;
    final weightController = TextEditingController(text: cut.weight.toString());

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text('Transfer: ${cut.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Available: ${cut.weight}${cut.unit}'),
              const SizedBox(height: 16),
              TextField(
                controller: weightController,
                decoration: InputDecoration(
                  labelText: 'Amount to Transfer',
                  suffixText: cut.unit,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: destination,
                decoration: const InputDecoration(labelText: 'Destination Branch', border: OutlineInputBorder()),
                items: branches.map((b) => DropdownMenuItem(
                  value: b.code,
                  child: Text('${b.name} (${b.location})'),
                )).toList(),
                onChanged: (v) => setState(() => destination = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                if (destination == null) return;

                final double transferredWeight = double.tryParse(weightController.text) ?? 0.0;
                if (transferredWeight <= 0) return;

                final now = DateTime.now();
                final transfer = StockTransfer(
                  id: UuidUtils.generate(),
                  batchId: cut.batchId,
                  meatType: '${cut.meatType} - ${cut.name}',
                  weight: transferredWeight,
                  destination: destination!,
                  transferTime: now,
                  status: TransferStatus.pending,
                );

                await ref.read(transferProvider.notifier).addTransfer(transfer);

                if (transferredWeight >= cut.weight) {
                  await ref.read(recentCutsProvider.notifier).deleteCut(cut.id);
                } else {
                  final remaining = cut.weight - transferredWeight;
                  await ref.read(recentCutsProvider.notifier).updateCutWeight(cut.id, remaining);
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  LabelService.printTransferLabel(transfer);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Successfully transferred ${transferredWeight.toStringAsFixed(1)}kg to $destination')),
                  );
                }
              },
              child: const Text('CONFIRM TRANSFER'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferSummary(BuildContext context, List<StockTransfer> transfers) {
    final pendingWeight = transfers
        .where((t) => t.status == TransferStatus.pending)
        .fold(0.0, (sum, t) => sum + t.weight);
    final completedTodayWeight = transfers
        .where((t) => t.status == TransferStatus.received && 
                t.transferTime.day == DateTime.now().day)
        .fold(0.0, (sum, t) => sum + t.weight);

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      children: [
        _summaryCard('In Transit', WeightConverter.formatShort(pendingWeight), Icons.local_shipping, Colors.blue, isMobile),
        _summaryCard('Completed Today', WeightConverter.formatShort(completedTodayWeight), Icons.check_circle, Colors.green, isMobile),
      ],
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color, bool isMobile) {
    return SizedBox(
      width: isMobile ? double.infinity : 250,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: color, size: 20),
                  const Icon(Icons.trending_up, color: AppColors.accentGreen, size: 16),
                ],
              ),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: AppColors.textLight, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentTransfers(List<StockTransfer> transfers, List<Branch> branches) {
    final filteredTransfers = transfers.where((t) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return t.meatType.toLowerCase().contains(q) || 
             t.batchId.toLowerCase().contains(q) || 
             t.id.toLowerCase().contains(q) ||
             t.destination.toLowerCase().contains(q);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Transfer History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: AppSpacing.m),
            if (filteredTransfers.isEmpty)
              Center(child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(_searchQuery.isEmpty ? 'No transfers recorded yet.' : 'No transfers match your search.', style: const TextStyle(color: AppColors.textLight)),
              ))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 600),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(1.5),
                      4: FlexColumnWidth(1.2),
                    },
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: AppColors.surfaceWhite),
                        children: [
                          Padding(padding: EdgeInsets.all(12), child: Text('ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(12), child: Text('Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(12), child: Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(12), child: Text('Destination', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(12), child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Padding(padding: EdgeInsets.all(12), child: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                      ...filteredTransfers.reversed.map((t) {
                        final branch = branches.where((b) => b.code == t.destination).firstOrNull;
                        final destinationDisplay = branch != null ? '${branch.name} (${branch.location})' : t.destination;
                        
                        return TableRow(
                        children: [
                          Padding(padding: const EdgeInsets.all(12), child: Text(t.id.substring(t.id.length - 8), style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                          Padding(padding: const EdgeInsets.all(12), child: Text(DateFormat('hh:mm a').format(t.transferTime), style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(12), child: Text('${t.meatType} (${WeightConverter.formatShort(t.weight)})', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
                          Padding(padding: const EdgeInsets.all(12), child: Text(destinationDisplay, style: const TextStyle(fontSize: 12))),
                          Padding(padding: const EdgeInsets.all(8), child: StatusChip(
                            label: t.status.name.toUpperCase(), 
                            color: t.status == TransferStatus.pending ? Colors.blue : Colors.green
                          )),
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: ElevatedButton.icon(
                              onPressed: () => LabelService.printTransferLabel(t),
                              icon: const Icon(Icons.print, size: 14),
                              label: const Text('REPRINT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryMaroon,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          ),
                        ],
                      );
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NewTransferDialog extends ConsumerStatefulWidget {
  const NewTransferDialog({super.key});

  @override
  ConsumerState<NewTransferDialog> createState() => _NewTransferDialogState();
}

class _NewTransferDialogState extends ConsumerState<NewTransferDialog> {
  bool _isDirectTransfer = false;
  final _weightController = TextEditingController();
  final _productSearchController = TextEditingController();
  String _productSearchQuery = '';
  
  String? _selectedBatchId;
  final Set<String> _selectedCutIds = {};
  String? _destination;
  bool _isThirdParty = false;
  final _thirdPartyCustomerController = TextEditingController();

  final _cutWeights = <String, double>{};

  @override
  void dispose() {
    _thirdPartyCustomerController.dispose();
    _weightController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final batchesAsync = ref.watch(activeBatchesProvider);
    final cutsAsync = ref.watch(recentCutsProvider);
    final transfers = ref.watch(transferProvider);
    final branchesAsync = ref.watch(branchesProvider);
    final productsAsync = ref.watch(productsFutureProvider);
    
    final activeBatches = batchesAsync.value ?? [];
    final activeCuts = cutsAsync.value ?? [];
    final branches = branchesAsync.value ?? [];
    
    if (_destination == null && branches.isNotEmpty) {
      _destination = branches.first.code;
    }

    final selectedBatch = _selectedBatchId != null 
        ? activeBatches.where((b) => b.id == _selectedBatchId).firstOrNull 
        : null;

    final availableCuts = selectedBatch == null 
        ? <MeatCut>[] 
        : activeCuts.where((c) => c.batchId == selectedBatch.id && 
            !transfers.any((t) => t.batchId == c.batchId && t.meatType.contains(c.name))).toList();

    return AlertDialog(
      scrollable: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
      title: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, color: AppColors.primaryMaroon),
          const SizedBox(width: 12),
          Expanded(child: Text(_isDirectTransfer ? 'Direct Transfer / Sale' : 'Move Stock to Retail', style: const TextStyle(fontSize: 18), overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Batch'), icon: Icon(Icons.inventory_2)),
                ButtonSegment(value: true, label: Text('Direct'), icon: Icon(Icons.bolt)),
              ],
              selected: {_isDirectTransfer},
              onSelectionChanged: (val) => setState(() => _isDirectTransfer = val.first),
            ),
            const SizedBox(height: 16),
            if (_isDirectTransfer) ...[
              TextField(
                controller: _productSearchController,
                decoration: InputDecoration(
                  labelText: 'Search Product',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _productSearchQuery.isNotEmpty 
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18), 
                        onPressed: () => setState(() {
                          _productSearchController.clear();
                          _productSearchQuery = '';
                        })
                      ) 
                    : null,
                ),
                onChanged: (v) => setState(() => _productSearchQuery = v),
              ),
              const SizedBox(height: 12),
              productsAsync.when(
                data: (products) {
                  final filteredProducts = products
                      .where((p) => !p.isDeleted)
                      .where((p) => p.name.toLowerCase().contains(_productSearchQuery.toLowerCase()) || 
                                     p.category.toLowerCase().contains(_productSearchQuery.toLowerCase()))
                      .toList();

                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: filteredProducts.any((p) => p.name == _selectedBatchId) ? _selectedBatchId : null,
                    decoration: const InputDecoration(labelText: 'Select Product', border: OutlineInputBorder()),
                    items: filteredProducts.map((p) => DropdownMenuItem(
                      value: p.name, 
                      child: Text('${p.category} - ${p.name}', style: const TextStyle(fontSize: 12)),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedBatchId = v),
                    validator: (v) => v == null ? 'Required' : null,
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const Text('Error loading products'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _weightController,
                decoration: const InputDecoration(labelText: 'Quantity (kg)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              ),
            ] else ...[
              batchesAsync.when(
                data: (batches) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _selectedBatchId,
                  decoration: const InputDecoration(labelText: '1. Select Source Batch', border: OutlineInputBorder()),
                  items: batches.map((b) => DropdownMenuItem<String>(
                    value: b.id,
                    child: Text(
                      '${b.id.length > 8 ? b.id.substring(0,8) : b.id} (${b.meatType})', 
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() {
                    _selectedBatchId = v;
                    _selectedCutIds.clear();
                  }),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error loading batches', style: const TextStyle(fontSize: 12, color: Colors.red)),
              ),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text('2. Select Parts to Move', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              const SizedBox(height: 8),
              if (selectedBatch != null && availableCuts.isNotEmpty) 
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedCutIds.length == availableCuts.length) {
                          _selectedCutIds.clear();
                        } else {
                          _selectedCutIds.addAll(availableCuts.map((c) => c.id));
                        }
                      });
                    },
                    child: Text(_selectedCutIds.length == availableCuts.length ? 'Deselect All' : 'Select All Available'),
                  ),
                ),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: availableCuts.isEmpty 
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(selectedBatch == null ? 'Select batch first' : 'No parts available for transfer', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: availableCuts.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final cut = availableCuts[index];
                        final isSelected = _selectedCutIds.contains(cut.id);
                        return CheckboxListTile(
                          title: Text(cut.name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${cut.weight}kg', style: const TextStyle(fontSize: 11)),
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedCutIds.add(cut.id);
                              } else {
                                _selectedCutIds.remove(cut.id);
                              }
                            });
                          },
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
              ),
              const SizedBox(height: 8),
              if (_selectedCutIds.isNotEmpty) ...[
                const Align(alignment: Alignment.centerLeft, child: Text('Adjust Quantities:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                const SizedBox(height: 4),
                Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView.builder(
                    itemCount: _selectedCutIds.length,
                    itemBuilder: (context, index) {
                      final cutId = _selectedCutIds.elementAt(index);
                      final cut = availableCuts.firstWhere((c) => c.id == cutId);
                      return ListTile(
                        title: Text(cut.name, style: const TextStyle(fontSize: 12)),
                        subtitle: TextFormField(
                          initialValue: cut.weight.toString(),
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4)),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) {
                            final val = double.tryParse(v);
                            if (val != null) _cutWeights[cut.id] = val;
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Third Party Sale', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: const Text('Notify CEO & Cashier for payment', style: TextStyle(fontSize: 11)),
              value: _isThirdParty,
              onChanged: (v) => setState(() => _isThirdParty = v),
              activeThumbColor: AppColors.primaryMaroon,
              contentPadding: EdgeInsets.zero,
            ),
            if (_isThirdParty) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _thirdPartyCustomerController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name / Destination',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ] else
              branchesAsync.when(
                data: (branches) => DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _destination,
                  decoration: const InputDecoration(labelText: 'Destination Branch', border: OutlineInputBorder()),
                  items: branches.map((b) => DropdownMenuItem<String>(
                    value: b.code,
                    child: Text('${b.name} (${b.location})', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setState(() => _destination = v!),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => const Text('Error loading branches', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ],
          ),
        ),
      actionsOverflowButtonSpacing: 8,
      actionsAlignment: MainAxisAlignment.end,
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            // Validation
            if (_isDirectTransfer) {
              if (_selectedBatchId == null || _weightController.text.isEmpty) return;
            } else {
              if (_selectedCutIds.isEmpty || selectedBatch == null) return;
              if (!_isThirdParty && _destination == null) return;
            }

            final List<StockTransfer> transfersList = [];
            final now = DateTime.now();

            final String currentBranchCode = ref.read(currentUserProvider)?.branchCode ?? 'HQ';
            final String targetBranch = _isThirdParty ? currentBranchCode : (_destination ?? currentBranchCode);

            if (_isDirectTransfer) {
              transfersList.add(StockTransfer(
                id: UuidUtils.generate(),
                batchId: 'DIRECT',
                meatType: _selectedBatchId!, // This is the product name
                weight: double.tryParse(_weightController.text) ?? 0.0,
                destination: targetBranch,
                transferTime: now,
                isThirdParty: _isThirdParty,
                status: _isThirdParty ? TransferStatus.awaitingPayment : TransferStatus.pending,
              ));
            } else {
              for (final cutId in _selectedCutIds) {
                final cut = availableCuts.firstWhere((c) => c.id == cutId);
                
                transfersList.add(StockTransfer(
                  id: UuidUtils.generate(),
                  batchId: cut.batchId,
                  meatType: '${selectedBatch!.meatType} - ${cut.name}',
                  weight: _cutWeights[cut.id] ?? cut.weight,
                  destination: targetBranch,
                  transferTime: now,
                  isThirdParty: _isThirdParty,
                  status: _isThirdParty ? TransferStatus.awaitingPayment : TransferStatus.pending,
                ));
              }
            }

            ref.read(transferProvider.notifier).addTransfers(transfersList);
            
            // Notify CEO for Third Party sales specifically
            if (_isThirdParty) {
              final meatDescription = _isDirectTransfer 
                  ? (_selectedBatchId ?? "Meat") 
                  : (selectedBatch?.meatType ?? "Meat");
              final totalWeight = transfersList.fold(0.0, (sum, t) => sum + t.weight);

              final msg = 'URGENT: Third Party Sale initiated. Payment required for ${totalWeight.toStringAsFixed(1)}kg of $meatDescription.';
              
              ref.read(notificationProvider.notifier).addNotification(
                'PAYMENT ALERT', 
                msg,
                isGlobal: true,
                type: 'warning',
              );
              SmsService.notifyAdmin(title: 'PAYMENT ALERT', message: msg);
            }

            Navigator.pop(context);
            
            // Show Barcode Alert Dialog
            _showBarcodePrintPrompt(context, transfersList);
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
          child: Text(_isThirdParty ? 'Initiate Transfer & Notify' : 'Confirm Transfer'),
        ),
      ],
    );
  }

  void _showBarcodePrintPrompt(BuildContext context, List<StockTransfer> transfers) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: AppColors.primaryMaroon),
            SizedBox(width: 12),
            Text('Attach Barcodes', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please print and attach the unique barcodes for these ${transfers.length} items to the package.'),
            const SizedBox(height: 12),
            const Text('The Receiver/Cashier will need to scan these to verify the stock receipt.', 
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('I\'ll do it later')
          ),
          ElevatedButton.icon(
            onPressed: () {
              LabelService.printMultipleTransferLabels(transfers);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.print),
            label: const Text('PRINT ALL LABELS'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
