import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/uuid_utils.dart';
import '../../widgets/status_chip.dart';
import '../../models/butcher_models.dart';
import '../../services/butcher_service.dart';
import '../../services/label_service.dart';
import '../../services/sms_service.dart';
import '../../models/transfer_models.dart';
import '../../services/transfer_provider.dart';
import '../../services/branch_provider.dart';
import '../../services/butcher_navigation_provider.dart';

class MeatProcessingScreen extends ConsumerStatefulWidget {
  const MeatProcessingScreen({super.key});

  @override
  ConsumerState<MeatProcessingScreen> createState() => _MeatProcessingScreenState();
}

class _MeatProcessingScreenState extends ConsumerState<MeatProcessingScreen> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slaughterLogsAsync = ref.watch(slaughterLogsProvider);
    final activeBatchesAsync = ref.watch(meatBatchesProvider);
    final recentCutsAsync = ref.watch(recentCutsProvider);
    final recentCuts = recentCutsAsync.value ?? [];
    final wasteRecords = ref.watch(butcherWasteProvider).value ?? [];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('MEAT PROCESSING', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: theme.cardColor,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () {
              final batches = activeBatchesAsync.value ?? [];
              if (batches.isNotEmpty) {
                LabelService.printMultipleBatchLabels(batches);
              }
            },
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print All Active Labels',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(slaughterLogsProvider.notifier).loadLogs();
              ref.read(meatBatchesProvider.notifier).loadBatches();
              ref.read(recentCutsProvider.notifier).loadCuts();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRecordCutDialog(context, ref),
        label: const Text('Add Part/Cut', style: TextStyle(fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.add_shopping_cart_rounded),
        backgroundColor: AppColors.primaryMaroon,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(slaughterLogsProvider.notifier).loadLogs();
          await ref.read(meatBatchesProvider.notifier).loadBatches();
          await ref.read(recentCutsProvider.notifier).loadCuts();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatsHeader(slaughterLogsAsync, activeBatchesAsync),
              const SizedBox(height: AppSpacing.xl),
              
              _buildSectionHeader('1. CARCASS PIPELINE (Awaiting Breakdown)', Icons.local_shipping_rounded),
              const SizedBox(height: AppSpacing.m),
              slaughterLogsAsync.when(
                data: (logs) {
                  final awaiting = logs.where((l) => l.status == SlaughterStatus.completed).toList();
                  if (awaiting.isEmpty) return const SizedBox.shrink();
                  return _buildAwaitingReceiveList(context, ref, awaiting);
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(10), child: LinearProgressIndicator())),
                error: (err, _) => const SizedBox.shrink(),
              ),
              
              const SizedBox(height: AppSpacing.xl),
              _buildSectionHeader('2. PRODUCTION FLOOR (Active Batches)', Icons.restaurant_rounded),
              const SizedBox(height: AppSpacing.m),
              activeBatchesAsync.when(
                data: (batches) {
                  // NEW LOGIC: A batch stays in the processing section if it has any weight left to dispatch,
                  // even if it was manually marked as 'completed'.
                  final processing = batches.where((b) {
                    final status = b.status.toLowerCase();
                    
                    // Check remaining weight
                    final batchCuts = recentCuts.where((c) => c.batchId == b.id).toList();
                    final batchWaste = wasteRecords.where((w) => w['batch_id'] == b.id).toList();
                    final accounted = batchCuts.fold(0.0, (sum, c) => sum + c.weight) + 
                                     batchWaste.fold(0.0, (sum, w) => sum + (double.tryParse(w['weight']?.toString() ?? '0') ?? 0));
                    final hasWeightLeft = accounted < (b.weight - 0.1); // 100g tolerance

                    // Section 2 Logic: Show if in active status OR if completed but has weight left
                    final isActiveStatus = ['preparing', 'mincing', 'cutting', 'received', 'transporting'].contains(status);
                    return isActiveStatus || (status == 'completed' && hasWeightLeft);
                  }).toList();
                  
                  if (processing.isEmpty) {
                    return _buildEmptyPlaceholder(theme, 'No active batches. Go to Slaughter Log to start a breakdown.');
                  }
                  return _buildActiveBatchesList(ref, processing);
                },
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
              
              const SizedBox(height: AppSpacing.xl),
              _buildSectionHeader('3. PACKAGING & DISPATCH READY', Icons.ac_unit_rounded),
              const SizedBox(height: AppSpacing.m),
              activeBatchesAsync.when(
                data: (batches) {
                  final packaging = batches.where((b) {
                    final status = b.status.toLowerCase();
                    return status == 'packaging' || status == 'frozen' || status == 'completed';
                  }).toList();
                  if (packaging.isEmpty) return _buildEmptyPlaceholder(theme, 'No batches ready for dispatch.');
                  return _buildPackagingSection(context, ref, packaging);
                },
                loading: () => const SizedBox.shrink(),
                error: (err, _) => const SizedBox.shrink(),
              ),
              
              const Divider(height: 60),
              _buildSectionHeader('PRODUCTION HISTORY (Today)', Icons.history),
              const SizedBox(height: AppSpacing.m),
              _buildHistorySummary(recentCutsAsync),
              const SizedBox(height: AppSpacing.m),
              recentCutsAsync.when(
                data: (cuts) => _buildCutProductionList(context, cuts.take(10).toList()),
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPlaceholder(ThemeData theme, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: theme.disabledColor, size: 32),
          const SizedBox(height: 12),
          Text(message, 
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: theme.disabledColor)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              ref.read(slaughterLogsProvider.notifier).loadLogs();
              ref.read(meatBatchesProvider.notifier).loadBatches();
            }, 
            icon: const Icon(Icons.refresh, size: 16), 
            label: const Text('Refresh Data', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader(AsyncValue<List<SlaughterLog>> logsAsync, AsyncValue<List<MeatBatch>> batchesAsync) {
    final awaiting = logsAsync.value?.where((l) => l.status == SlaughterStatus.completed).length ?? 0;
    final inProcess = batchesAsync.value?.where((b) => b.status != MeatBatchStatus.completed.name).length ?? 0;
    
    return Row(
      children: [
        _miniStatCard('Awaiting', '$awaiting', Colors.blue),
        const SizedBox(width: AppSpacing.m),
        _miniStatCard('In-Process', '$inProcess', Colors.orange),
        const SizedBox(width: AppSpacing.m),
        _miniStatCard('Completed', '${batchesAsync.value?.where((b) => b.status == MeatBatchStatus.completed.name).length ?? 0}', Colors.green),
      ],
    );
  }

  Widget _miniStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.m),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySummary(AsyncValue<List<MeatCut>> cutsAsync) {
    final today = DateTime.now();
    final todayCuts = cutsAsync.value?.where((c) => 
      c.processedAt.day == today.day && 
      c.processedAt.month == today.month && 
      c.processedAt.year == today.year
    ).toList() ?? [];
    
    final totalWeight = todayCuts.fold(0.0, (sum, c) => sum + c.weight);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryMaroon, Color(0xFF4A0808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.l),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TODAY\'S PRODUCTION OUTPUT', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text('${totalWeight.toStringAsFixed(1)} kg', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
          Text('Across ${todayCuts.length} individual items packaged', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: AppColors.primaryMaroon.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: AppColors.primaryMaroon),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5))),
      ],
    );
  }

  Widget _buildAwaitingReceiveList(BuildContext context, WidgetRef ref, List<SlaughterLog> logs) {
    final awaiting = logs.where((l) => l.status == SlaughterStatus.completed).toList();
    if (awaiting.isEmpty) return const Text('No carcasses awaiting transport.', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic));

    return SizedBox(
      height: 170,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: awaiting.length,
        itemBuilder: (context, index) {
          final log = awaiting[index];
          return Container(
            width: 320,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m), side: BorderSide(color: Colors.blue.withValues(alpha: 0.2))),
              color: Colors.blue.withValues(alpha: 0.02),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(log.type.displayName, 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          icon: const Icon(Icons.print, size: 20, color: Colors.blue),
                          onPressed: () => _showPrintBatchLabelDialog(context, log),
                          tooltip: 'Print Batch Label',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('TAG: ${log.tagNumber ?? log.id.substring(0,8)}', 
                      style: const TextStyle(fontSize: 11, color: AppColors.textLight, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    Text('INTAKE WEIGHT: ${log.meatWeight}kg', 
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showReceiveDialog(context, ref, log),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, 
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('RECEIVE & PREPARE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveBatchesList(WidgetRef ref, List<MeatBatch> processing) {
    if (processing.isEmpty) return const Text('No batches currently in active processing.', style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic));
    
    final recentCuts = ref.watch(recentCutsProvider).value ?? [];
    final wasteRecords = ref.watch(butcherWasteProvider).value ?? [];

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: processing.length,
      itemBuilder: (context, index) {
        final batch = processing[index];
        final batchCuts = recentCuts.where((c) => c.batchId == batch.id).toList();
        final batchWaste = wasteRecords.where((w) => w['batch_id'] == batch.id);
        
        final processedWeight = batchCuts.fold(0.0, (sum, c) => sum + c.weight);
        final wastedWeight = batchWaste.fold(0.0, (sum, w) => sum + (double.tryParse(w['weight']?.toString() ?? '0') ?? 0));
        final totalAccounted = processedWeight + wastedWeight;
        final progress = (totalAccounted / batch.weight).clamp(0.0, 1.0);

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.m),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryMaroon.withValues(alpha: 0.1),
              child: Icon(_getAnimalIcon(batch.meatType), color: AppColors.primaryMaroon, size: 20),
            ),
            title: Text(batch.meatType, 
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('BATCH: ${batch.id.substring(0,8)}', 
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold)
                ),
                StatusChip(
                  label: batch.status.toUpperCase(), 
                  color: batch.status == MeatBatchStatus.preparing.name ? Colors.orange : Colors.blue,
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('WORKFLOW CONTROL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey)),
                        IconButton(
                          icon: const Icon(Icons.print, size: 18, color: AppColors.primaryMaroon),
                          onPressed: () => LabelService.printBatchLabel(batch),
                          tooltip: 'Print Batch Label',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Wrap(
                          alignment: WrapAlignment.spaceAround,
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            _workflowAction(ref, batch, Icons.restaurant, 'PREP', MeatBatchStatus.preparing),
                            _workflowAction(ref, batch, Icons.bolt, 'MINCE', MeatBatchStatus.mincing),
                            _workflowAction(ref, batch, Icons.content_cut, 'CUT', MeatBatchStatus.cutting),
                            _workflowAction(ref, batch, Icons.inventory_2, 'PACK', MeatBatchStatus.packaging),
                          ],
                        );
                      }
                    ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('CARCASS BREAKDOWN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.grey)),
                        Flexible(
                          child: Text('Total Intake: ${batch.weight} kg', 
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (batchCuts.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('No parts recorded yet.', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                      ))
                    else
                      ...batchCuts.map((cut) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, size: 14, color: Colors.green),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(cut.name, 
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${cut.weight} kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.print, size: 16, color: Colors.grey),
                              onPressed: () => LabelService.printCutLabel(cut),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      )),
                    if (wastedWeight > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline, size: 14, color: Colors.orange),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Recorded Waste/Bones', 
                                style: TextStyle(fontSize: 12, color: Colors.orange),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${wastedWeight.toStringAsFixed(1)} kg', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)
                            ),
                            const SizedBox(width: 24), // Spacer for align
                          ],
                        ),
                      ),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text('${(progress * 100).toStringAsFixed(0)}% Accounted', 
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: progress > 0.95 ? Colors.green : AppColors.primaryMaroon),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${totalAccounted.toStringAsFixed(1)} / ${batch.weight} kg', 
                          style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress, 
                      backgroundColor: Colors.grey.shade100, 
                      color: progress > 0.95 ? Colors.green : AppColors.primaryMaroon,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 130,
                          child: OutlinedButton.icon(
                            onPressed: () => _showRecordWasteDialog(context, ref, batch),
                            icon: const Icon(Icons.delete_outline, size: 16),
                            label: const Text('WASTE', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange, 
                              side: const BorderSide(color: Colors.orange),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: OutlinedButton.icon(
                            onPressed: () => _showQuickDispatchDialog(context, ref, batch),
                            icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                            label: const Text('DISPATCH', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue, 
                              side: const BorderSide(color: Colors.blue),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: ElevatedButton.icon(
                            onPressed: () => _showRecordCutDialog(context, ref, initialBatch: batch),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('ADD PART', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryMaroon, 
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showQuickDispatchDialog(BuildContext context, WidgetRef ref, MeatBatch batch) {
    final weightController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final locationController = TextEditingController();
    
    AnimalType? animalType;
    for (var type in AnimalType.values) {
      if (type.name[0].toUpperCase() + type.name.substring(1) == batch.meatType || 
          (type == AnimalType.hardChicken && batch.meatType == 'Hard Chicken (Layers)') ||
          (type == AnimalType.softChicken && batch.meatType == 'Soft Chicken (Broilers)') ||
          (type.displayName.toUpperCase() == batch.meatType.toUpperCase())) {
        animalType = type;
        break;
      }
    }
    final availableCuts = animalType?.standardCuts ?? [];
    String? selectedCut;
    String dispatchTarget = 'BRANCH'; // 'BRANCH' or 'INDIVIDUAL'
    String? selectedBranchCode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final branchesAsync = ref.watch(branchesProvider);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: Row(
              children: [
                const Icon(Icons.rocket_launch_outlined, color: AppColors.primaryMaroon),
                const SizedBox(width: 12),
                Expanded(child: Text('Dispatch: ${batch.meatType}', overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Select weight and destination. This will log the cut and print a label.', 
                      style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                    const SizedBox(height: 20),
                    
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Select Part/Cut', border: OutlineInputBorder()),
                      items: availableCuts.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => selectedCut = v),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: weightController,
                      decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder(), suffixText: 'kg'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    ),
                    const Divider(height: 40),
                    
                    const Align(alignment: Alignment.centerLeft, child: Text('DESTINATION TYPE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Branch')),
                            selected: dispatchTarget == 'BRANCH',
                            onSelected: (v) => setState(() => dispatchTarget = 'BRANCH'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ChoiceChip(
                            label: const Center(child: Text('Individual')),
                            selected: dispatchTarget == 'INDIVIDUAL',
                            onSelected: (v) => setState(() => dispatchTarget = 'INDIVIDUAL'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (dispatchTarget == 'BRANCH')
                      branchesAsync.when(
                        data: (branches) => DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Select Destination Branch', border: OutlineInputBorder()),
                          items: branches.map((b) => DropdownMenuItem(value: b.code, child: Text(b.name))).toList(),
                          onChanged: (v) => setState(() => selectedBranchCode = v),
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stackTrace) => const Text('Error loading branches'),
                      )
                    else ...[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone_outlined)),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(labelText: 'Delivery Location', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on_outlined)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                onPressed: () async {
                  final weight = double.tryParse(weightController.text) ?? 0;
                  if (selectedCut == null || weight <= 0) return;
                  if (dispatchTarget == 'BRANCH' && selectedBranchCode == null) return;
                  if (dispatchTarget == 'INDIVIDUAL' && nameController.text.isEmpty) return;

                  final now = DateTime.now();
                  final id = UuidUtils.generate();

                  // 1. Create the MeatCut
                  final cut = MeatCut(
                    id: id,
                    name: selectedCut!,
                    meatType: batch.meatType,
                    batchId: batch.id,
                    weight: weight,
                    processedAt: now,
                    branchCode: batch.branchCode,
                  );

                  // 2. Create the Transfer
                  final transfer = StockTransfer(
                    id: id,
                    branchCode: batch.branchCode,
                    batchId: batch.id,
                    meatType: '${batch.meatType} - $selectedCut',
                    weight: weight,
                    destination: dispatchTarget == 'BRANCH' ? selectedBranchCode! : 'PRIVATE_ORDER',
                    transferTime: now,
                    isIndividual: dispatchTarget == 'INDIVIDUAL',
                    customerName: nameController.text.trim(),
                    customerPhone: phoneController.text.trim(),
                    customerLocation: locationController.text.trim(),
                  );

                  // Process actions
                  await ref.read(recentCutsProvider.notifier).addCut(cut);
                  await ref.read(transferProvider.notifier).addTransfer(transfer);
                  await LabelService.printCutLabel(cut);

                  // 3. Send SMS if individual order
                  if (dispatchTarget == 'INDIVIDUAL' && phoneController.text.isNotEmpty) {
                    try {
                      await SmsService.sendDispatchSms(
                        name: nameController.text.trim(),
                        phone: phoneController.text.trim(),
                        item: '${batch.meatType} - $selectedCut',
                        weight: weight,
                        location: locationController.text.trim(),
                      );
                    } catch (smsErr) {
                      debugPrint('Dispatch SMS Error: $smsErr');
                    }
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Successfully dispatched $weight kg to ${dispatchTarget == 'BRANCH' ? selectedBranchCode : nameController.text}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('PRINT & DISPATCH'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
              ),
            ],
          );
        },
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

  IconData _getAnimalIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('cow') || t.contains('bull') || t.contains('beef')) return Icons.pets;
    if (t.contains('pig') || t.contains('pork')) return Icons.set_meal_rounded;
    if (t.contains('chicken') || t.contains('poultry')) return Icons.egg;
    return Icons.restaurant;
  }

  Widget _workflowAction(WidgetRef ref, MeatBatch batch, IconData icon, String label, MeatBatchStatus targetStatus) {
    final isActive = batch.status == targetStatus.name;
    return InkWell(
      onTap: () {
        if (targetStatus == MeatBatchStatus.packaging) {
          _showPackingSummaryDialog(context, ref, batch);
        } else {
          ref.read(meatBatchesProvider.notifier).updateBatchProcessingStatus(batch.id, targetStatus);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryMaroon.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isActive ? AppColors.primaryMaroon : Colors.grey),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 8, fontWeight: isActive ? FontWeight.w900 : FontWeight.normal, color: isActive ? AppColors.primaryMaroon : Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showPackingSummaryDialog(BuildContext context, WidgetRef ref, MeatBatch batch) {
    final recentCuts = ref.read(recentCutsProvider).value ?? [];
    final wasteRecords = ref.read(butcherWasteProvider).value ?? [];
    final batchCuts = recentCuts.where((c) => c.batchId == batch.id).toList();
    final batchWaste = wasteRecords.where((w) => w['batch_id'] == batch.id).toList();
    
    final processedWeight = batchCuts.fold(0.0, (sum, c) => sum + c.weight);
    final wastedWeight = batchWaste.fold(0.0, (sum, w) => sum + (double.tryParse(w['weight']?.toString() ?? '0') ?? 0));
    final totalAccounted = processedWeight + wastedWeight;
    final progress = (totalAccounted / batch.weight).clamp(0.0, 1.0);

    showDialog(
      context: context,
      builder: (context) {
        final bool isMobile = MediaQuery.of(context).size.width < 600;
        final theme = Theme.of(context);
        
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          child: Container(
            width: isMobile ? MediaQuery.of(context).size.width * 0.95 : 450,
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  decoration: BoxDecoration(
                    color: AppColors.primaryMaroon.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.m),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2, color: AppColors.primaryMaroon, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Packaging Confirmation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.primary)),
                            Text('${batch.meatType} | Batch: ${batch.id.substring(0, 8)}', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Yield Metrics
                Row(
                  children: [
                    Expanded(child: _metricBox('INTAKE', '${batch.weight}kg', Colors.blue)),
                    const SizedBox(width: 8),
                    Expanded(child: _metricBox('PACKED', '${totalAccounted.toStringAsFixed(1)}kg', Colors.green)),
                    const SizedBox(width: 8),
                    Expanded(child: _metricBox('YIELD', '${(progress * 100).toStringAsFixed(0)}%', progress > 0.9 ? Colors.green : Colors.orange)),
                  ],
                ),
                
                const SizedBox(height: 24),
                const Align(alignment: Alignment.centerLeft, child: Text('PACKED ITEMS DETAIL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1, color: Colors.grey))),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppRadius.m),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: isMobile ? 180 : 250),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: batchCuts.length,
                      itemBuilder: (context, index) {
                        final cut = batchCuts[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, size: 16, color: Colors.green),
                              const SizedBox(width: 12),
                              Expanded(child: Text(cut.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                              Text('${cut.weight}kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (wastedWeight > 0) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, size: 16, color: Colors.orange),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Operational Waste (Bones/Fat)', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w500))),
                        Text('${wastedWeight.toStringAsFixed(1)}kg', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade100,
                      color: progress > 0.95 ? Colors.green : AppColors.primaryMaroon,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    const SizedBox(height: 8),
                    Text('${(progress * 100).toStringAsFixed(1)}% of carcass accounted for', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // 1. Mark as completed
                      await ref.read(meatBatchesProvider.notifier).updateBatchProcessingStatus(batch.id, MeatBatchStatus.completed);
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                        
                        // 2. Navigate to Batch Management for Dispatch preparation
                        ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.batchManagement);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Batch finalized! Now preparing for Stock Transfer.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('FINALIZE & TRANSFER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryMaroon, 
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to Workstation', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: color, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.withValues(alpha: 0.9))),
        ],
      ),
    );
  }

  Widget _buildPackagingSection(BuildContext context, WidgetRef ref, List<MeatBatch> packaging) {
    if (packaging.isEmpty) return _buildEmptyPlaceholder(Theme.of(context), 'No batches in packaging. Use the PACK duty above to move them here.');

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: packaging.length,
      itemBuilder: (context, index) {
        final batch = packaging[index];
        final isFrozen = batch.status == MeatBatchStatus.frozen.name;
        
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.m),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.m),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
            border: Border.all(color: isFrozen ? Colors.cyan.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3)),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: isFrozen ? Colors.cyan : Colors.blue,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(AppRadius.m), bottomLeft: Radius.circular(AppRadius.m)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(isFrozen ? Icons.ac_unit : Icons.inventory_2, color: isFrozen ? Colors.cyan : Colors.blue, size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(batch.meatType.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                            StatusChip(label: batch.status.toUpperCase(), color: isFrozen ? Colors.cyan : Colors.blue),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            _miniInfo(Icons.tag, 'BATCH: ${batch.id.substring(0,8)}'),
                            _miniInfo(Icons.scale, '${batch.weight}kg Total'),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            if (!isFrozen)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => ref.read(meatBatchesProvider.notifier).updateBatchProcessingStatus(batch.id, MeatBatchStatus.frozen),
                                  icon: const Icon(Icons.ac_unit_rounded, size: 16),
                                  label: const Text('FREEZE', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.cyan, side: const BorderSide(color: Colors.cyan)),
                                ),
                              )
                            else
                              const Expanded(child: SizedBox.shrink()),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _showQuickDispatchDialog(context, ref, batch),
                                icon: const Icon(Icons.local_shipping_rounded, size: 16),
                                label: const Text('DISPATCH NOW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, elevation: 0),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCutProductionList(BuildContext context, List<MeatCut> cuts) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 700),
              child: DataTable(
                columnSpacing: 24,
                headingRowColor: WidgetStateProperty.all(AppColors.primaryMaroon.withValues(alpha: 0.05)),
                headingTextStyle: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primaryMaroon, fontSize: 12),
                columns: const [
                  DataColumn(label: Text('CUT NAME')),
                  DataColumn(label: Text('BATCH ID')),
                  DataColumn(label: Text('WEIGHT')),
                  DataColumn(label: Text('TIME')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: cuts.map((cut) => DataRow(
                  cells: [
                    DataCell(Text(cut.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    DataCell(Text(cut.batchId.substring(0,8), style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                    DataCell(Text('${cut.weight} kg', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.green))),
                    DataCell(Text(DateFormat('MMM dd, HH:mm').format(cut.processedAt), style: const TextStyle(fontSize: 11))),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => LabelService.printCutLabel(cut),
                            icon: const Icon(Icons.print, size: 18, color: AppColors.primaryMaroon),
                            tooltip: 'Reprint Label',
                          ),
                        ],
                      ),
                    ),
                  ],
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrintBatchLabelDialog(BuildContext context, SlaughterLog log) {
    final weightController = TextEditingController(text: log.meatWeight.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Print Batch Label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Printing label for ${log.type.displayName}'),
            const SizedBox(height: 16),
            TextField(
              controller: weightController,
              decoration: const InputDecoration(
                labelText: 'Verify Weight (kg)',
                border: OutlineInputBorder(),
                suffixText: 'kg',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              final weight = double.tryParse(weightController.text) ?? log.meatWeight;

              // Validation: Verified weight vs Intake Meat Weight
              if (weight > log.meatWeight) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Verification Failed: Carcass weight (${weight}kg) cannot exceed intake weight (${log.meatWeight}kg).')),
                );
                return;
              }
              if (weight < log.meatWeight * 0.9) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Verification Failed: Carcass weight (${weight}kg) is too low (less than 90% of intake weight).')),
                );
                return;
              }

              final tempBatch = MeatBatch(
                id: log.id,
                branchCode: log.branchCode,
                animalId: log.animalId,
                meatType: log.type.displayName,
                weight: weight,
                costPrice: log.farmPrice ?? 0.0,
                createdAt: log.slaughterTime ?? DateTime.now(),
                status: 'transporting',
                source: BatchSource(name: 'Slaughterhouse', location: '', owner: ''),
              );
              LabelService.printBatchLabel(tempBatch);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.print),
            label: const Text('Print Label'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showReceiveDialog(BuildContext context, WidgetRef ref, SlaughterLog log) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Text('Confirm Carcass Receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Move ${log.meatWeight}kg ${log.type.displayName} into active processing?'),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Recorded By (Staff Name)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                ref.read(meatBatchesProvider.notifier).receiveCarcass(log, controller.text);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('Confirm & Start Prep'),
          ),
        ],
      ),
    );
  }

  void _showRecordCutDialog(BuildContext context, WidgetRef ref, {MeatBatch? initialBatch}) {
    final formKey = GlobalKey<FormState>();
    final weightController = TextEditingController();
    MeatBatch? selectedBatch = initialBatch;
    String? selectedCutName;
    
    final batchesAsync = ref.read(meatBatchesProvider);
    final activeBatches = batchesAsync.value?.where((b) => 
      b.status != MeatBatchStatus.completed.name && 
      b.status != MeatBatchStatus.frozen.name
    ).toList() ?? [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          AnimalType? animalType;
          if (selectedBatch != null) {
            for (var type in AnimalType.values) {
              if (type.name[0].toUpperCase() + type.name.substring(1) == selectedBatch!.meatType || 
                  (type == AnimalType.hardChicken && selectedBatch!.meatType == 'Hard Chicken (Layers)') ||
                  (type == AnimalType.softChicken && selectedBatch!.meatType == 'Soft Chicken (Broilers)')) {
                animalType = type;
                break;
              }
            }
          }
          final availableCuts = animalType?.standardCuts ?? [];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: const Row(
              children: [
                Icon(Icons.restaurant_rounded, color: AppColors.primaryMaroon),
                SizedBox(width: 12),
                Expanded(child: Text('Add Dissected Part', overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<MeatBatch>(
                      initialValue: selectedBatch,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Select Source Batch', border: OutlineInputBorder()),
                      items: activeBatches.map((b) => DropdownMenuItem(
                        value: b, 
                        child: Text('${b.id.substring(0,8)} (${b.meatType})', overflow: TextOverflow.ellipsis)
                      )).toList(),
                      onChanged: (v) => setState(() {
                        selectedBatch = v;
                        selectedCutName = null;
                      }),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedCutName,
                      decoration: const InputDecoration(labelText: 'Select Part/Cut', border: OutlineInputBorder()),
                      items: availableCuts.map((cut) => DropdownMenuItem(
                        value: cut, 
                        child: Text(cut, overflow: TextOverflow.ellipsis)
                      )).toList(),
                      onChanged: (v) => setState(() => selectedCutName = v),
                      validator: (v) => v == null ? 'Required' : null,
                      disabledHint: const Text('Select a batch first'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: weightController,
                      decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.scale)), 
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final weight = double.tryParse(v);
                        if (weight == null || weight <= 0) return 'Invalid weight';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final String validUuid = UuidUtils.generate();

                    final cut = MeatCut(
                      id: validUuid,
                      name: selectedCutName!,
                      meatType: selectedBatch!.meatType,
                      batchId: selectedBatch!.id,
                      weight: double.tryParse(weightController.text) ?? 0,
                      processedAt: DateTime.now(),
                    );

                    await ref.read(recentCutsProvider.notifier).addCut(cut);
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
                          title: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green),
                              SizedBox(width: 12),
                              Expanded(child: Text('Cut Recorded')),
                            ],
                          ),
                          content: Text('${cut.name} (${cut.weight}kg) recorded for production.'),
                          actions: [
                            TextButton.icon(
                              onPressed: () => LabelService.printCutLabel(cut),
                              icon: const Icon(Icons.print, size: 18),
                              label: const Text('Print Label'),
                            ),
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep Dissecting')),
                          ],
                        ),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
                child: const Text('Save & Print'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _showRecordWasteDialog(BuildContext context, WidgetRef ref, MeatBatch batch) {
    final formKey = GlobalKey<FormState>();
    final reasonController = TextEditingController();
    final weightController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.orange),
            const SizedBox(width: 12),
            Expanded(child: Text('Waste: ${batch.id.substring(0, 8)}', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: weightController,
                decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                ref.read(butcherWasteProvider.notifier).addWaste(batch.id, reasonController.text, double.parse(weightController.text));
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Record Waste'),
          ),
        ],
      ),
    );
  }
}
