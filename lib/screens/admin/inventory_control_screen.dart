import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../services/product_service.dart';
import '../../models/product.dart';
import '../../core/uuid_utils.dart';
import '../../core/utils.dart';
import 'package:intl/intl.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../models/user_model.dart';
import '../../services/transfer_provider.dart';
import '../../widgets/passcode_guard.dart';

import '../../services/product_seeder.dart';
import '../../models/butcher_models.dart';

import '../../widgets/role_pop_scope.dart';

class InventoryControlScreen extends ConsumerStatefulWidget {
  const InventoryControlScreen({super.key});

  @override
  ConsumerState<InventoryControlScreen> createState() => _InventoryControlScreenState();
}

class _InventoryControlScreenState extends ConsumerState<InventoryControlScreen> {
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final activeRole = user.activePrimaryRole;
    final isAdmin = activeRole == UserRole.admin || activeRole == UserRole.superAdmin;

    final theme = Theme.of(context);
    final productsAsync = ref.watch(productsFutureProvider);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/stock';

    // Safety: Reset selected category if it no longer exists after deletions
    if (productsAsync.hasValue) {
      final products = productsAsync.value!;
      final availableCategories = ['All', ...products.where((p) => !p.isDeleted).map((p) => _normalizeCategory(p)).toSet()];
      if (!availableCategories.contains(_selectedCategory)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedCategory = 'All');
        });
      }
    }

    return RolePopScope(
      currentRoute: currentRoute,
      child: PasscodeGuard(
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: const MainAppBar(title: 'Inventory Control', showMenuButton: true),
          drawer: isDesktop
              ? null
              : Drawer(
                  child: AppSidebar(
                    userId: user.id,
                    userName: user.name,
                    userRole: user.activePrimaryRole.name.toUpperCase(),
                    currentRoute: currentRoute,
                    items: MenuService.getMenuItemsForUser(user),
                    onTap: (route) => MenuService.navigate(context, route, currentRoute),
                  ),
                ),
          body: Row(
            children: [
              if (isDesktop)
                AppSidebar(
                  userId: user.id,
                  userName: user.name,
                  userRole: user.activePrimaryRole.name.toUpperCase(),
                  currentRoute: currentRoute,
                  items: MenuService.getMenuItemsForUser(user),
                  onTap: (route) => MenuService.navigate(context, route, currentRoute),
                ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context, ref, productsAsync.value ?? [], isAdmin: isAdmin),
                        const SizedBox(height: AppSpacing.l),
                        _buildFilters(theme, productsAsync.value ?? []),
                        const SizedBox(height: AppSpacing.l),
                        productsAsync.when(
                          data: (products) {
                            final activeProducts = products
                                .where((p) => !p.isDeleted)
                                .where((p) {
                                  final normCat = _normalizeCategory(p);
                                  return _selectedCategory == 'All' || normCat == _selectedCategory;
                                })
                                .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                                               p.category.toLowerCase().contains(_searchQuery.toLowerCase()))
                                .toList();

                            // Sort: Priced products and higher quantity first
                            activeProducts.sort((a, b) {
                              // 1. Priced products (price > 0) come first
                              final bool aPriced = a.retailPrice > 0;
                              final bool bPriced = b.retailPrice > 0;
                              if (aPriced != bPriced) return aPriced ? -1 : 1;
                              
                              // 2. Products with higher quantity come first
                              return b.stockQuantity.compareTo(a.stockQuantity);
                            });
                            
                            if (activeProducts.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(40.0),
                                  child: Text('No products match criteria', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                                ),
                              );
                            }
                            return _buildProductGrid(context, activeProducts, ref, isAdmin: isAdmin);
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (err, _) => Center(child: Text('Error: $err')),
                        ),
                        // Add padding for bottom navigation bars
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: isAdmin ? SafeArea(
            child: FloatingActionButton.extended(
              onPressed: () => _showAddProductDialog(context, ref),
              backgroundColor: theme.colorScheme.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add New Product', style: TextStyle(color: Colors.white)),
            ),
          ) : null,
        ),
      ),
    );
  }

  Widget _buildFilters(ThemeData theme, List<Product> products) {
    final categories = ['All', ...products.map((p) => _normalizeCategory(p)).toSet()];
    final isMobile = ResponsiveLayout.isMobile(context);

    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.m,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: isMobile ? double.infinity : 400,
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search by Name (e.g. Cow), Category (e.g. Pork), or both...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty 
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _searchQuery = ''))
                : null,
              filled: true,
              fillColor: theme.cardTheme.color,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.m),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
            ),
          ),
        ),
        SizedBox(
          width: isMobile ? double.infinity : 200,
          child: DropdownButtonFormField<String>(
            initialValue: categories.contains(_selectedCategory) ? _selectedCategory : 'All',
            decoration: InputDecoration(
              labelText: 'Sort Category',
              filled: true,
              fillColor: theme.cardTheme.color,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
            ),
            items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() => _selectedCategory = v!),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, List<Product> products, {required bool isAdmin}) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final pendingTransfers = ref.watch(pendingIncomingTransfersProvider);

    final actionButtons = [
      if (pendingTransfers.isNotEmpty)
        ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/cashier/verify-stock'),
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: Text('Verify Incoming (${pendingTransfers.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade800,
            foregroundColor: Colors.white,
          ),
        ),
      if (isAdmin) ...[
        PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'unlimited') {
              _showBulkUnlimitedDialog(context, ref, products, true);
            } else if (val == 'fixed') {
              _showBulkUnlimitedDialog(context, ref, products, false);
            }
          },
          child: OutlinedButton.icon(
            onPressed: null, // Let PopupMenuButton handle it
            icon: const Icon(Icons.settings_suggest_outlined, size: 18),
            label: const Text('Bulk Actions', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: theme.colorScheme.primary),
            ),
          ),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'unlimited',
              child: Row(
                children: [
                  Icon(Icons.all_inclusive, size: 18, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Set ALL to Unlimited'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'fixed',
              child: Row(
                children: [
                  Icon(Icons.pin, size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Set ALL to Fixed Qty'),
                ],
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: () => _showPromotionDialog(context, ref, products),
          icon: const Icon(Icons.campaign_outlined, size: 18),
          label: const Text('Promotions', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange.shade800,
            side: BorderSide(color: Colors.orange.shade800),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.pushNamed(context, '/admin/product-report'),
          icon: const Icon(Icons.assessment_outlined, size: 18),
          label: const Text('Activity Report', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
            side: BorderSide(color: theme.colorScheme.primary),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Initialize Catalog?'),
                content: const Text('This will add all default products (Cow, Pork, Hard Chicken (Layer)/Soft Chicken (Broiler), etc.) with 0.0 quantity if they don\'t exist. Continue?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
                  ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('INITIALIZE')),
                ],
              ),
            );
            if (confirm == true) {
              await ref.read(productSeederProvider).seedProducts();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Catalog initialized successfully!')));
              }
            }
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Load Defaults', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.primary,
            side: BorderSide(color: theme.colorScheme.primary),
          ),
        ),
      ]
    ];

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Master Stock List', 
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text('Manage products, pricing, and stock levels', 
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (actionButtons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actionButtons,
            ),
          ],
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Master Stock List', 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text('Manage products, pricing, and stock levels', 
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        if (actionButtons.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: actionButtons,
          ),
          ...actionButtons,
        ],
      ],
    );
  }

  void _showBulkUnlimitedDialog(BuildContext context, WidgetRef ref, List<Product> products, bool isUnlimited) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isUnlimited ? 'Set All to Unlimited?' : 'Set All to Fixed Qty?'),
        content: Text(isUnlimited 
          ? 'This will make every product in the catalog "Unlimited", meaning sales will not decrease the current stock levels. Continue?'
          : 'This will make every product follow "Fixed" stock, where sales will subtract from the defined quantity. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              ref.read(productsFutureProvider.notifier).setUnlimitedStatus(isUnlimited);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('All products updated to ${isUnlimited ? "Unlimited" : "Fixed"} stock.'))
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: isUnlimited ? Colors.blue : Colors.green, foregroundColor: Colors.white),
            child: const Text('PROCEED'),
          ),
        ],
      ),
    );
  }

  void _showPromotionDialog(BuildContext context, WidgetRef ref, List<Product> products, {Product? initialProduct}) {
    final formKey = GlobalKey<FormState>();
    final percentageController = TextEditingController(
      text: initialProduct != null 
        ? (initialProduct.discountPercentage % 1 == 0 
            ? initialProduct.discountPercentage.toInt().toString() 
            : initialProduct.discountPercentage.toString())
        : ''
    );
    final theme = Theme.of(context);
    DateTime? startDate = initialProduct?.promoStartDate;
    DateTime? endDate = initialProduct?.promoEndDate;
    PromoTarget selectedTarget = initialProduct?.promoTarget ?? PromoTarget.both;
    PromoCustomerTarget selectedCustomerTarget = initialProduct?.promoCustomerTarget ?? PromoCustomerTarget.all;
    
    final selectedIds = <String>{};
    if (initialProduct != null) {
      selectedIds.add(initialProduct.id);
    } else {
      for (var p in products) {
        selectedIds.add(p.id);
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final allSelected = selectedIds.length == products.length;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            title: Row(
              children: [
                const Icon(Icons.campaign_outlined, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(child: Text('Run Promotion', style: theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: Form(
              key: formKey,
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                      TextFormField(
                        controller: percentageController,
                        decoration: const InputDecoration(
                          labelText: 'Discount Percentage (%)',
                          hintText: 'e.g. 10 or 12.5',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          final n = double.tryParse(v);
                          if (n == null || n <= 0 || n > 100) return 'Invalid % (0.1 - 100)';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.m),
                      DropdownButtonFormField<PromoTarget>(
                        initialValue: selectedTarget,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Promotion Target'),
                        items: const [
                          DropdownMenuItem(value: PromoTarget.both, child: Text('Both Retail & Wholesale', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: PromoTarget.retail, child: Text('Retail Only', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: PromoTarget.wholesale, child: Text('Wholesale Only', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => selectedTarget = v!),
                      ),
                      const SizedBox(height: AppSpacing.m),
                      DropdownButtonFormField<PromoCustomerTarget>(
                        initialValue: selectedCustomerTarget,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Customer Eligibility'),
                        items: const [
                          DropdownMenuItem(value: PromoCustomerTarget.all, child: Text('All Customers (Public)', overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(value: PromoCustomerTarget.regularsOnly, child: Text('Regulars/Favorites Only', overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => selectedCustomerTarget = v!),
                      ),
                      const SizedBox(height: AppSpacing.m),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            initialDateRange: (startDate != null && endDate != null) 
                              ? DateTimeRange(start: startDate!, end: endDate!)
                              : DateTimeRange(start: DateTime.now(), end: DateTime.now().add(const Duration(days: 7))),
                          );
                          if (picked != null) {
                            setState(() {
                              startDate = picked.start;
                              endDate = picked.end;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: startDate == null ? Colors.grey : theme.colorScheme.primary),
                            borderRadius: BorderRadius.circular(AppRadius.s),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  startDate == null 
                                    ? 'Select Promotion Dates (Required)' 
                                    : '${DateFormat('MMM dd').format(startDate!)} - ${DateFormat('MMM dd').format(endDate!)}',
                                  style: TextStyle(
                                    color: startDate == null ? Colors.grey : theme.colorScheme.onSurface,
                                    fontWeight: startDate == null ? FontWeight.normal : FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.m),
                      const Divider(),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Select Products:', 
                            style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (allSelected) {
                                  selectedIds.clear();
                                } else {
                                  selectedIds.addAll(products.map((p) => p.id));
                                }
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(allSelected ? 'Deselect All' : 'Select All', style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.3),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.dividerColor),
                          borderRadius: BorderRadius.circular(AppRadius.s),
                        ),
                        child: ListView.builder(
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final p = products[index];
                            return CheckboxListTile(
                              title: Text('${p.category} - ${p.name}', style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('Current: ₵${p.retailPrice}', style: const TextStyle(fontSize: 10)),
                              value: selectedIds.contains(p.id),
                              onChanged: (val) {
                                setState(() {
                                  if (val!) {
                                    selectedIds.add(p.id);
                                  } else {
                                    selectedIds.remove(p.id);
                                  }
                                });
                              },
                              dense: true,
                              activeColor: theme.colorScheme.primary,
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          actionsOverflowButtonSpacing: 8,
          actionsAlignment: MainAxisAlignment.end,
          actions: [
              TextButton(
                onPressed: () {
                  ref.read(productsFutureProvider.notifier).clearPromotions();
                  Navigator.pop(context);
                },
                child: const Text('Clear All Promos', style: TextStyle(color: Colors.red, fontSize: 13)),
              ),
              ElevatedButton(
                onPressed: (selectedIds.isEmpty || startDate == null || endDate == null) ? null : () {
                  if (formKey.currentState!.validate()) {
                    final percentage = double.tryParse(percentageController.text) ?? 0;
                    ref.read(productsFutureProvider.notifier).applyPromotion(
                      percentage, 
                      startDate!, 
                      endDate!, 
                      selectedTarget,
                      selectedCustomerTarget,
                      selectedIds: selectedIds.toList()
                    );
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child: Text('Apply to ${selectedIds.length} Items', style: const TextStyle(fontSize: 13)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddProductDialog(BuildContext context, WidgetRef ref) {
    final products = ref.read(productsFutureProvider).value ?? [];
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final retailPriceController = TextEditingController();
    final wholesalePriceController = TextEditingController();
    final costPriceController = TextEditingController();
    final stockController = TextEditingController();
    final otherCategoryController = TextEditingController();
    final customNameController = TextEditingController();
    final theme = Theme.of(context);

    String selectedCategory = 'Cow';
    String? selectedProductName;
    WeightUnit selectedUnit = WeightUnit.kg;
    bool isUnlimited = false;
    ChickenRange? selectedRange;

    final Map<String, List<String>> categoryProductMap = {
      'Hard Chicken (Layer)': [
        'Hard Whole Chicken (Layer)', 'Hard Thigh (Layer)', 'Hard Breast (Layer)', 
        'Hard Back (Layer)', 'Hard Wings (Layer)', 'Hard Drumsticks (Layer)', 
        'Gizzard', 'Other'
      ],
      'Soft Chicken (Broiler)': [
        'Soft Whole Chicken (Broiler)', 'Soft Thigh (Broiler)', 'Soft Breast (Broiler)', 
        'Soft Back (Broiler)', 'Soft Wings (Broiler)', 'Soft Drumsticks (Broiler)', 
        'Gizzard', 'Other'
      ],
      'Beef': [
        'Standard Meat', 'Boneless', 'Cow Steak', 
        'Liver & Lungs', 'Grounded Meat', 'Tail / Padua',
        'Other'
      ],
      'Cow': [
        'Offals / Yemadeɛ', 'Feet', 'Head', 'Other'
      ],
      'Goat': ['Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Head', 'Feet', 'Other'],
      'Sheep': ['Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Head', 'Feet', 'Other'],
      'Pork': [
        'Standard Meat', 'Boneless Meat', 'Offals / Yemadeɛ', 'Pork Steak', 
        'Head', 'Ear', 'Feet', 'Liver', 'Skin',
        'Other'
      ],
      'Turkey': ['Whole Turkey', 'Breast', 'Thighs', 'Drumsticks', 'Wings', 'Gizzards', 'Feet', 'Other'],
      'Rabbit': ['Whole Rabbit', 'Legs', 'Saddle', 'Shoulders', 'Other'],
      'Lamb': ['Standard Meat', 'Boneless', 'Chops', 'Other'],
      'Feeds': ['Dog Feed', 'Other'],
      'Other': ['Custom Entry']
    };

    final existingCategories = products.map((p) => _normalizeCategory(p)).toSet();
    final List<String> categories = categoryProductMap.keys.toList();
    for (var cat in existingCategories) {
      if (!categories.contains(cat)) {
        categories.insert(categories.length - 1, cat);
      }
    }

    Uint8List? imageBytes;
    String? imageName;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Container(
            padding: const EdgeInsets.all(AppSpacing.l),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.l)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add New Product', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Enter product details for the shop catalog', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ],
            ),
          ),
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.all(AppSpacing.l),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: InkWell(
                    onTap: () async {
                      final picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() {
                          imageBytes = bytes;
                          imageName = image.name;
                        });
                      }
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppRadius.m),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: imageBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.m),
                              child: Image.memory(imageBytes!, fit: BoxFit.cover),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(height: 4),
                                Text('Add Image', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.l),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() {
                    selectedCategory = v!;
                    selectedProductName = null;
                    nameController.clear();
                  }),
                ),
                if (selectedCategory == 'Other') ...[
                  const SizedBox(height: AppSpacing.m),
                  _buildFormTextField(
                    context: context,
                    controller: otherCategoryController,
                    label: 'Custom Category Name',
                    hint: 'e.g. Rabbit',
                    icon: Icons.edit_note,
                    isName: true,
                    validator: (v) => (selectedCategory == 'Other' && (v == null || v.isEmpty)) ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.m),
                DropdownButtonFormField<String>(
                  initialValue: selectedProductName,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product Name'),
                  items: (categoryProductMap[selectedCategory] ?? (products.where((p) => p.category == selectedCategory).map((p) => p.name).toSet().toList()..add('Other'))).map((name) {
                    return DropdownMenuItem(value: name, child: Text(name));
                  }).toList(),
                  onChanged: (v) => setState(() {
                    selectedProductName = v;
                    selectedRange = null; // Reset range when product changes
                    if (v != 'Other' && v != 'Custom Entry') {
                      nameController.text = v!;
                    } else {
                      nameController.clear();
                    }
                  }),
                  validator: (v) => (v == null) ? 'Required' : null,
                ),
                if ((selectedCategory == 'Hard Chicken (Layer)' || selectedCategory == 'Soft Chicken (Broiler)') && selectedProductName != 'Gizzard' && selectedProductName != null) ...[
                  const SizedBox(height: AppSpacing.m),
                  DropdownButtonFormField<ChickenRange>(
                    initialValue: selectedRange,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Weight Range (LB)'),
                    items: (selectedCategory == 'Hard Chicken (Layer)' ? AnimalType.hardChicken : AnimalType.softChicken)
                        .chickenRanges
                        .map((r) => DropdownMenuItem(value: r, child: Text(r.label)))
                        .toList(),
                    onChanged: (v) => setState(() => selectedRange = v),
                    // validator removed to make it optional, or use the "No Range" option
                  ),
                ],
                if (selectedProductName == 'Other' || selectedProductName == 'Custom Entry') ...[
                  const SizedBox(height: AppSpacing.m),
                  _buildFormTextField(
                    context: context,
                    controller: customNameController,
                    label: 'Custom Product Name',
                    hint: 'e.g. Sirloin Steak',
                    icon: Icons.edit_note,
                    isName: true,
                    onChanged: (v) => nameController.text = v,
                    validator: (v) => ((selectedProductName == 'Other' || selectedProductName == 'Custom Entry') && (v == null || v.isEmpty)) ? 'Required' : null,
                  ),
                ],
                const SizedBox(height: AppSpacing.m),
                Row(
                  children: [
                    Expanded(
                      child: _buildFormTextField(
                        context: context,
                        controller: retailPriceController,
                        label: 'Retail',
                        prefix: '₵ ',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onTap: () {
                          if (retailPriceController.text == '0.0' || retailPriceController.text == '0') {
                            retailPriceController.clear();
                          }
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid price';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: _buildFormTextField(
                        context: context,
                        controller: wholesalePriceController,
                        label: 'Wholesale',
                        prefix: '₵ ',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onTap: () {
                          if (wholesalePriceController.text == '0.0' || wholesalePriceController.text == '0') {
                            wholesalePriceController.clear();
                          }
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid price';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: _buildFormTextField(
                        context: context,
                        controller: costPriceController,
                        label: 'Cost',
                        prefix: '₵ ',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onTap: () {
                          if (costPriceController.text == '0.0' || costPriceController.text == '0') {
                            costPriceController.clear();
                          }
                        },
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid price';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildFormTextField(
                        context: context,
                        controller: stockController,
                        label: isUnlimited ? 'Current Quantity (Display only)' : 'Initial Stock',
                        suffix: selectedUnit.name,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (isUnlimited) return null;
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid qty';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: DropdownButtonFormField<WeightUnit>(
                        initialValue: selectedUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: WeightUnit.values.map((u) => DropdownMenuItem(value: u, child: Text(u == WeightUnit.unit ? 'PCS' : u.name.toUpperCase()))).toList(),
                        onChanged: (v) => setState(() => selectedUnit = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.m),
                SwitchListTile(
                  title: const Text('Unlimited Stock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Sales will not subtract from quantity', style: TextStyle(fontSize: 11)),
                  value: isUnlimited, 
                  onChanged: (v) => setState(() => isUnlimited = v),
                  activeThumbColor: Colors.blue,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isUploading ? null : () async {
                if (formKey.currentState!.validate()) {
                  setState(() => isUploading = true);
                  
                  String finalImageUrl = 'assets/images/meat_art.jpg';
                  
                  if (imageBytes != null && imageName != null) {
                    final uploadedUrl = await ref.read(productsFutureProvider.notifier).uploadImage(
                      imageBytes!, 
                      'prod_${DateTime.now().millisecondsSinceEpoch}_$imageName'
                    );
                    if (uploadedUrl != null) {
                      finalImageUrl = uploadedUrl;
                    }
                  }

                  String finalName = nameController.text;
                  if ((selectedCategory == 'Hard Chicken (Layer)' || selectedCategory == 'Soft Chicken (Broiler)') && 
                      selectedRange != null && 
                      selectedRange!.label != 'No Range') {
                    if (!finalName.contains(selectedRange!.label)) {
                      finalName = '$finalName (${selectedRange!.label})';
                    }
                  }

                  final String validUuid = UuidUtils.generate();

                  final newProduct = Product(
                    id: validUuid,
                    name: finalName,
                    retailPrice: double.tryParse(retailPriceController.text) ?? 0.0,
                    wholesalePrice: double.tryParse(wholesalePriceController.text) ?? 0.0,
                    costPrice: double.tryParse(costPriceController.text) ?? 0.0,
                    category: selectedCategory == 'Other' ? otherCategoryController.text : selectedCategory,
                    imageUrl: finalImageUrl,
                    stockQuantity: double.tryParse(stockController.text) ?? 0.0,
                    unit: selectedUnit.name,
                    isUnlimited: isUnlimited,
                  );
                  await ref.read(productsFutureProvider.notifier).addProduct(newProduct);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
              ),
              child: isUploading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Add Product'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProductDialog(BuildContext context, WidgetRef ref, Product product) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: product.name);
    final retailPriceController = TextEditingController(text: product.retailPrice.toString());
    final wholesalePriceController = TextEditingController(text: product.wholesalePrice.toString());
    final costPriceController = TextEditingController(text: product.costPrice.toString());
    final otherCategoryController = TextEditingController();
    final theme = Theme.of(context);
    
    final categories = ['Beef', 'Cow', 'Pork', 'Hard Chicken (Layer)', 'Soft Chicken (Broiler)', 'Lamb', 'Goat', 'Turkey', 'Rabbit', 'Feeds', 'Other'];
    String normalized = _normalizeCategory(product);
    String selectedCategory = categories.contains(normalized) ? normalized : 'Other';
    bool isUnlimited = product.isUnlimited;

    if (selectedCategory == 'Other') {
      otherCategoryController.text = product.category;
    }
    
    Uint8List? imageBytes;
    String? imageName;
    bool isUploading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Text('Edit Product: ${product.name}'),
          content: Form(
            key: formKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: InkWell(
                      onTap: () async {
                        final picker = ImagePicker();
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          final bytes = await image.readAsBytes();
                          setState(() {
                            imageBytes = bytes;
                            imageName = image.name;
                          });
                        }
                      },
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.m),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.m),
                          child: imageBytes != null
                              ? Image.memory(imageBytes!, fit: BoxFit.cover)
                              : (product.imageUrl.startsWith('http')
                                  ? Image.network(product.imageUrl, fit: BoxFit.cover)
                                  : Image.asset(product.imageUrl, fit: BoxFit.cover)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  _buildFormTextField(
                    context: context,
                    controller: nameController, 
                    label: 'Product Name',
                    isName: true,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => selectedCategory = v!),
                  ),
                  if (selectedCategory == 'Other') ...[
                    const SizedBox(height: 16),
                    _buildFormTextField(
                      context: context,
                      controller: otherCategoryController,
                      label: 'Custom Category Name',
                      isName: true,
                      validator: (v) => (selectedCategory == 'Other' && (v == null || v.isEmpty)) ? 'Required' : null,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFormTextField(
                          context: context,
                          controller: retailPriceController, 
                          label: 'Retail Price', 
                          prefix: '₵ ',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onTap: () {
                            if (retailPriceController.text == '0.0' || retailPriceController.text == '0') {
                              retailPriceController.clear();
                            }
                          },
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (double.tryParse(v) == null) return 'Invalid price';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFormTextField(
                          context: context,
                          controller: wholesalePriceController, 
                          label: 'Wholesale Price', 
                          prefix: '₵ ',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onTap: () {
                            if (wholesalePriceController.text == '0.0' || wholesalePriceController.text == '0') {
                              wholesalePriceController.clear();
                            }
                          },
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (double.tryParse(v) == null) return 'Invalid price';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFormTextField(
                          context: context,
                          controller: costPriceController, 
                          label: 'Cost Price', 
                          prefix: '₵ ',
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onTap: () {
                            if (costPriceController.text == '0.0' || costPriceController.text == '0') {
                              costPriceController.clear();
                            }
                          },
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (double.tryParse(v) == null) return 'Invalid price';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Unlimited Stock', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Sales will not subtract from quantity', style: TextStyle(fontSize: 11)),
                    value: isUnlimited, 
                    onChanged: (v) => setState(() => isUnlimited = v),
                    activeThumbColor: Colors.blue,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context), 
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))
            ),
            ElevatedButton(
              onPressed: isUploading ? null : () async {
                if (formKey.currentState!.validate()) {
                  setState(() => isUploading = true);

                  String finalImageUrl = product.imageUrl;

                  if (imageBytes != null && imageName != null) {
                    final uploadedUrl = await ref.read(productsFutureProvider.notifier).uploadImage(
                      imageBytes!, 
                      'prod_${DateTime.now().millisecondsSinceEpoch}_$imageName'
                    );
                    if (uploadedUrl != null) {
                      finalImageUrl = uploadedUrl;
                    }
                  }

                  final updated = product.copyWith(
                    name: nameController.text,
                    retailPrice: double.tryParse(retailPriceController.text),
                    wholesalePrice: double.tryParse(wholesalePriceController.text),
                    costPrice: double.tryParse(costPriceController.text),
                    category: selectedCategory == 'Other' ? otherCategoryController.text : selectedCategory,
                    imageUrl: finalImageUrl,
                    isUnlimited: isUnlimited,
                  );
                  await ref.read(productsFutureProvider.notifier).updateProduct(updated);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
              child: isUploading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    String? hint,
    String? prefix,
    String? suffix,
    IconData? icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool isName = false,
    Function(String)? onChanged,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        suffixText: suffix,
        prefixIcon: icon != null ? Icon(icon) : null,
      ),
      keyboardType: keyboardType,
      onChanged: onChanged,
      inputFormatters: [
        if (isName) FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-]')),
        if (keyboardType == const TextInputType.numberWithOptions(decimal: true))
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      validator: validator,
    );
  }

  Widget _buildProductGrid(BuildContext context, List<Product> products, WidgetRef ref, {required bool isAdmin}) {
    return LayoutBuilder(builder: (context, constraints) {
      final isMobile = constraints.maxWidth < 600;
      final crossAxisCount = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 500 ? 2 : 1));
      final aspectRatio = isMobile ? (constraints.maxWidth < 400 ? 1.2 : 1.4) : 0.72;
      
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: products.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.m,
          mainAxisSpacing: AppSpacing.m,
          childAspectRatio: aspectRatio,
        ),
        itemBuilder: (context, index) {
          final product = products[index];
          final isLowStock = product.stockQuantity <= product.lowStockThreshold;
          final hasPromo = product.isPromoScheduled;
          final pendingWeight = ref.watch(productPendingWeightProvider(product.name));
          final hasIncoming = pendingWeight > 0;

          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
            child: isMobile 
              ? InkWell(
                  onTap: isAdmin ? () => _showUpdateStockDialog(context, ref, product) : null,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    child: Row(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.s),
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.s),
                            child: product.imageUrl.isEmpty
                                ? const Icon(Icons.image)
                                : (product.imageUrl.startsWith('assets/') && product.imageUrl.isNotEmpty)
                                    ? Image.asset(
                                        product.imageUrl, 
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(Icons.image),
                                      )
                                    : Image.network(
                                        product.imageUrl, 
                                        fit: BoxFit.cover, 
                                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.image),
                                      ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildFormattedName(product.name, const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                  if (isAdmin) _buildItemMenu(context, ref, product),
                                ],
                              ),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      product.category.toUpperCase(), 
                                      style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (hasIncoming) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                      child: Text('IN TRANSIT', style: TextStyle(color: Colors.blue.shade700, fontSize: 8, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text('₵${product.retailPrice.toStringAsFixed(2)}', 
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                        ),
                                        if (hasPromo) 
                                          Text('PROMO ACTIVE', 
                                            style: TextStyle(color: Colors.orange.shade800, fontSize: 9, fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: (product.isUnlimited ? Colors.blue : (isLowStock ? Colors.red : Colors.green)).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          product.isUnlimited 
                                            ? 'UNLIMITED' 
                                            : '${product.stockQuantity.toStringAsFixed(product.unit == 'unit' ? 0 : 1)}${product.unit == 'unit' ? (product.category == 'CHICKEN' ? " birds" : " pcs") : product.unit}', 
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: product.isUnlimited ? Colors.blue : (isLowStock ? Colors.red : Colors.green))
                                        ),
                                      ),
                                      if (hasIncoming)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text('+${pendingWeight.toStringAsFixed(1)}${product.unit} coming', 
                                            style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                        )
                                      else if (product.dailyStockAdded > 0 && 
                                          product.lastStockUpdate != null && 
                                          product.lastStockUpdate!.year == DateTime.now().year &&
                                          product.lastStockUpdate!.month == DateTime.now().month &&
                                          product.lastStockUpdate!.day == DateTime.now().day)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text('+${product.dailyStockAdded}${product.unit} today', 
                                            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          product.imageUrl.isEmpty
                              ? Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Center(child: Icon(Icons.image)))
                              : (product.imageUrl.startsWith('assets/') && product.imageUrl.isNotEmpty)
                                  ? Image.asset(
                                      product.imageUrl, 
                                      fit: BoxFit.cover, 
                                      width: double.infinity,
                                      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.image)),
                                    )
                                  : Image.network(
                                      product.imageUrl, 
                                      fit: BoxFit.cover, 
                                      width: double.infinity, 
                                      errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.image)),
                                    ),
                          if (isLowStock)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                child: const Text('LOW STOCK', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          if (hasIncoming)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: BorderRadius.circular(4)),
                                child: const Text('IN TRANSIT', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          if (product.retailPrice <= 0)
                            Positioned(
                              top: hasIncoming ? 32 : 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(4)),
                                child: const Text('PRICING REQ', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          if (hasPromo)
                            Positioned(
                              top: (product.retailPrice <= 0 && hasIncoming) ? 56 : (product.retailPrice <= 0 || hasIncoming ? 32 : 8),
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                child: Text(
                                  product.promoCustomerTarget == PromoCustomerTarget.regularsOnly 
                                    ? '-${product.discountPercentage % 1 == 0 ? product.discountPercentage.toInt() : product.discountPercentage}% REGULARS' 
                                    : '-${product.discountPercentage % 1 == 0 ? product.discountPercentage.toInt() : product.discountPercentage}% PROMO', 
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  product.category.toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (hasIncoming) ...[
                                const SizedBox(width: 8),
                                Text('+${pendingWeight.toStringAsFixed(1)}${product.unit} IN TRANSIT', 
                                  style: TextStyle(color: Colors.blue.shade700, fontSize: 8, fontWeight: FontWeight.bold)),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: _buildFormattedName(product.name, const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              if (isAdmin) _buildItemMenu(context, ref, product),
                            ],
                          ),
                          Text(product.category, 
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text('Ret: ₵${product.retailPrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, decoration: product.isPromoActiveFor(false, null, ignoreCustomerFilter: true) ? TextDecoration.lineThrough : null)),
                                    ),
                                    if (product.isPromoActiveFor(false, null, ignoreCustomerFilter: true)) 
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text('₵${product.getPrice(false, ignoreCustomerFilter: true).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                                      ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text('Whl: ₵${product.wholesalePrice.toStringAsFixed(2)}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant, decoration: product.isPromoActiveFor(true, null, ignoreCustomerFilter: true) ? TextDecoration.lineThrough : null)),
                                    ),
                                    if (product.isPromoActiveFor(true, null, ignoreCustomerFilter: true)) 
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text('₵${product.getPrice(true, ignoreCustomerFilter: true).toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange)),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    product.isUnlimited 
                                      ? 'UNLIMITED' 
                                      : '${product.stockQuantity.toStringAsFixed(product.unit == 'unit' ? 0 : 1)}${product.unit == 'unit' ? (product.category == 'CHICKEN' ? " birds" : " pcs") : product.unit}', 
                                    style: TextStyle(fontWeight: FontWeight.bold, color: product.isUnlimited ? Colors.blue : (isLowStock ? Colors.red : Colors.green))
                                  ),
                                  if (hasIncoming)
                                    Text('+${pendingWeight.toStringAsFixed(1)}${product.unit} coming', 
                                      style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue.shade700))
                                  else if (product.dailyStockAdded > 0 &&
                                      product.lastStockUpdate != null && 
                                      product.lastStockUpdate!.year == DateTime.now().year &&
                                      product.lastStockUpdate!.month == DateTime.now().month &&
                                      product.lastStockUpdate!.day == DateTime.now().day)
                                    Text('+${product.dailyStockAdded}${product.unit} today', 
                                      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (isAdmin)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => _showUpdateStockDialog(context, ref, product),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                  foregroundColor: Theme.of(context).colorScheme.primary,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: const Text('Update Stock', style: TextStyle(fontSize: 12)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
          );
        },
      );
    });
  }

  Widget _buildFormattedName(String name, TextStyle baseStyle) {
    if (!name.contains('(')) {
      return Text(name, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    }

    final int splitIndex = name.lastIndexOf('(');
    final String mainName = name.substring(0, splitIndex).trim();
    final String range = name.substring(splitIndex).trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(mainName, style: baseStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(range, 
          style: baseStyle.copyWith(
            fontSize: baseStyle.fontSize! - 2, 
            color: baseStyle.color?.withValues(alpha: 0.7) ?? Colors.black54,
            fontWeight: FontWeight.normal,
          ), 
          maxLines: 1, 
          overflow: TextOverflow.ellipsis
        ),
      ],
    );
  }

  Widget _buildItemMenu(BuildContext context, WidgetRef ref, Product product) {
    final bool isWholeChicken = product.name.contains('Whole Chicken');

    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'edit') {
          _showEditProductDialog(context, ref, product);
        } else if (val == 'portion' && isWholeChicken) {
          _showChickenPortioningDialog(context, ref, product);
        } else if (val == 'delete') {
          _confirmDeleteProduct(context, ref, product);
        } else if (val == 'stop_promo') {
          ref.read(productsFutureProvider.notifier).removePromotion(product.id);
        } else if (val == 'extend_promo') {
          _showPromotionDialog(context, ref, [product], initialProduct: product);
        }
      },
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      itemBuilder: (context) => [
        if (isWholeChicken)
          const PopupMenuItem(
            value: 'portion',
            child: Row(
              children: [
                Icon(Icons.restaurant_rounded, size: 18, color: Colors.orange),
                SizedBox(width: 8),
                Text('Portion Bird'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18),
              SizedBox(width: 8),
              Text('Edit Details'),
            ],
          ),
        ),
        if (product.discountPercentage > 0) ...[
          const PopupMenuItem(
            value: 'extend_promo',
            child: Row(
              children: [
                Icon(Icons.timer_outlined, size: 18, color: Colors.blue),
                SizedBox(width: 8),
                Text('Extend/Modify Promo'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'stop_promo',
            child: Row(
              children: [
                Icon(Icons.block, size: 18, color: Colors.orange),
                SizedBox(width: 8),
                Text('Stop Promotion'),
              ],
            ),
          ),
        ],
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Product', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  void _showUpdateStockDialog(BuildContext context, WidgetRef ref, Product product) {
    final formKey = GlobalKey<FormState>();
    final stockController = TextEditingController();
    final theme = Theme.of(context);
    WeightUnit selectedUnit = WeightUnit.values.firstWhere((u) => u.name == product.unit, orElse: () => WeightUnit.kg);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
          title: Row(
            children: [
              const Icon(Icons.edit_note, color: AppColors.primaryMaroon),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Update Stock: ${product.name}', 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  overflow: TextOverflow.ellipsis
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(AppRadius.s),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2, color: theme.colorScheme.primary),
                        const SizedBox(width: AppSpacing.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Current Inventory', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(WeightConverter.formatShort(product.stockQuantity, unit: product.unit), 
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: theme.colorScheme.primary)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: stockController,
                          decoration: InputDecoration(
                            labelText: selectedUnit == WeightUnit.unit ? 'Add/Remove Qty' : 'Add/Remove (${selectedUnit.name})',
                            hintText: 'e.g. 50.0 or -10.5',
                            helperText: 'Use negative to reduce',
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                          autofocus: true,
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (double.tryParse(v) == null) return 'Invalid';
                            return null;
                          },
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  double change = double.tryParse(stockController.text) ?? 0.0;
                  if (change != 0) {
                    // Normalize to master unit (kg or unit)
                    if (product.unit == 'unit') {
                      // If master is unit, we just add the absolute value
                      ref.read(productsFutureProvider.notifier).updateStock(product.id, change);
                    } else {
                      // If master is weight (kg), we convert from selected unit to kg
                      if (selectedUnit == WeightUnit.g) change = WeightConverter.fromG(change);
                      if (selectedUnit == WeightUnit.lb) change = WeightConverter.toKg(change);
                      ref.read(productsFutureProvider.notifier).updateStock(product.id, change);
                    }
                    Navigator.pop(context);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteProduct(BuildContext context, WidgetRef ref, Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete ${product.name}? This will remove it from the catalog for all terminals.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(productsFutureProvider.notifier).deleteProduct(product.id);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${product.name} deleted successfully'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete Product'),
          ),
        ],
      ),
    );
  }

  void _showChickenPortioningDialog(BuildContext context, WidgetRef ref, Product wholeChicken) {
    final qtyController = TextEditingController(text: '1');
    
    // Weight controllers for all parts
    final thighWeightController = TextEditingController(text: '0');
    final wingWeightController = TextEditingController(text: '0');
    final drumWeightController = TextEditingController(text: '0');
    final breastWeightController = TextEditingController(text: '0');
    final backWeightController = TextEditingController(text: '0');
    final gizzardWeightController = TextEditingController(text: '0');

    final type = wholeChicken.name.contains('Soft') ? 'Soft' : 'Hard';
    bool isProcessing = false;
    WeightUnit selectedUnit = WeightUnit.kg;
    bool isLegSeparated = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Row(
            children: [
              const Icon(Icons.restaurant_rounded, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(child: Text('Portion: ${wholeChicken.name}', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the total weight for each part group resulting from this batch.', 
                style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      decoration: const InputDecoration(
                        labelText: 'Number of Birds',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      const Text('INPUT UNIT', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                      ToggleButtons(
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
                        isSelected: [
                          selectedUnit == WeightUnit.kg, 
                          selectedUnit == WeightUnit.lb,
                        ],
                        onPressed: (index) {
                          setState(() {
                            selectedUnit = index == 0 ? WeightUnit.kg : WeightUnit.lb;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: Colors.white,
                        fillColor: Colors.orange,
                        children: const [
                          Text('kg', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          Text('lb', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(),
              ),
              
              const Text('PART WEIGHTS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange, letterSpacing: 1)),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Separate Thighs & Drumsticks?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                subtitle: const Text('OFF: Thigh includes Drumstick. ON: They are separate.', style: TextStyle(fontSize: 9)),
                value: isLegSeparated, 
                onChanged: (v) => setState(() => isLegSeparated = v),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.orange,
              ),
              const SizedBox(height: 8),
              
              _weightInputField(
                isLegSeparated ? 'Thighs (Separated)' : ((double.tryParse(drumWeightController.text) ?? 0) > 0 ? 'Thighs (Separated)' : 'Thighs (Whole Leg)'), 
                thighWeightController, 
                selectedUnit,
                enabled: isLegSeparated || (double.tryParse(drumWeightController.text) ?? 0) == 0,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              _weightInputField('Wings Weight', wingWeightController, selectedUnit),
              const SizedBox(height: 8),
              _weightInputField(
                isLegSeparated ? 'Drumsticks (Separated)' : ((double.tryParse(thighWeightController.text) ?? 0) > 0 ? 'Drumsticks (Included in Thigh)' : 'Drumsticks Weight'), 
                drumWeightController, 
                selectedUnit,
                enabled: isLegSeparated || (double.tryParse(thighWeightController.text) ?? 0) == 0,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              _weightInputField('Breast Weight', breastWeightController, selectedUnit),
              const SizedBox(height: 8),
              _weightInputField('Back Weight', backWeightController, selectedUnit),
              const SizedBox(height: 8),
              _weightInputField('Gizzard Weight', gizzardWeightController, selectedUnit),
            ],
          ),
          actions: [
            TextButton(onPressed: isProcessing ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isProcessing ? null : () async {
                final int birds = int.tryParse(qtyController.text) ?? 0;
                if (birds <= 0) return;
                
                if (birds > wholeChicken.stockQuantity) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not enough whole chickens in stock!')));
                  return;
                }

                setState(() => isProcessing = true);
                try {
                  final notifier = ref.read(productsFutureProvider.notifier);
                  final products = ref.read(productsFutureProvider).value ?? [];
                  
                  // 0. Extract Range Suffix (e.g. "(3.0 - 4.0 LB)")
                  String rangeSuffix = '';
                  if (wholeChicken.name.contains('(') && wholeChicken.name.contains(')')) {
                    rangeSuffix = wholeChicken.name.substring(wholeChicken.name.lastIndexOf('('));
                  }

                  if (rangeSuffix.isEmpty) {
                    throw Exception('Weight range suffix missing. Cannot portion bird without range.');
                  }

                  // 1. Update Whole Chicken
                  await notifier.updateStock(wholeChicken.id, -birds.toDouble(), reason: 'PORTIONING_REDUCTION');

                  // Helper to convert and update
                  Future<void> updatePart(String partName, String enteredWeight) async {
                    double weight = double.tryParse(enteredWeight) ?? 0.0;
                    if (weight <= 0) return;

                    // Convert to KG for database consistency if needed
                    if (selectedUnit == WeightUnit.lb) {
                      weight = WeightConverter.toKg(weight);
                    }

                    // Find the specific card that matches type (Soft/Hard), Part Name, and Range
                    final part = products.where((p) => 
                      p.name.contains(type) && 
                      p.name.contains(partName) && 
                      p.name.contains(rangeSuffix)
                    ).firstOrNull;

                    if (part != null) {
                      await notifier.updateStock(part.id, weight, reason: 'PORTIONING_ADDITION_${rangeSuffix.replaceAll('(', '').replaceAll(')', '').replaceAll(' ', '')}');
                    }
                  }

                  // 2. Update all parts
                  await updatePart('Thigh', thighWeightController.text);
                  await updatePart('Wings', wingWeightController.text);
                  await updatePart('Drumsticks', drumWeightController.text);
                  await updatePart('Breast', breastWeightController.text);
                  await updatePart('Back', backWeightController.text);

                  // 3. Update Gizzard (Single global card)
                  double gizzardWeight = double.tryParse(gizzardWeightController.text) ?? 0.0;
                  if (gizzardWeight > 0) {
                    if (selectedUnit == WeightUnit.lb) gizzardWeight = WeightConverter.toKg(gizzardWeight);
                    final gizzard = products.firstWhere((p) => p.name.toUpperCase() == 'GIZZARD');
                    await notifier.updateStock(gizzard.id, gizzardWeight, reason: 'PORTIONING_GIZZARD_WEIGHT');
                  }

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Portioned $birds chickens and updated part weights!'), backgroundColor: Colors.green)
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    setState(() => isProcessing = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
              child: isProcessing 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Weights'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weightInputField(String label, TextEditingController controller, WeightUnit unit, {bool enabled = true, Function(String)? onChanged}) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: unit.name,
        border: const OutlineInputBorder(),
        isDense: true,
        fillColor: enabled ? null : Colors.grey.shade100,
        filled: !enabled,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
    );
  }

  String _normalizeCategory(Product p) {
    final cat = p.category.toUpperCase();
    if (cat.contains('BEEF') || cat.contains('COW')) {
      final n = p.name.toUpperCase();
      if (n.contains('HEAD') || n.contains('FEET') || n.contains('OFFAL')) {
        return 'Cow';
      }
      return 'Beef';
    }
    if (cat.contains('HARD LAYER') || cat.contains('HARD CHICKEN')) return 'Hard Chicken (Layer)';
    if (cat.contains('SOFT BROILER') || cat.contains('SOFT CHICKEN')) return 'Soft Chicken (Broiler)';
    if (cat.contains('CHICKEN')) {
      if (p.name.contains('Hard')) return 'Hard Chicken (Layer)';
      if (p.name.contains('Soft')) return 'Soft Chicken (Broiler)';
      return 'Hard Chicken (Layer)'; // Default
    }
    // Title case fallback
    if (cat.isEmpty) return 'Other';
    return cat[0].toUpperCase() + cat.substring(1).toLowerCase();
  }
}
