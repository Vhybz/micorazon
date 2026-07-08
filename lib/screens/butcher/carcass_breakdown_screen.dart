import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../models/butcher_models.dart';
import '../../services/butcher_service.dart';
import '../../core/uuid_utils.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../services/label_service.dart';

class CarcassBreakdownScreen extends ConsumerStatefulWidget {
  const CarcassBreakdownScreen({super.key});

  @override
  ConsumerState<CarcassBreakdownScreen> createState() => _CarcassBreakdownScreenState();
}

class _CarcassBreakdownScreenState extends ConsumerState<CarcassBreakdownScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _units = {}; // Added to track 'kg' vs 'Qty'
  final TextEditingController _wasteController = TextEditingController();
  bool _isSaving = false;
  String? _errorMessage;
  double _totalAccounted = 0;

  @override
  void initState() {
    super.initState();
    final log = ref.read(activeSlaughterLogProvider);
    if (log != null) {
      for (var cut in log.type.standardCuts) {
        _controllers[cut] = TextEditingController();
        _units[cut] = 'kg'; // Default unit
        _controllers[cut]!.addListener(_calculateTotals);
      }
      _wasteController.addListener(_calculateTotals);
    }
  }

  void _calculateTotals() {
    double sum = 0;
    _controllers.forEach((name, controller) {
      // Only count 'kg' units towards the weight balance
      if (_units[name] == 'kg') {
        sum += double.tryParse(controller.text) ?? 0;
      }
    });
    final waste = double.tryParse(_wasteController.text) ?? 0;
    
    setState(() {
      _totalAccounted = sum + waste;
      _errorMessage = null; // Clear error on edit
    });
  }

  @override
  void dispose() {
    _controllers.forEach((_, c) => c.dispose());
    _wasteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(activeSlaughterLogProvider);
    if (log == null) return const Center(child: Text('No active animal selected.'));

    final theme = Theme.of(context);
    final progress = (log.meatWeight > 0) ? (_totalAccounted / log.meatWeight).clamp(0.0, 1.2) : 0.0;
    final remaining = log.meatWeight - _totalAccounted;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.slaughterLog);
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildStickyHeader(log, progress, remaining),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.l),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_errorMessage != null) _buildErrorBanner(),
                          _buildIntakeSummary(log),
                          const SizedBox(height: AppSpacing.xl),
                          _buildCutsGrid(log),
                          const SizedBox(height: AppSpacing.xl),
                          _buildWasteSection(),
                          const SizedBox(height: 100), // Space for bottom action
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomSheet: _buildBottomAction(log),
      ),
    );
  }

  Widget _buildStickyHeader(SlaughterLog log, double progress, double remaining) {
    final theme = Theme.of(context);
    final isOver = remaining < -0.1;
    final isDone = remaining.abs() < 0.1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.slaughterLog),
                icon: const Icon(Icons.arrow_back),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(log.type.displayName, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text('TAG: ${log.tagNumber ?? log.id.substring(0, 8)}', 
                      style: TextStyle(fontSize: 11, color: AppColors.textLight, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isOver ? 'EXCESS WEIGHT' : (isDone ? 'COMPLETED' : 'REMAINING'), 
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: isOver ? Colors.red : (isDone ? Colors.green : Colors.orange)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Text('${remaining.abs().toStringAsFixed(1)} kg', 
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: isOver ? Colors.red : (isDone ? Colors.green : theme.colorScheme.primary)),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress > 1 ? 1 : progress,
              minHeight: 12,
              backgroundColor: Colors.grey.shade200,
              color: isOver ? Colors.red : (isDone ? Colors.green : AppColors.primaryMaroon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
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
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildIntakeSummary(SlaughterLog log) {
    return Card(
      elevation: 0,
      color: AppColors.primaryMaroon.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m), side: BorderSide(color: AppColors.primaryMaroon.withValues(alpha: 0.1))),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(child: _summaryItem('Live Weight', '${log.liveWeight}kg', Icons.pets)),
            Expanded(child: _summaryItem('Intake Meat Est.', '${log.meatWeight}kg', Icons.restaurant)),
            Expanded(child: _summaryItem('Est. Yield', '${log.yieldPercentage.toStringAsFixed(1)}%', Icons.analytics)),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primaryMaroon.withValues(alpha: 0.6)),
        const SizedBox(height: 4),
        Text(label, 
          style: const TextStyle(fontSize: 10, color: AppColors.textLight),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildCutsGrid(SlaughterLog log) {
    final cuts = log.type.standardCuts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CARCASS BREAKDOWN', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                mainAxisExtent: 90,
              ),
              itemCount: cuts.length,
              itemBuilder: (context, index) {
                final cut = cuts[index];
                return _buildCutInput(cut);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildCutInput(String name) {
    final bool isQty = _units[name] == 'Qty';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(name, 
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold), 
                  maxLines: 1, 
                  overflow: TextOverflow.ellipsis
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _units[name] = isQty ? 'kg' : 'Qty';
                    _calculateTotals();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isQty ? Colors.blue.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isQty ? Colors.blue.shade200 : Colors.grey.shade300),
                  ),
                  child: Text(isQty ? 'Qty' : 'kg', 
                    style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: isQty ? Colors.blue : Colors.grey.shade700)
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          TextField(
            controller: _controllers[name],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              suffixText: isQty ? ' units' : ' kg',
              suffixStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.normal, color: Colors.grey),
              hintText: '0.0',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWasteSection() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.l),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.orange,
            child: Icon(Icons.delete_outline, color: Colors.white),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SLAUGHTER WASTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Bones, hides, etc. (Optional)', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _wasteController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '0.0',
                suffixText: ' kg',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomAction(SlaughterLog log) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.l),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 55,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _handleSave,
          icon: _isSaving 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.check_circle_outline),
          label: const Text('SAVE CARCASS & PROCEED', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryMaroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSave() async {
    final log = ref.read(activeSlaughterLogProvider);
    if (log == null) return;

    final remaining = log.meatWeight - _totalAccounted;
    final bool isDone = remaining.abs() < 0.1;

    // 1. Validation - If not "Green", check if all cuts are filled. 
    // If "Green", we can proceed even with some empty fields.
    if (!isDone) {
      bool cutsFilled = true;
      _controllers.forEach((cut, c) { 
        if (c.text.isEmpty) cutsFilled = false; 
      });

      if (!cutsFilled) {
        setState(() => _errorMessage = 'The expected weight has not been reached. Please fill in all cuts or balance the weights.');
        return;
      }
    }

    setState(() => _isSaving = true);
    try {
      final List<MeatCut> meatCuts = [];
      final now = DateTime.now();
      final waste = double.tryParse(_wasteController.text) ?? 0.0;
      double totalCarcassWeight = 0;

      _controllers.forEach((cutName, controller) {
        final val = double.tryParse(controller.text) ?? 0;
        if (_units[cutName] == 'kg') {
          totalCarcassWeight += val;
        }
      });

      // Validation: Carcass weight vs Intake Meat Weight Estimate (Only for kg items)
      if (totalCarcassWeight > (log.meatWeight + 0.5)) { // Allow a tiny buffer
        setState(() {
          _isSaving = false;
          _errorMessage = 'Total accounted weight (${totalCarcassWeight.toStringAsFixed(1)}kg) exceeds the intake meat estimate (${log.meatWeight.toStringAsFixed(1)}kg).';
        });
        return;
      }

      if (!isDone && totalCarcassWeight < (log.meatWeight * 0.85)) { 
        setState(() {
          _isSaving = false;
          _errorMessage = 'Total parts weight is too low. Please reach the green target to proceed.';
        });
        return;
      }

      _controllers.forEach((cutName, controller) {
        final value = double.tryParse(controller.text) ?? 0;
        if (value > 0) {
          meatCuts.add(MeatCut(
            id: UuidUtils.generate(),
            name: cutName,
            meatType: log.type.displayName,
            batchId: log.id,
            weight: value,
            unit: _units[cutName] ?? 'kg',
            processedAt: now,
          ));
        }
      });

      // 2. Record everything
      await ref.read(meatBatchesProvider.notifier).initiateBatchFromSlaughter(
        log: log,
        totalCarcassWeight: totalCarcassWeight,
        cuts: meatCuts,
        waste: waste,
      );

      if (mounted) {
        _showSuccessOverlay(log);
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _errorMessage = 'Error saving: ${e.toString()}';
      });
    }
  }

  void _showSuccessOverlay(SlaughterLog log) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Weights Recorded',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: const Text(
          'The carcass breakdown has been successfully logged. The next step is to receive the animal at the Processing Workstation for dissection.',
          style: TextStyle(fontSize: 13),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () => LabelService.printSlaughterLabel(log),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('PRINT BATCH LABEL'),
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(activeSlaughterLogProvider.notifier).state = null;
                        ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.slaughterLog);
                      },
                      child: const Text('Back to Logs'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(activeSlaughterLogProvider.notifier).state = null;
                        ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.meatProcessing);
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                      label: const Text('TO PROCESSING', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryMaroon, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
