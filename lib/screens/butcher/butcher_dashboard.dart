import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../core/uuid_utils.dart';
import '../../widgets/kpi_card.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/summary_row.dart';
import '../../widgets/workflow_step.dart';
import '../../services/butcher_service.dart';
import '../../models/butcher_models.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../services/transfer_provider.dart';
import '../../models/transfer_models.dart';
import '../../services/user_provider.dart';

class ButcherDashboard extends ConsumerWidget {
  const ButcherDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(slaughterLogsProvider);
    final batchesAsync = ref.watch(meatBatchesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1200;

        return SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? AppSpacing.l : AppSpacing.m),
          child: Column(
            children: [
              if (isDesktop)
                Container(
                  height: 150,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.l),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.m),
                    image: DecorationImage(
                      image: const AssetImage('assets/images/butcher_cow.jpg'),
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.m),
                      gradient: LinearGradient(
                        begin: Alignment.bottomRight,
                        colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                      ),
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    alignment: Alignment.bottomLeft,
                    child: const Text(
                      'Butcher Operations Overview',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              logsAsync.when(
                data: (logs) {
                  final batches = batchesAsync.value ?? [];
                  final wasteRecords = ref.watch(butcherWasteProvider).value ?? [];
                  return _buildKPIGrid(constraints.maxWidth, logs, batches, wasteRecords);
                },
                loading: () => const LinearProgressIndicator(),
                error: (err, stack) => const Text('Error loading stats'),
              ),
              const SizedBox(height: AppSpacing.l),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          _buildInteractiveWorkflow(ref),
                          const SizedBox(height: AppSpacing.l),
                          logsAsync.when(
                            data: (logs) => _buildSlaughterTrendChart(context, logs, ref),
                            loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                            error: (e, _) => const Text('Error loading slaughter trend'),
                          ),
                          const SizedBox(height: AppSpacing.l),
                          _buildSlaughterLogs(ref, logsAsync),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.l),
                    Expanded(
                      flex: 1,
                      child: Column(
                        children: [
                          _buildSmartInsights(logsAsync),
                          const SizedBox(height: AppSpacing.l),
                          _buildQuickDispatch(context, ref),
                          const SizedBox(height: AppSpacing.l),
                          _buildMeatSummary(logsAsync),
                          const SizedBox(height: AppSpacing.l),
                          _buildQuickActions(ref),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    _buildInteractiveWorkflow(ref),
                    const SizedBox(height: AppSpacing.l),
                    logsAsync.when(
                      data: (logs) => _buildSlaughterTrendChart(context, logs, ref),
                      loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                      error: (e, _) => const Text('Error loading slaughter trend'),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    _buildSmartInsights(logsAsync),
                    const SizedBox(height: AppSpacing.l),
                    _buildQuickDispatch(context, ref),
                    const SizedBox(height: AppSpacing.l),
                    _buildMeatSummary(logsAsync),
                    const SizedBox(height: AppSpacing.l),
                    _buildSlaughterLogs(ref, logsAsync),
                    const SizedBox(height: AppSpacing.l),
                    _buildQuickActions(ref),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlaughterTrendChart(BuildContext context, List<SlaughterLog> logs, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Group logs by day for the last 7 days
    final now = DateTime.now();
    final last7Days = List.generate(7, (index) {
      return now.subtract(Duration(days: 6 - index));
    });

    final dailyData = last7Days.map((date) {
      final dayLogs = logs.where((l) {
        final logDate = l.slaughterTime ?? DateTime.now();
        return logDate.year == date.year && logDate.month == date.month && logDate.day == date.day;
      }).toList();
      
      final Map<AnimalType, int> typeCounts = {};
      for (var log in dayLogs) {
        typeCounts[log.type] = (typeCounts[log.type] ?? 0) + 1;
      }
      return typeCounts;
    }).toList();

    final dailyTotals = dailyData.map((d) => d.values.fold(0, (sum, v) => sum + v)).toList();
    final maxCount = dailyTotals.isEmpty ? 10 : (dailyTotals.reduce((a, b) => a > b ? a : b) + 2);

    // Get all unique animal types present in the logs for the legend
    final presentTypes = logs.map((l) => l.type).toSet().toList();

    return Container(
      height: 350, // Slightly taller for legend
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: isDark ? Border.all(color: theme.dividerColor) : null,
      ),
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
                    Text('Slaughter Trend', 
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: theme.colorScheme.onSurface),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('Daily breakdown by animal type', 
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.slaughterLog),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('View Logs', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(dailyData.length, (index) {
                final typeCounts = dailyData[index];
                final total = dailyTotals[index];
                final date = last7Days[index];
                final isToday = index == 6;

                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(
                        child: Text(total > 0 ? '$total' : '', 
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isToday ? AppColors.primaryMaroon : theme.colorScheme.onSurfaceVariant)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(minHeight: 5),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: typeCounts.entries.map((entry) {
                              final double segmentHeight = (entry.value / maxCount) * 140;
                              return Container(
                                height: segmentHeight,
                                width: double.infinity,
                                color: _getAnimalColor(entry.key),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        DateFormat('E').format(date).substring(0, 1),
                        style: TextStyle(
                          fontSize: 10, 
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isToday ? AppColors.primaryMaroon : theme.colorScheme.onSurfaceVariant
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: presentTypes.map((type) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: _getAnimalColor(type), shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text(type.displayName, style: TextStyle(fontSize: 8, color: theme.colorScheme.onSurfaceVariant)),
              ],
            )).toList(),
          ),
        ],
      ),
    );
  }

  Color _getAnimalColor(AnimalType type) {
    switch (type) {
      case AnimalType.cow: return const Color(0xFF5D4037); // Brown
      case AnimalType.bull: return const Color(0xFF212121); // Dark Gray/Black
      case AnimalType.pig: return const Color(0xFFF06292); // Pink
      case AnimalType.sheep: return const Color(0xFFFFB74D); // Light Orange
      case AnimalType.goat: return const Color(0xFFE65100); // Dark Orange
      case AnimalType.hardChicken: return const Color(0xFFFBC02D); // Yellow Gold
      case AnimalType.softChicken: return const Color(0xFFFFF176); // Light Yellow
      case AnimalType.turkey: return const Color(0xFF78909C); // Blue Gray
      case AnimalType.rabbit: return const Color(0xFFBDBDBD); // Gray
    }
  }

  Widget _buildSmartInsights(AsyncValue<List<SlaughterLog>> logsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: AppColors.accentGreen),
                SizedBox(width: 8),
                Text("Smart Insights", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            logsAsync.when(
              data: (logs) {
                final completed = logs.where((l) => 
                  l.status == SlaughterStatus.completed || 
                  l.status == SlaughterStatus.processed
                ).toList();
                if (completed.isEmpty) return const Text("No yield data available yet.");
                
                final totalWeight = completed.fold(0.0, (sum, l) => sum + l.liveWeight);
                final totalYield = completed.fold(0.0, (sum, l) => sum + l.meatWeight);
                final avgEfficiency = (totalYield / totalWeight) * 100;

                return Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: 120,
                          width: 120,
                          child: CircularProgressIndicator(
                            value: avgEfficiency / 100,
                            strokeWidth: 12,
                            backgroundColor: AppColors.surfaceWhite,
                            color: AppColors.accentGreen,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Column(
                          children: [
                            Text("${avgEfficiency.toStringAsFixed(1)}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.accentGreen)),
                            const Text("Efficiency", style: TextStyle(fontSize: 10, color: AppColors.textLight)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.l),
                    Text(
                      "Average yield efficiency across ${completed.length} animals.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => const Text("Failed to calculate insights"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveWorkflow(WidgetRef ref) {
    final transfers = ref.watch(transferProvider);
    final pendingTransferCount = transfers.where((t) => t.status == TransferStatus.pending).length;
    
    final logsAsync = ref.watch(slaughterLogsProvider);
    final batchesAsync = ref.watch(meatBatchesProvider);

    int intakeCount = 0;
    int slaughterCount = 0;
    int processingCount = 0;

    logsAsync.whenData((logs) {
      intakeCount = logs.where((l) => l.status == SlaughterStatus.pending).length;
      slaughterCount = logs.where((l) => l.status == SlaughterStatus.slaughtering || l.status == SlaughterStatus.cleaned).length;
    });

    batchesAsync.whenData((batches) {
      processingCount = batches.length;
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(child: Text("Active Operations Pipeline", style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Icon(Icons.info_outline, size: 14, color: AppColors.textLight),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStep(ref, 'Intake', intakeCount.toString(), Icons.login, ButcherScreen.animalIntake, true),
                  _buildArrow(),
                  _buildStep(ref, 'Slaughter', slaughterCount.toString(), Icons.precision_manufacturing, ButcherScreen.slaughterLog, false),
                  _buildArrow(),
                  _buildStep(ref, 'Processing', processingCount.toString(), Icons.restaurant, ButcherScreen.meatProcessing, false),
                  _buildArrow(),
                  _buildStep(ref, 'Transfer', '$pendingTransferCount', Icons.local_shipping, ButcherScreen.stockTransfer, false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(WidgetRef ref, String label, String count, IconData icon, ButcherScreen target, bool isActive) {
    return InkWell(
      onTap: () => ref.read(butcherNavProvider.notifier).setScreen(target),
      borderRadius: BorderRadius.circular(AppRadius.m),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: WorkflowStep(label: label, count: count, icon: icon, isActive: isActive),
      ),
    );
  }

  Widget _buildQuickDispatch(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text("Quick End-of-Day Dispatch", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              "No meat should stay in the butcher house for more than a day. Push all processed meat to the coldroom or retail cashier.",
              style: TextStyle(fontSize: 11, color: AppColors.textLight),
            ),
            const SizedBox(height: AppSpacing.m),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showQuickDispatchDialog(context, ref),
                icon: const Icon(Icons.send_to_mobile),
                label: const Text("Push to Coldroom / Cashier"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickDispatchDialog(BuildContext context, WidgetRef ref) {
    String? selectedCategory;
    final meatTypeController = TextEditingController();
    final weightController = TextEditingController();
    String destinationType = 'COLDROOM'; // Default
    WeightUnit selectedUnit = WeightUnit.kg;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Quick Meat Dispatch'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Choose meat type and weight that was recently butchered.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Meat Category'),
                  items: ['Beef', 'Cow', 'Pork', 'Hard Chicken (Layer)', 'Soft Chicken (Broiler)', 'Goat', 'Sheep', 'Rabbit'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (v) {
                    setState(() {
                      selectedCategory = v;
                      if (v == 'Hard Chicken (Layer)' || v == 'Soft Chicken (Broiler)') {
                        selectedUnit = WeightUnit.unit;
                      } else {
                        selectedUnit = WeightUnit.kg;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: meatTypeController,
                  decoration: const InputDecoration(labelText: 'Specific Cut / Type', hintText: 'e.g. Standard Meat'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: weightController,
                        decoration: InputDecoration(
                          labelText: selectedUnit == WeightUnit.unit ? 'Quantity' : 'Weight (${selectedUnit.name})',
                          suffixText: selectedUnit == WeightUnit.unit ? 'pcs' : selectedUnit.name,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      children: [
                        const Text('UNIT', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                        ToggleButtons(
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                          isSelected: [
                            selectedUnit == WeightUnit.kg, 
                            selectedUnit == WeightUnit.g,
                            selectedUnit == WeightUnit.lb,
                            selectedUnit == WeightUnit.unit,
                          ],
                          onPressed: (index) {
                            setState(() {
                              selectedUnit = WeightUnit.values[index];
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          selectedColor: Colors.white,
                          fillColor: theme.colorScheme.primary,
                          children: const [
                            Text('kg', style: TextStyle(fontSize: 9)),
                            Text('g', style: TextStyle(fontSize: 9)),
                            Text('lb', style: TextStyle(fontSize: 9)),
                            Text('pcs', style: TextStyle(fontSize: 9)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                const Align(alignment: Alignment.centerLeft, child: Text('Destination:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                RadioGroup<String>(
                  groupValue: destinationType,
                  onChanged: (v) => setState(() => destinationType = v!),
                  child: Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Coldroom', style: TextStyle(fontSize: 12)),
                          value: 'COLDROOM',
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Third Party', style: TextStyle(fontSize: 12)),
                          value: 'THIRDPARTY',
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                if (destinationType == 'THIRDPARTY') ...[
                  TextField(decoration: const InputDecoration(labelText: 'Customer/Vendor Name')),
                  const SizedBox(height: 8),
                  const Text('Payment must be confirmed by Cashier/CEO.', style: TextStyle(fontSize: 10, color: Colors.orange)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () async {
                double weightVal = double.tryParse(weightController.text) ?? 0;
                if (weightVal <= 0) return;

                // Conversion to KG
                if (selectedUnit == WeightUnit.g) {
                  weightVal = WeightConverter.fromG(weightVal);
                } else if (selectedUnit == WeightUnit.lb) {
                  weightVal = WeightConverter.toKg(weightVal);
                }

                final user = ref.read(currentUserProvider);
                
                final String categoryPart = selectedCategory != null ? '$selectedCategory - ' : '';
                final String cutPart = meatTypeController.text.isEmpty ? 'Standard Meat' : meatTypeController.text;

                final transfer = StockTransfer(
                  id: UuidUtils.generate(),
                  batchId: 'DIRECT-DAILY',
                  meatType: '$categoryPart$cutPart',
                  weight: weightVal,
                  unit: selectedUnit == WeightUnit.unit ? 'unit' : 'kg',
                  branchCode: user?.branchCode, // Set source branch
                  destination: destinationType == 'COLDROOM' ? (user?.branchCode ?? 'MAIN') : 'THIRDPARTY',
                  transferTime: DateTime.now(),
                  status: destinationType == 'THIRDPARTY' ? TransferStatus.awaitingPayment : TransferStatus.pending,
                  isThirdParty: destinationType == 'THIRDPARTY',
                );

                await ref.read(transferProvider.notifier).addTransfer(transfer);
                
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meat Dispatched! Cashier and CEO notified.')));
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
              child: const Text('DISPATCH NOW'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIGrid(double maxWidth, List<SlaughterLog> logs, List<MeatBatch> batches, List<Map<String, dynamic>> wasteRecords) {
    final completedCount = logs.where((l) => 
      l.status == SlaughterStatus.completed || 
      l.status == SlaughterStatus.processed
    ).length;
    
    final pendingCount = logs.where((l) => l.status == SlaughterStatus.pending).length;
    
    final totalYield = logs.where((l) => 
      l.status == SlaughterStatus.completed || 
      l.status == SlaughterStatus.processed
    ).fold(0.0, (sum, l) => sum + l.meatWeight);

    final totalWaste = wasteRecords.fold(0.0, (sum, w) => sum + (double.tryParse(w['weight']?.toString() ?? '0') ?? 0));

    final bool isMobile = maxWidth < 700;
    final double itemWidth = isMobile ? (maxWidth - 48) / 2 : (maxWidth - 80) / 5;

    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      children: [
        _kpiWrapper(KPICard(title: 'Animals Today', value: '${logs.length}', subValue: '$pendingCount Pending', icon: Icons.pets, iconColor: Colors.blue, iconBgColor: const Color(0xFFE3F2FD)), itemWidth),
        _kpiWrapper(KPICard(title: 'Slaughtered', value: '$completedCount', icon: Icons.done_all, iconColor: Colors.green, iconBgColor: const Color(0xFFE8F5E9)), itemWidth),
        _kpiWrapper(KPICard(title: 'Yield (Est. kg)', value: totalYield.toStringAsFixed(1), icon: Icons.layers, iconColor: Colors.purple, iconBgColor: const Color(0xFFF3E5F5)), itemWidth),
        _kpiWrapper(KPICard(title: 'Active Batches', value: '${batches.length}', icon: Icons.inventory_2, iconColor: Colors.orange, iconBgColor: const Color(0xFFFFF3E0)), itemWidth),
        _kpiWrapper(KPICard(title: 'Waste Recorded', value: '${totalWaste.toStringAsFixed(1)} kg', icon: Icons.delete_outline, iconColor: Colors.red, iconBgColor: const Color(0xFFFFEBEE)), itemWidth),
      ],
    );
  }

  Widget _kpiWrapper(Widget child, double width) {
    return SizedBox(
      width: width,
      child: child,
    );
  }

  Widget _buildArrow() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.arrow_forward_ios, color: AppColors.borderGray, size: 12),
      );

  Widget _buildSlaughterLogs(WidgetRef ref, AsyncValue<List<SlaughterLog>> logsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Recent Activity Logs', style: TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                TextButton(
                  onPressed: () => ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.slaughterLog), 
                  child: const Text('View Detailed Logs', style: TextStyle(fontSize: 12))
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            logsAsync.when(
              data: (logs) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 500),
                  child: DataTable(
                    columnSpacing: 20,
                    columns: const [
                      DataColumn(label: Text('ID', style: TextStyle(fontSize: 11))),
                      DataColumn(label: Text('Animal', style: TextStyle(fontSize: 11))),
                      DataColumn(label: Text('Type', style: TextStyle(fontSize: 11))),
                      DataColumn(label: Text('Date/Time', style: TextStyle(fontSize: 11))),
                      DataColumn(label: Text('Weight', style: TextStyle(fontSize: 11))),
                      DataColumn(label: Text('Status', style: TextStyle(fontSize: 11))),
                    ],
                    rows: logs.take(5).map((log) => DataRow(cells: [
                      DataCell(SizedBox(width: 80, child: Text(log.tagNumber ?? log.id.substring(0, 8), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                      DataCell(SizedBox(width: 80, child: Text(log.manualFarmTag ?? log.animalId.substring(0, 8), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
                      DataCell(Text(log.type.displayName, style: const TextStyle(fontSize: 11))),
                      DataCell(Text(
                        log.slaughterTime != null 
                          ? DateFormat('MM/dd HH:mm').format(log.slaughterTime!) 
                          : 'Pending',
                        style: const TextStyle(fontSize: 10),
                      )),
                      DataCell(Text(WeightConverter.formatShort(log.weight, unit: 'kg'), style: const TextStyle(fontSize: 10))),
                      DataCell(StatusChip(label: log.status.name.toUpperCase(), color: _getStatusColor(log.status))),
                    ])).toList(),
                  ),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Error: $err'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(SlaughterStatus status) {
    switch (status) {
      case SlaughterStatus.completed: return Colors.green;
      case SlaughterStatus.slaughtering: return Colors.red;
      case SlaughterStatus.cleaned: return Colors.blue;
      case SlaughterStatus.pending: return Colors.orange;
      case SlaughterStatus.processed: return Colors.blueGrey;
    }
  }

  Widget _buildMeatSummary(AsyncValue<List<SlaughterLog>> logsAsync) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yield Summary (Today)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.m),
            logsAsync.when(
              data: (logs) {
                final today = DateTime.now();
                final todayLogs = logs.where((l) {
                  final date = l.slaughterTime ?? today;
                  return date.day == today.day && date.month == today.month && date.year == today.year;
                }).toList();

                final totalIntake = todayLogs.fold(0.0, (sum, l) => sum + l.liveWeight);
                final totalYield = todayLogs.where((l) => 
                  l.status == SlaughterStatus.completed || 
                  l.status == SlaughterStatus.processed
                ).fold(0.0, (sum, l) => sum + l.meatWeight);
                final totalWaste = totalIntake - totalYield;

                return Column(
                  children: [
                    SummaryRow(icon: Icons.monitor_weight_outlined, label: 'Gross Intake', value: '${totalIntake.toStringAsFixed(1)}kg'),
                    SummaryRow(icon: Icons.restaurant, label: 'Actual Net Yield', value: '${totalYield.toStringAsFixed(1)}kg'),
                    SummaryRow(icon: Icons.delete_outline, label: 'Recorded Waste', value: '${totalWaste.toStringAsFixed(1)}kg', iconColor: Colors.red),
                  ],
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (err, stack) => const Text("Error loading summary"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Operational Control', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.m),
            _buildActionBtn('New Intake', Icons.add_circle_outline, true, () {
              ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.animalIntake);
            }),
            const SizedBox(height: AppSpacing.s),
            _buildActionBtn('Transfer Stock', Icons.local_shipping_outlined, false, () {
              ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.stockTransfer);
            }),
            const SizedBox(height: AppSpacing.s),
            _buildActionBtn('Record Waste', Icons.delete_sweep, false, () {
              ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.wasteManagement);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(String label, IconData icon, bool primary, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: primary 
        ? ElevatedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white, padding: const EdgeInsets.all(16)))
        : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon, size: 16), label: Text(label, style: const TextStyle(fontSize: 12)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16))),
    );
  }
}
