import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../models/butcher_models.dart';
import '../../services/butcher_service.dart';
import '../../services/user_provider.dart';
import '../../services/butcher_navigation_provider.dart';
import '../../core/utils.dart';
import '../../widgets/responsive_layout.dart';

import '../../core/uuid_utils.dart';

class AnimalIntakeScreen extends ConsumerStatefulWidget {
  const AnimalIntakeScreen({super.key});

  @override
  ConsumerState<AnimalIntakeScreen> createState() => _AnimalIntakeScreenState();
}

class _AnimalIntakeScreenState extends ConsumerState<AnimalIntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tagNumberController = TextEditingController();
  final _manualFarmTagController = TextEditingController(); 
  final _liveWeightController = TextEditingController();
  final _meatWeightController = TextEditingController(); // Added Meat Weight
  final _priceController = TextEditingController();
  final _farmPriceController = TextEditingController(); 
  final _sourceNameController = TextEditingController();
  final _sourceLocationController = TextEditingController();
  final _ownerController = TextEditingController();

  AnimalType? _selectedType;
  bool _isChicken = false;
  bool _isHard = true;
  bool _isSubmitting = false;
  WeightUnit _liveWeightUnit = WeightUnit.kg;
  WeightUnit _meatWeightUnit = WeightUnit.kg;
  double _weightLoss = 0;
  double _yieldPercent = 0;
  DateTime _intakeDate = DateTime.now();


  @override
  void initState() {
    super.initState();
    _tagNumberController.text = _generateTagID();
    
    // Add listeners to calculate loss and yield in real-time
    _liveWeightController.addListener(_calculateMetrics);
    _meatWeightController.addListener(_calculateMetrics);
  }

  void _calculateMetrics() {
    double live = double.tryParse(_liveWeightController.text) ?? 0;
    double meat = double.tryParse(_meatWeightController.text) ?? 0;
    
    // Convert to KG for calculation
    if (_liveWeightUnit == WeightUnit.lb) live = WeightConverter.toKg(live);
    if (_meatWeightUnit == WeightUnit.lb) meat = WeightConverter.toKg(meat);
    
    setState(() {
      _weightLoss = live - meat;
      _yieldPercent = live > 0 ? (meat / live) * 100 : 0;
    });
  }

  @override
  void dispose() {
    _liveWeightController.removeListener(_calculateMetrics);
    _meatWeightController.removeListener(_calculateMetrics);
    super.dispose();
  }

  String _generateTagID() {
    final typeCode = _selectedType?.shortCode ?? 'ANM';
    return IdGenerator.generate(prefix: typeCode);
  }

  Widget _buildTypeDropdown() {
    final List<Map<String, dynamic>> categories = [
      {'label': 'Cow', 'type': AnimalType.cow},
      {'label': 'Bull', 'type': AnimalType.bull},
      {'label': 'Pig', 'type': AnimalType.pig},
      {'label': 'Sheep', 'type': AnimalType.sheep},
      {'label': 'Goat', 'type': AnimalType.goat},
      {'label': 'Chicken', 'type': 'chicken'},
      {'label': 'Turkey', 'type': AnimalType.turkey},
      {'label': 'Rabbit', 'type': AnimalType.rabbit},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<dynamic>(
          initialValue: _isChicken ? 'chicken' : _selectedType,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Animal Type', border: OutlineInputBorder(), isDense: true),
          items: categories.map((c) => DropdownMenuItem(value: c['type'], child: Text(c['label'], overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) {
            setState(() {
              if (v == 'chicken') {
                _isChicken = true;
                _selectedType = _isHard ? AnimalType.hardChicken : AnimalType.softChicken;
              } else {
                _isChicken = false;
                _selectedType = v as AnimalType;
              }
              _tagNumberController.text = _generateTagID();
            });
          },
          validator: (v) => v == null ? 'Required' : null,
        ),
        if (_isChicken) ...[
          const SizedBox(height: AppSpacing.m),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(AppRadius.s),
              border: Border.all(color: AppColors.borderGray),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Chicken Category:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ChoiceChip(
                  label: const Text('Hard (Layers)', style: TextStyle(fontSize: 11)),
                  selected: _isHard,
                  onSelected: (val) {
                    setState(() {
                      _isHard = val;
                      _selectedType = val ? AnimalType.hardChicken : AnimalType.softChicken;
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('Soft (Broilers)', style: TextStyle(fontSize: 11)),
                  selected: !_isHard,
                  onSelected: (val) {
                    setState(() {
                      _isHard = !val;
                      _selectedType = val ? AnimalType.softChicken : AnimalType.hardChicken;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTagNumberField() {
    return TextFormField(
      controller: _tagNumberController,
      decoration: const InputDecoration(labelText: 'Tag Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.tag), isDense: true),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildLiveWeightField() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _liveWeightController,
            decoration: InputDecoration(
              labelText: 'Live Weight (${_liveWeightUnit.name})', 
              hintText: 'e.g. 250.5',
              border: const OutlineInputBorder(), 
              prefixIcon: const Icon(Icons.scale), 
              isDense: true
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => _calculateMetrics(),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<WeightUnit>(
          value: _liveWeightUnit,
          items: WeightUnit.values.where((u) => u != WeightUnit.unit).map((u) => DropdownMenuItem(value: u, child: Text(u.name.toUpperCase()))).toList(),
          onChanged: (v) {
            setState(() {
              _liveWeightUnit = v!;
              _calculateMetrics();
            });
          },
        ),
      ],
    );
  }

  Widget _buildMeatWeightField() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _meatWeightController,
            decoration: InputDecoration(
              labelText: 'Meat Weight (${_meatWeightUnit.name})', 
              hintText: 'e.g. 180.2',
              border: const OutlineInputBorder(), 
              prefixIcon: const Icon(Icons.shopping_basket_outlined), 
              isDense: true
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => _calculateMetrics(),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<WeightUnit>(
          value: _meatWeightUnit,
          items: WeightUnit.values.where((u) => u != WeightUnit.unit).map((u) => DropdownMenuItem(value: u, child: Text(u.name.toUpperCase()))).toList(),
          onChanged: (v) {
            setState(() {
              _meatWeightUnit = v!;
              _calculateMetrics();
            });
          },
        ),
      ],
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      decoration: const InputDecoration(
        labelText: 'Price (₵)', 
        hintText: 'Purchase price e.g. 1500',
        border: OutlineInputBorder(), 
        prefixIcon: Icon(Icons.payments_outlined), 
        isDense: true
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        final n = double.tryParse(v);
        if (n == null || n < 0) return 'Invalid';
        return null;
      },
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(context: context, initialDate: _intakeDate, firstDate: DateTime(2023), lastDate: DateTime.now());
        if (picked != null) setState(() => _intakeDate = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 18, color: AppColors.textLight),
            const SizedBox(width: 8),
            Text(DateFormat('yyyy-MM-dd').format(_intakeDate), style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationField() {
    return TextFormField(
      controller: _sourceLocationController,
      decoration: const InputDecoration(labelText: 'Location/Town', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on_outlined), isDense: true),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  Widget _buildOwnerField() {
    return TextFormField(
      controller: _ownerController,
      decoration: const InputDecoration(labelText: 'Owner Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline), isDense: true),
      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = ResponsiveLayout.isDesktop(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Live Animal Intake', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text('Record animal details and supply source for traceability.', style: TextStyle(color: AppColors.textLight)),
          const SizedBox(height: AppSpacing.xl),
          
          Form(
            key: _formKey,
            child: isDesktop 
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: _buildIntakeForm(isDesktop)),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(flex: 1, child: _buildTraceabilitySummary()),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIntakeForm(isDesktop),
                    const SizedBox(height: AppSpacing.l),
                    _buildTraceabilitySummary(),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntakeForm(bool isDesktop) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            isDesktop 
              ? Row(
                  children: [
                    Expanded(child: _buildTypeDropdown()),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(child: _buildTagNumberField()),
                  ],
                )
              : Column(
                  children: [
                    _buildTypeDropdown(),
                    const SizedBox(height: AppSpacing.m),
                    _buildTagNumberField(),
                  ],
                ),
            const SizedBox(height: AppSpacing.l),
            // Row for Optional Farm Info
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _manualFarmTagController,
                    decoration: const InputDecoration(
                      labelText: 'Farm Tag ID (Optional)', 
                      border: OutlineInputBorder(), 
                      prefixIcon: Icon(Icons.tag_faces_outlined), 
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: TextFormField(
                    controller: _farmPriceController,
                    decoration: const InputDecoration(
                      labelText: 'Farm Price (Optional Cost)', 
                      border: OutlineInputBorder(), 
                      prefixIcon: Icon(Icons.money_off_outlined), 
                      prefixText: '₵ ',
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.l),
            isDesktop 
              ? Row(
                  children: [
                    Expanded(child: _buildLiveWeightField()),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(child: _buildMeatWeightField()),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(child: _buildPriceField()),
                  ],
                )
              : Column(
                  children: [
                    _buildLiveWeightField(),
                    const SizedBox(height: AppSpacing.m),
                    _buildMeatWeightField(),
                    const SizedBox(height: AppSpacing.m),
                    _buildPriceField(),
                  ],
                ),
            if (_liveWeightController.text.isNotEmpty && _meatWeightController.text.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.m),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryMaroon.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.s),
                  border: Border.all(color: AppColors.primaryMaroon.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metricItem('Weight Loss', '${_weightLoss.toStringAsFixed(1)} kg', Colors.red),
                    _metricItem('Yield', '${_yieldPercent.toStringAsFixed(1)}%', Colors.green),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.l),
            _buildDateField(),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.xl),
            const Align(alignment: Alignment.centerLeft, child: Text('Supply Source (Traceability)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            const SizedBox(height: AppSpacing.l),
      TextFormField(
        controller: _sourceNameController,
        decoration: const InputDecoration(
          labelText: 'Source Farm/Name', 
          hintText: 'e.g. Clifford Green Farms',
          border: OutlineInputBorder(), 
          prefixIcon: Icon(Icons.house_siding)
        ),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.m),
            isDesktop 
              ? Row(
                  children: [
                    Expanded(child: _buildLocationField()),
                    const SizedBox(width: AppSpacing.m),
                    Expanded(child: _buildOwnerField()),
                  ],
                )
              : Column(
                  children: [
                    _buildLocationField(),
                    const SizedBox(height: AppSpacing.m),
                    _buildOwnerField(),
                  ],
                ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitIntake,
                icon: _isSubmitting 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
                label: Text(_isSubmitting ? 'Processing...' : 'Confirm Intake & Queue for Slaughter',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTraceabilitySummary() {
    return Column(
      children: [
        Card(
          color: AppColors.primaryMaroon.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppColors.primaryMaroon),
                    SizedBox(width: 8),
                    Text('Data Compliance', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryMaroon)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Every animal intake must be recorded with its source for GRA and Health Department compliance. Generated Batch IDs are used for all downstream processing labels.', 
                  style: TextStyle(fontSize: 12, color: AppColors.textLight)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitIntake() async {
    final user = ref.read(currentUserProvider);
    if (user?.branchCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No branch or shop location assigned. Please contact Admin.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (_selectedType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an animal type.')),
        );
        return;
      }

      setState(() => _isSubmitting = true);

      try {
        final tagNumber = _tagNumberController.text;
        final manualFarmTag = _manualFarmTagController.text.isNotEmpty ? _manualFarmTagController.text : null;
        final type = _selectedType!;
        final double liveWeight = _liveWeightUnit == WeightUnit.kg 
            ? (double.tryParse(_liveWeightController.text) ?? 0) 
            : WeightConverter.toKg(double.tryParse(_liveWeightController.text) ?? 0);
        
        final double meatWeight = _meatWeightUnit == WeightUnit.kg 
            ? (double.tryParse(_meatWeightController.text) ?? 0) 
            : WeightConverter.toKg(double.tryParse(_meatWeightController.text) ?? 0);
        
        final price = double.tryParse(_priceController.text) ?? 0;

        final farmPrice = double.tryParse(_farmPriceController.text);
        final branchCode = user!.branchCode!;

        // Generate proper database UUIDs and human-readable tag numbers
        final String logUuid = UuidUtils.generate();
        final String animalUuid = UuidUtils.generate();

        final log = SlaughterLog(
          id: logUuid,
          animalId: animalUuid, 
          tagNumber: _tagNumberController.text,
          manualFarmTag: manualFarmTag,
          type: type,
          liveWeight: liveWeight,
          meatWeight: meatWeight, // This acts as the estimated meat weight from intake
          price: price,
          farmPrice: farmPrice,
          status: SlaughterStatus.pending, 
          slaughterTime: null,
          branchCode: branchCode,
        );

        // 0. Record the animal first (Queued for safety)
        await ref.read(slaughterLogsProvider.notifier).queueAnimalRecord(
          animalUuid: animalUuid,
          tagNumber: tagNumber,
          manualFarmTag: manualFarmTag,
          type: type,
          weight: liveWeight,
          price: price,
          farmPrice: farmPrice,
          sourceFarm: _sourceNameController.text,
          branchCode: branchCode,
        );

        // 1. Create the slaughter log (Status: Pending)
        await ref.read(slaughterLogsProvider.notifier).addLog(log);
        
        // Note: Batch is created ONLY after "Transport and Receive" in the flow
        
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(child: Text('Livestock Purchased')),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('The livestock record has been added. It is now listed in the Slaughter Log for the next phase.', style: TextStyle(fontSize: 13)),
                      const SizedBox(height: 12),
                      _detailRow('Tag Number', tagNumber),
                      _detailRow('Purchase Wt.', '${liveWeight.toStringAsFixed(1)} kg'),
                      _detailRow('Source', _sourceNameController.text),
                      const SizedBox(height: 16),
                      const Text('Traceability records have been synchronized.',
                        style: TextStyle(fontSize: 11, color: AppColors.textLight)),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _resetForm();
                  },
                  child: const Text('Done'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _resetForm();
                    // Navigate to Slaughter Log screen
                    ref.read(butcherNavProvider.notifier).setScreen(ButcherScreen.slaughterLog);
                  },
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text('Next: Slaughter Log', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to complete intake: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }

  void _resetForm() {
    _formKey.currentState!.reset();
    _liveWeightController.clear();
    _priceController.clear();
    _sourceNameController.clear();
    _sourceLocationController.clear();
    _ownerController.clear();
    _tagNumberController.text = _generateTagID();
  }

  Widget _detailRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textLight)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
        ],
      ),
    );
  }

  Widget _metricItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textLight)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
