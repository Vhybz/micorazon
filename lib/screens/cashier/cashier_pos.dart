import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/uuid_utils.dart';
import '../../core/utils.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/product_card.dart';
import '../../widgets/cart_item_tile.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/cart_provider.dart';
import '../../services/product_service.dart';
import '../../services/transfer_provider.dart';
import '../../services/sale_provider.dart';
import '../../services/customer_provider.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../services/expense_provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/transfer_models.dart';
import '../../models/sale_model.dart';
import '../../models/product.dart';
import '../../models/customer_model.dart';
import '../../models/user_model.dart';
import '../../services/receipt_service.dart';
import '../../services/sms_service.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/held_receipt_provider.dart';
import '../../services/birthday_service.dart';
import '../../services/branch_provider.dart';
import '../../widgets/phone_prompt_dialog.dart';
import '../../widgets/passcode_guard.dart';

import '../../services/customer_metrics_provider.dart';

enum POSView { sales, history }

class CashierPOS extends ConsumerStatefulWidget {
  const CashierPOS({super.key});

  @override
  ConsumerState<CashierPOS> createState() => _CashierPOSState();
}

class _CashierPOSState extends ConsumerState<CashierPOS> {
  POSView _currentView = POSView.sales;
  String _selectedCategory = 'All';
  
  String _productSearchQuery = '';
  final String _historySearchQuery = '';
  DateTimeRange? _historyDateRange;

  // Selected customer for the current sale
  Customer? _selectedCustomer;
  String? _uploadedReceiptUrl;

  static const Map<String, List<String>> allowedCatalog = {
    'HARD CHICKEN': [
      'Hard Whole Chicken (Layer)', 'Hard Thigh (Layer)', 'Hard Breast (Layer)', 
      'Hard Back (Layer)', 'Hard Wings (Layer)', 'Hard Drumsticks (Layer)', 'Gizzard'
    ],
    'SOFT CHICKEN': [
      'Soft Whole Chicken (Broiler)', 'Soft Thigh (Broiler)', 'Soft Breast (Broiler)', 
      'Soft Back (Broiler)', 'Soft Wings (Broiler)', 'Soft Drumsticks (Broiler)', 'Gizzard'
    ],
    'BEEF': [
      'Standard Meat', 'Boneless', 'Cow Steak', 
      'Liver & Lungs', 'Grounded Meat', 'Tail / Padua'
    ],
    'COW': [
      'Offals / Yemadeɛ', 'Feet', 'Head'
    ],
    'GOAT': ['Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Head', 'Feet'],
    'SHEEP': ['Standard Meat', 'Boneless', 'Offals / Yemadeɛ', 'Head', 'Feet'],
    'PORK': [
      'Standard Meat', 'Boneless Meat', 'Offals / Yemadeɛ', 'Pork Steak',
      'Head', 'Ear', 'Feet', 'Liver', 'Skin'
    ],
    'TURKEY': ['Whole Turkey', 'Breast', 'Thighs', 'Drumsticks', 'Wings', 'Gizzards', 'Feet'],
    'RABBIT': ['Whole Rabbit', 'Legs', 'Saddle', 'Shoulders'],
    'FEEDS': ['Dog Feed'],
  };

  @override
  void initState() {
    super.initState();
    // Force a fresh sync of transfers when the POS opens
    Future.microtask(() {
      ref.read(transferProvider.notifier).loadTransfers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    // Check for Birthday
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        BirthdayService.checkAndShowBirthdayWish(context, user);
      }
    });

    // Instant Permission Guard: Redirect if access is revoked
    final roles = user.activeRoles;
    final hasAccess = roles.contains(UserRole.cashier) || roles.contains(UserRole.superAdmin) || user.enabledPermissions.contains('/cashier');
    
    if (!hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final isWholesale = ref.watch(isWholesaleProvider);
    final menuItems = ref.watch(menuItemsProvider);

    // Safety: Reset selected category if it no longer exists after deletions
    final productsAsync = ref.watch(productsFutureProvider);
    if (productsAsync.hasValue) {
      final products = productsAsync.value!;
      final availableCategories = ['All', ...{
        ...allowedCatalog.keys,
        ...products.where((p) => !p.isDeleted).map((p) => _getMappedCategory(p))
      }];
      if (!availableCategories.contains(_selectedCategory.toUpperCase()) && _selectedCategory != 'All') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedCategory = 'All');
        });
      }
    }

    return RolePopScope(
      currentRoute: '/cashier',
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_currentView != POSView.sales) {
            setState(() => _currentView = POSView.sales);
          } else {
            // Already on Sales (Home), stay here instead of showing exit dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Use the menu to logout or switch accounts'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        },
        child: PasscodeGuard(
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: MainAppBar(
              title: _currentView == POSView.sales 
                  ? 'POS System (${isWholesale ? "Wholesale" : "Retail"})' 
                  : 'Sales History',
              actions: [],
            ),
            drawer: isDesktop ? null : Drawer(child: _buildSidebar(context, user, menuItems)),
            body: Row(
              children: [
                if (isDesktop) _buildSidebar(context, user, menuItems),
                Expanded(
                  child: _currentView == POSView.sales 
                    ? _buildPOSLayout(isMobile, isDesktop)
                    : _buildHistoryLayout(),
                ),
              ],
            ),
            bottomNavigationBar: SafeArea(child: _buildFooter()),
            floatingActionButton: (isMobile && _currentView == POSView.sales)
                ? SafeArea(
                    child: FloatingActionButton.extended(
                      onPressed: () => _showMobileCart(),
                      label: const Text('View Cart'),
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(Icons.shopping_cart),
                          if (ref.watch(cartProvider).isNotEmpty)
                            Positioned(
                              right: -8,
                              top: -8,
                              child: CircleAvatar(
                                radius: 8,
                                backgroundColor: Colors.red,
                                child: Text(
                                  '${ref.watch(cartProvider).length}',
                                  style: const TextStyle(color: Colors.white, fontSize: 8),
                                ),
                              ),
                            ),
                        ],
                      ),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  void _showMobileCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: _buildCartSection(context, ref)),
          ],
        ),
      ),
    );
  }

  void _holdCurrentReceipt() {
    final cartItems = ref.read(cartProvider);
    final total = ref.read(cartProvider.notifier).subtotal;
    
    final saleItems = cartItems.map((item) => SaleItem(
      product: item.product,
      quantity: item.quantity,
      priceAtSale: item.priceAtSale,
      originalPrice: item.originalPrice,
    )).toList();

    // Simple mock logic for discount/promo
    ref.read(heldReceiptProvider.notifier).holdReceipt(
      saleItems, total, 0, null, _selectedCustomer?.name, _selectedCustomer?.phone
    );
    ref.read(cartProvider.notifier).clear();
    setState(() => _selectedCustomer = null);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt held!')));
  }

  Widget _getPaymentMethodIcon(List<PaymentDetail> payments) {
    if (payments.isEmpty) return const SizedBox.shrink();
    if (payments.length > 1) return const Icon(Icons.call_split, size: 12, color: Colors.blue);
    
    final method = payments.first.method;
    switch (method) {
      case PaymentMethod.cash:
        return const Icon(Icons.money, size: 12, color: Colors.green);
      case PaymentMethod.mobileMoney:
        return const Icon(Icons.smartphone, size: 12, color: Colors.orange);
      case PaymentMethod.bankDeposit:
        return const Icon(Icons.account_balance, size: 12, color: Colors.purple);
    }
  }

  void _showHeldReceipts() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.l))),
      builder: (context) {
        final held = ref.watch(heldReceiptProvider);
        if (held.isEmpty) {
          return Container(
            height: 200,
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.list_alt_rounded, size: 48, color: theme.disabledColor),
                const SizedBox(height: 16),
                const Text('No held receipts found.', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Row(
                children: [
                  const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  const Text('HELD TRANSACTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  Text('${held.length} Receipts', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: held.length,
                itemBuilder: (context, index) {
                  final h = held[index];
                  final itemsPreview = h.items.take(2).map((i) => i.product.name).join(', ');
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m), side: BorderSide(color: theme.dividerColor)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Held at ${DateFormat('HH:mm:ss').format(h.timestamp)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('₵${h.totalAmount.toStringAsFixed(2)}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person_outline, size: 14, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(h.customerName ?? 'Walk-in', style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 12),
                              Icon(Icons.shopping_basket_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text('${h.items.length} items', style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                          if (itemsPreview.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(itemsPreview + (h.items.length > 2 ? '...' : ''), 
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ],
                      ),
                      onTap: () {
                        // Resume logic
                        ref.read(cartProvider.notifier).clear();
                        for (var item in h.items) {
                          ref.read(cartProvider.notifier).addItemWithCustomPrice(item.product, item.quantity, item.priceAtSale, item.originalPrice);
                        }
                        ref.read(heldReceiptProvider.notifier).resumeReceipt(h);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }


  Widget _buildPOSLayout(bool isMobile, bool isDesktop) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Container(
            color: theme.scaffoldBackgroundColor,
            child: _buildProductSection(context, ref),
          ),
        ),
        if (!isMobile)
          Container(
            width: isDesktop ? 400 : 300,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: isDark ? const Color(0xFF2C2C2C) : AppColors.borderGray)),
            ),
            child: Material(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              child: _buildCartSection(context, ref),
            ),
          ),
      ],
    );
  }

  Widget _buildSidebar(BuildContext context, UserAccount user, List<SidebarItem> menuItems) {
    const currentRoute = '/cashier';
    return AppSidebar(
      userId: user.id,
      userName: user.name,
      userRole: user.activePrimaryRole.name.toUpperCase(),
      currentRoute: currentRoute,
      items: menuItems,
      onTap: (route) => MenuService.navigate(context, route, currentRoute),
    );
  }

  Widget _buildProductSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final productsAsync = ref.watch(productsFutureProvider);
    final isWholesale = ref.watch(isWholesaleProvider);
    final transfers = ref.watch(transferProvider);

    if (user == null) return const SizedBox.shrink();
    int crossAxisCount = ResponsiveLayout.isMobile(context) ? 2 : (ResponsiveLayout.isTablet(context) ? 3 : 4);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        children: [
          // Build controls with ALL standard categories always visible
          // Build controls with ALL categories found in the database, plus standard ones
          _buildPOSControls(['All', ...{...allowedCatalog.keys, ...productsAsync.value?.where((p) => !p.isDeleted).map((p) => _getMappedCategory(p)) ?? {}}]),
          const SizedBox(height: AppSpacing.m),
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = products
                    .where((p) => !p.isDeleted)
                    .where((p) {
                      final mappedCat = _getMappedCategory(p);
                      
                      // STAGE 2: Visibility Logic
                      // If the category is one of the "standard" ones, we apply a name whitelist.
                      // If it's a custom category OR if the product name was custom-added by admin, we show it.
                      if (allowedCatalog.containsKey(mappedCat)) {
                        final bool isAllowedName = allowedCatalog[mappedCat]!.any((allowedName) => 
                          p.name.toUpperCase().contains(allowedName.toUpperCase())
                        );
                        
                        // If it's not in the standard list, it might be a custom admin entry.
                        // We allow it if the category matches but the name is unique.
                        if (!isAllowedName) {
                          // Check if this was a custom admin entry (not in the seeder defaults for this cat)
                          // For now, we'll allow all admin-added products to show up.
                        }
                      }

                      // STAGE 3: UI Search & Category Filters
                      final matchesCategory = _selectedCategory == 'All' || mappedCat == _selectedCategory;
                      final matchesSearch = p.name.toLowerCase().contains(_productSearchQuery.toLowerCase());
                      
                      return matchesCategory && matchesSearch;
                    })
                    .toList();
                
                // Sort: Highest Quantity first, then Priced items, then Natural Name sort
                filtered.sort((a, b) {
                  // 1. Quantity Priority (Descending)
                  if (a.stockQuantity != b.stockQuantity) {
                    return b.stockQuantity.compareTo(a.stockQuantity);
                  }

                  // 2. Priced Priority (Sellable items first if quantities are equal)
                  final aIsPriced = a.getPrice(isWholesale, customer: _selectedCustomer) > 0.01;
                  final bIsPriced = b.getPrice(isWholesale, customer: _selectedCustomer) > 0.01;
                  if (aIsPriced != bIsPriced) {
                    return aIsPriced ? -1 : 1;
                  }

                  // 3. Natural Name Sort (Covers weight ranges)
                  return _compareNaturally(a.name, b.name);
                });
                
                if (filtered.isEmpty) {
                  return Center(child: Text(_productSearchQuery.isEmpty ? 'No items in this category' : 'No products match "$_productSearchQuery"', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)));
                }

                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: AppSpacing.s,
                    mainAxisSpacing: AppSpacing.s,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    final mappedCat = _getMappedCategory(product);
                    final hasPromo = product.isPromoActiveFor(isWholesale, _selectedCustomer);
                    final currentPrice = product.getPrice(isWholesale, customer: _selectedCustomer);
                    final isPriced = currentPrice > 0.01;
                    
                    // NEW: Check if this specific product is currently being transferred to this branch
                    final bool productInTransit = transfers.any((t) {
                      if (t.status != TransferStatus.pending || t.destination != user.branchCode) return false;
                      
                      final mType = t.meatType.toLowerCase();
                      final pName = product.name.toLowerCase();
                      
                      // Try to split "Animal - Cut"
                      String cutToMatch = mType;
                      if (mType.contains(' - ')) {
                        cutToMatch = mType.split(' - ').last.trim();
                      }

                      return pName == cutToMatch || mType.contains(pName) || pName.contains(cutToMatch);
                    });

                    return ProductCard(
                      name: product.name,
                      category: mappedCat,
                      price: isPriced ? '₵${currentPrice.toStringAsFixed(2)}/${product.unit}' : 'UNPRICED',
                      originalPrice: hasPromo ? '₵${(isWholesale ? product.wholesalePrice : product.retailPrice).toStringAsFixed(2)}' : null,
                      stockQuantity: product.stockQuantity,
                      isUnlimited: product.isUnlimited,
                      lowStockThreshold: product.lowStockThreshold,
                      unit: product.unit,
                      promoLabel: hasPromo ? '${product.name} - ${product.discountPercentage.toInt()}% OFF' : null,
                      imageUrl: product.imageUrl,
                      isInTransit: productInTransit,
                      onTap: isPriced ? () => _showWeightInputDialog(product) : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('This product is not yet priced. Please contact Admin.')),
                        );
                      },
                    );
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

  Widget _buildPOSControls(List<String> categories) {
    final isWholesale = ref.watch(isWholesaleProvider);
    final theme = Theme.of(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 45,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.m),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    Expanded(child: _modeButton('Retail', !isWholesale)),
                    Expanded(child: _modeButton('Wholesale', isWholesale)),
                  ],
                ),
              ),
            ),
            if (!isMobile) ...[
              const SizedBox(width: AppSpacing.m),
              SizedBox(
                width: 200,
                child: _buildCategoryDropdown(categories),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.m),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 45,
                child: TextField(
                  onChanged: (v) => setState(() => _productSearchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search products...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.m),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                ),
              ),
            ),
            if (isMobile) ...[
              const SizedBox(width: AppSpacing.s),
              SizedBox(
                width: 120,
                child: _buildCategoryDropdown(categories),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(List<String> categories) {
    return DropdownButtonFormField<String>(
      initialValue: categories.contains(_selectedCategory) ? _selectedCategory : 'All',
      isExpanded: true, // Crucial for preventing internal overflow
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
        isDense: true,
      ),
      items: categories.map((c) => DropdownMenuItem(
        value: c, 
        child: Text(c, 
          style: const TextStyle(fontSize: 12), 
          overflow: TextOverflow.ellipsis
        )
      )).toList(),
      onChanged: (v) => setState(() {
        _selectedCategory = v!;
        _productSearchQuery = ''; 
      }),
    );
  }

  Widget _modeButton(String label, bool isSelected) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        final newMode = label == 'Wholesale';
        if (ref.read(cartProvider).isNotEmpty) {
          _confirmModeChange(newMode);
        } else {
          ref.read(isWholesaleProvider.notifier).state = newMode;
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.m - 4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  void _confirmModeChange(bool newMode) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Sale Mode?'),
        content: const Text('Changing the mode (Retail/Wholesale) will CLEAR your current cart because prices vary. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              ref.read(isWholesaleProvider.notifier).state = newMode;
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
            child: const Text('Clear Cart & Change'),
          ),
        ],
      ),
    );
  }

  void _showWeightInputDialog(Product product) {
    showDialog(
      context: context,
      builder: (context) => ProductWeightDialog(
        product: product,
        customer: _selectedCustomer,
        onAdd: (weight, price, original) {
          ref.read(cartProvider.notifier).addItemWithCustomPrice(product, weight, price, original);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product.name} (${WeightConverter.formatShort(weight, unit: product.unit)}) added to cart'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCartSection(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cartItems = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Row(
            children: [
              const Icon(Icons.shopping_cart_outlined),
              const SizedBox(width: 8),
              const Text('Current Sale', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              IconButton(
                onPressed: () => _showHeldReceipts(),
                icon: const Icon(Icons.list_alt, color: Colors.blue),
                tooltip: 'View Held Receipts',
              ),
              const Spacer(),
              if (cartItems.isNotEmpty)
                IconButton(
                  onPressed: () => _holdCurrentReceipt(),
                  icon: const Icon(Icons.pause_circle_outline, color: Colors.orange),
                  tooltip: 'Hold Receipt',
                ),
              if (cartItems.isNotEmpty)
                IconButton(
                  onPressed: () => notifier.clear(),
                  icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        // Customer Selection
        Material(
          color: Colors.transparent,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.person_outline, size: 20),
            title: Text(_selectedCustomer?.name ?? 'Select Customer', 
              style: TextStyle(fontWeight: _selectedCustomer != null ? FontWeight.bold : FontWeight.normal, color: theme.colorScheme.onSurface)),
            subtitle: _selectedCustomer != null ? Text(_selectedCustomer!.phone, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedCustomer != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.red),
                    onPressed: () => setState(() => _selectedCustomer = null),
                    tooltip: 'Remove Customer',
                  ),
                IconButton(
                  icon: Icon(_selectedCustomer == null ? Icons.add_circle_outline : Icons.edit, size: 18),
                  onPressed: () => _showCustomerDialog(),
                ),
              ],
            ),
            onTap: () => _showCustomerDialog(),
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: cartItems.isEmpty
              ? Center(child: Text('Cart is empty', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
              : ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.m),
                  itemCount: cartItems.length,
                  itemBuilder: (context, index) {
                    final item = cartItems[index];
                    return CartItemTile(
                      category: item.product.category,
                      name: item.product.name,
                      qty: '1',
                      weight: WeightConverter.formatShort(item.quantity, unit: item.product.unit),
                      amount: '₵${item.total.toStringAsFixed(2)}',
                      onDelete: () => notifier.removeItem(index),
                    );
                  },
                ),
        ),
        _buildCartSummary(ref),
      ],
    );
  }

  Future<bool> _showBulkPurchaseCustomerDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Row(
          children: [
            Icon(Icons.shopping_cart_checkout, color: Colors.blue),
            SizedBox(width: 12),
            Text('Bulk Purchase Detected'),
          ],
        ),
        content: const Text(
          'This sale exceeds ₵800.00. For records and loyalty tracking, we need to register this as a Bulk Purchase.\n\nWould you like to select or add a customer now?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL SALE'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            child: const Text('PROCEED TO CUSTOMER'),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _showCustomerDialog({bool isBulk = false}) async {
    await showDialog(
      context: context,
      builder: (context) => CustomerSelectionDialog(
        isBulk: isBulk,
        onSelected: (customer) {
          setState(() {
            _selectedCustomer = customer;
            
            // Auto-Switch Sale Mode based on customer type
            final isWholesale = ref.read(isWholesaleProvider);
            if (customer.isWholesaler && !isWholesale) {
              // Suggest switching to wholesale or just do it?
              // For now, let's just do it to be fast, but clear the cart as required
              if (ref.read(cartProvider).isEmpty) {
                ref.read(isWholesaleProvider.notifier).state = true;
              } else {
                _showModeSwitchOnCustomerSelect(true);
              }
            } else if (!customer.isWholesaler && isWholesale) {
              if (ref.read(cartProvider).isEmpty) {
                ref.read(isWholesaleProvider.notifier).state = false;
              } else {
                _showModeSwitchOnCustomerSelect(false);
              }
            }
          });
        },
      ),
    );
  }

  void _showModeSwitchOnCustomerSelect(bool targetWholesale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${targetWholesale ? "Wholesaler" : "Retailer"} Detected'),
        content: Text('This customer is registered as a ${targetWholesale ? "Wholesaler" : "Retailer"}. Would you like to switch the sale mode? \n\n(This will CLEAR your current cart)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('KEEP CURRENT')),
          ElevatedButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              ref.read(isWholesaleProvider.notifier).state = targetWholesale;
              Navigator.pop(context);
            },
            child: const Text('SWITCH MODE & CLEAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartSummary(WidgetRef ref) {
    final theme = Theme.of(context);
    final cartItems = ref.watch(cartProvider);
    final isWholesale = ref.watch(isWholesaleProvider);
    final subtotal = ref.watch(cartProvider.notifier).subtotal;

    // Promotion Logic
    double discountPercentage = 0;
    String promoLabel = '';
    
    if (isWholesale && subtotal > 0) {
      final totalWeight = cartItems.fold(0.0, (sum, item) => sum + item.quantity);
      final bool isFavorite = _selectedCustomer?.isFavorite ?? false;
      
      if (isFavorite) {
        discountPercentage = 0.10;
        promoLabel = '${cartItems.first.product.category} - Favorite Customer Reward (10% OFF)';
      } else if (totalWeight >= 10) {
        discountPercentage = 0.05;
        promoLabel = '${cartItems.first.product.category} - Bulk Purchase Reward (5% OFF)';
      }
    }

    final discount = subtotal * discountPercentage;
    final total = subtotal - discount;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Column(
        children: [
          if (discount > 0) ...[
            _summaryRow('Subtotal', '₵${subtotal.toStringAsFixed(2)}', fontSize: 13),
            _summaryRow(promoLabel, '-₵${discount.toStringAsFixed(2)}', color: Colors.green, fontSize: 12),
            const SizedBox(height: 8),
          ],
          _summaryRow('TOTAL DUE', '₵${total.toStringAsFixed(2)}', isBold: true, fontSize: 20, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.m),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: cartItems.isEmpty ? null : () => _showPaymentDialog(total, discount, promoLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
              ),
              child: const Text('PROCEED TO PAYMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 45,
            child: OutlinedButton.icon(
              onPressed: cartItems.isEmpty ? null : () => _showDebtSaleDialog(total, discount, promoLabel),
              icon: const Icon(Icons.money_off, size: 18),
              label: const Text('SAVE AS DEBT', style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade800,
                side: BorderSide(color: Colors.orange.shade800),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.m)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isBold = false, double fontSize = 14, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, 
              style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: color ?? theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  void _showDebtSaleDialog(double finalTotal, double discount, String promo) async {
    // 1. Force Customer Selection if none selected
    if (_selectedCustomer == null) {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: const Row(
            children: [
              Icon(Icons.person_search, color: Colors.blue),
              SizedBox(width: 12),
              Text('Customer Required'),
            ],
          ),
          content: const Text('This is a debt sale. You must select an existing customer profile or register a new one to proceed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'), 
              child: const Text('CANCEL SALE')
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'new'), 
              child: const Text('REGISTER NEW')
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'select'), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('SELECT CUSTOMER')
            ),
          ],
        ),
      );

      if (choice == 'select') {
        await _showCustomerDialog();
      } else if (choice == 'new') {
        await _showCustomerRegistrationDialog();
      } else {
        return; // User canceled or dismissed
      }
    }

    // Safety: If still null after selection flow, stop.
    if (_selectedCustomer == null) return;

    // 2. Partial Payment Dialog with Change Option
    final partialPaymentController = TextEditingController();
    
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: const Row(
            children: [
              Icon(Icons.money_off, color: Colors.orange),
              SizedBox(width: 12),
              Text('Confirm Debt Sale'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('Recording debt for ${_selectedCustomer!.name}.', style: const TextStyle(fontSize: 13))),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context); // Close confirm
                      await _showCustomerDialog(); // Select new
                      _showDebtSaleDialog(finalTotal, discount, promo); // Restart flow
                    },
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('CHANGE', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Total Amount: ₵${finalTotal.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: partialPaymentController,
                decoration: const InputDecoration(
                  labelText: 'Partial Cash Payment (Optional)',
                  prefixText: '₵ ',
                  border: OutlineInputBorder(),
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              const Text('The balance will be saved as outstanding debt.', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: () {
                final double partial = double.tryParse(partialPaymentController.text) ?? 0;
                List<PaymentDetail> payments = [];
                if (partial > 0) {
                  payments.add(PaymentDetail(
                    method: PaymentMethod.cash, 
                    amount: partial,
                  ));
                }
                Navigator.pop(context);
                _completeSale(ref, payments, finalTotal, discount, promo);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
              child: const Text('CONFIRM DEBT SALE'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomerRegistrationDialog() async {
    await showDialog(
      context: context,
      builder: (context) => CustomerSelectionDialog(
        isBulk: true, // Forces "New Customer" view
        onSelected: (customer) {
          setState(() {
            _selectedCustomer = customer;
          });
        },
      ),
    );
  }

  void _showPaymentDialog(double finalTotal, double discount, String promo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PaymentDialog(
        totalAmount: finalTotal,
        onComplete: (payments, receiptUrl) {
          setState(() => _uploadedReceiptUrl = receiptUrl);
          _completeSale(ref, payments, finalTotal, discount, promo);
        },
      ),
    );
  }

  void _completeSale(WidgetRef ref, List<PaymentDetail> payments, double finalTotal, double discount, String promo) async {
    final cartItems = ref.read(cartProvider);
    final currentUser = ref.read(currentUserProvider);
    
    final double amountPaid = payments.fold(0.0, (sum, p) => sum + p.amount);
    final double balance = finalTotal - amountPaid;
    final double totalCost = cartItems.fold(0.0, (sum, item) => sum + (item.product.costPrice * item.quantity));

    // High Value Sale Enforcement: If total >= 800, prompt for customer
    if (finalTotal >= 800 && _selectedCustomer == null) {
      final proceed = await _showBulkPurchaseCustomerDialog();
      if (!proceed) return;
      
      await _showCustomerDialog(isBulk: true);
      if (_selectedCustomer == null) return;
    }

    // Debt Enforcement: If there's a balance, a customer MUST be selected
    if (balance > 0.01 && _selectedCustomer == null) {
      final proceed = await _showDebtCustomerRequiredDialog();
      if (!proceed) return;
      
      // Open customer dialog and wait for it
      await _showCustomerDialog();
      
      // If they registered/selected a customer, _selectedCustomer will be non-null now
      if (_selectedCustomer == null) return; 
    }

    final hasBankDeposit = payments.any((p) => p.method == PaymentMethod.bankDeposit);

    final sale = SaleRecord(
      id: 'INV-${DateTime.now().millisecondsSinceEpoch}',
      items: cartItems.map((item) => SaleItem(
        product: item.product,
        quantity: item.quantity,
        priceAtSale: item.priceAtSale,
        originalPrice: item.originalPrice,
      )).toList(),
      totalAmount: finalTotal,
      totalDiscount: discount,
      totalCost: totalCost,
      appliedPromo: promo.isEmpty ? null : promo,
      payments: payments,
      timestamp: DateTime.now(),
      cashierName: currentUser != null ? '${currentUser.firstName} ${currentUser.surname}' : 'Unknown Cashier',
      cashierId: currentUser?.id ?? 'N/A',
      customerName: _selectedCustomer?.name,
      customerPhone: _selectedCustomer?.phone,
      status: hasBankDeposit ? SaleStatus.awaitingDeposit : SaleStatus.completed,
      isVerified: !hasBankDeposit, // Cash/MoMo sales are verified immediately
      bankReceiptUrl: _uploadedReceiptUrl,
    );

    await ref.read(saleHistoryProvider.notifier).addSale(sale);
    ref.read(cartProvider.notifier).clear();
    
    // Send SMS with branch identification
    final currentBranch = ref.read(currentBranchProvider);
    final String? branchName = currentBranch != null 
        ? '${currentBranch.name} (${currentBranch.location})' 
        : null;

    SmsService.sendReceiptSms(sale, discountAmount: discount, branchName: branchName);

    setState(() {
      _selectedCustomer = null;
      _uploadedReceiptUrl = null;
    });

    _showPrintConfirmation(sale);
  }

  Future<bool> _showDebtCustomerRequiredDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Customer Required', 
                style: TextStyle(fontSize: ResponsiveLayout.isMobile(context) ? 18 : null),
                overflow: TextOverflow.ellipsis
              ),
            ),
          ],
        ),
        content: const Text(
          'This transaction has an outstanding balance (Debt). \n\n'
          'To track this debt, you must select or register a customer before completing the sale.'
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel Sale'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryMaroon, 
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const FittedBox(
                    child: Text('Register / Select Customer', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showPrintConfirmation(SaleRecord sale) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ReceiptSuccessDialog(
        sale: sale,
        ref: ref,
      ),
    );
  }

  Widget _buildFooter() {
    final theme = Theme.of(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final pendingCount = ref.watch(pendingIncomingTransfersProvider).length;

    return Container(
      height: 65,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _footerAction(Icons.point_of_sale, 'New Sale', _currentView == POSView.sales, () => setState(() => _currentView = POSView.sales)),
          if (isMobile)
            _footerAction(
              Icons.qr_code_scanner_rounded, 
              'Incoming Stock', 
              false, 
              () => Navigator.pushNamed(context, '/cashier/verify-stock'),
              badge: pendingCount > 0 ? pendingCount : null,
            ),
          _footerAction(Icons.history, 'Transaction History', _currentView == POSView.history, () => setState(() => _currentView = POSView.history)),
        ],
      ),
    );
  }

  Widget _footerAction(IconData icon, String label, bool isSelected, VoidCallback onTap, {int? badge}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
              Text(label, style: TextStyle(
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              )),
            ],
          ),
          if (badge != null && badge > 0)
            Positioned(
              right: -4,
              top: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Center(
                  child: Text(
                    '$badge',
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showDateFilterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.today),
            title: const Text('Today'),
            onTap: () {
              final now = DateTime.now();
              setState(() => _historyDateRange = DateTimeRange(start: now, end: now));
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Yesterday'),
            onTap: () {
              final yesterday = DateTime.now().subtract(const Duration(days: 1));
              setState(() => _historyDateRange = DateTimeRange(start: yesterday, end: yesterday));
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Specific Day'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await showDatePicker(
                context: context,
                initialDate: _historyDateRange?.start ?? DateTime.now(),
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _historyDateRange = DateTimeRange(start: picked, end: picked));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.date_range),
            title: const Text('Date Range'),
            onTap: () async {
              Navigator.pop(context);
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: _historyDateRange,
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => _historyDateRange = picked);
              }
            },
          ),
          const SizedBox(height: AppSpacing.l),
        ],
      ),
    );
  }

  Widget _buildHistoryLayout() {
    final theme = Theme.of(context);
    final salesHistory = ref.watch(saleHistoryProvider);
    final filteredHistory = salesHistory.where((s) {
      final matchesSearch = s.id.toLowerCase().contains(_historySearchQuery.toLowerCase());
      
      bool matchesDate = true;
      if (_historyDateRange != null) {
        final start = DateTime(_historyDateRange!.start.year, _historyDateRange!.start.month, _historyDateRange!.start.day);
        final end = DateTime(_historyDateRange!.end.year, _historyDateRange!.end.month, _historyDateRange!.end.day, 23, 59, 59);
        matchesDate = s.timestamp.isAfter(start.subtract(const Duration(seconds: 1))) && 
                      s.timestamp.isBefore(end.add(const Duration(seconds: 1)));
      }
      
      return matchesSearch && matchesDate;
    }).toList();

    // Stats calculations
    double totalSales = 0;
    double totalCost = 0;
    final Map<String, ({double qty, String category})> productStatsMap = {};

    for (var sale in filteredHistory) {
      if (sale.status == SaleStatus.cancelled) continue;
      totalSales += sale.totalAmount;
      totalCost += sale.totalCost;
      for (var item in sale.items) {
        final existing = productStatsMap[item.product.name];
        productStatsMap[item.product.name] = (
          qty: (existing?.qty ?? 0) + item.quantity,
          category: item.product.category
        );
      }
    }
    final totalProfit = totalSales - totalCost;

    return Column(
      children: [
        // Non-scrollable Header (Date Filter)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, 0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: () => _showDateFilterOptions(context),
                  icon: const Icon(Icons.date_range),
                  label: Text(_historyDateRange == null 
                    ? 'Select Date' 
                    : _historyDateRange!.start.day == _historyDateRange!.end.day && 
                      _historyDateRange!.start.month == _historyDateRange!.end.month && 
                      _historyDateRange!.start.year == _historyDateRange!.end.year
                      ? DateFormat('MMM dd').format(_historyDateRange!.start)
                      : '${DateFormat('MMM dd').format(_historyDateRange!.start)} - ${DateFormat('MMM dd').format(_historyDateRange!.end)}'),
                ),
              ),
              if (_historyDateRange != null)
                IconButton(
                  onPressed: () => setState(() => _historyDateRange = null),
                  icon: const Icon(Icons.close, size: 18, color: Colors.red),
                  tooltip: 'Clear Filter',
                ),
              if (_historyDateRange != null && filteredHistory.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final period = '${DateFormat('MMM dd, yyyy').format(_historyDateRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_historyDateRange!.end)}';
                      ReceiptService.printDetailedHistoryReport(filteredHistory, period: period);
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('PRINT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Scrollable Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (filteredHistory.isNotEmpty) ...[
                  _buildHistorySummaryCards(totalSales, totalProfit, theme),
                  const SizedBox(height: 24),
                  Text('SALES TREND', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 12),
                  _buildSalesChart(filteredHistory, theme),
                  const SizedBox(height: 24),
                  Text('HIGHEST PURCHASED PRODUCTS', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 12),
                  _buildProductQtyList(productStatsMap, theme),
                  const SizedBox(height: 24),
                ],

                Text('TRANSACTION LOG', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 12),
                filteredHistory.isEmpty 
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text('No transactions found.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filteredHistory.length,
                      itemBuilder: (context, index) {
                        final sale = filteredHistory[index];
                        return _buildHistoryCard(sale);
                      },
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryCard(SaleRecord sale) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
          child: Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(sale.id, 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), 
                overflow: TextOverflow.ellipsis
              ),
            ),
            const SizedBox(width: 8),
            Text('₵${sale.totalAmount.toStringAsFixed(2)}', 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('${DateFormat('HH:mm').format(sale.timestamp)} • ${sale.items.length} items', style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 8),
                _getPaymentMethodIcon(sale.payments),
                if (sale.status != SaleStatus.completed) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: _getStatusColor(sale.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _getStatusColor(sale.status).withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      sale.status.name.toUpperCase(),
                      style: TextStyle(color: _getStatusColor(sale.status), fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
            Text('Cust: ${sale.customerName ?? "Walk-in"}', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showSaleDetails(sale),
      ),
    );
  }

  Widget _buildHistorySummaryCards(double totalSales, double totalProfit, ThemeData theme) {
    return Row(
      children: [
        _summaryStatCard('TOTAL SALES', '₵${totalSales.toStringAsFixed(2)}', theme.colorScheme.primary, theme),
        const SizedBox(width: 12),
        _summaryStatCard('TOTAL PROFIT', '₵${totalProfit.toStringAsFixed(2)}', AppColors.accentGreen, theme),
      ],
    );
  }

  Widget _summaryStatCard(String label, String value, Color color, ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(AppRadius.m),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart(List<SaleRecord> sales, ThemeData theme) {
    if (sales.isEmpty) return const SizedBox.shrink();

    // Group sales by day (Last 7 days or selected range)
    final now = DateTime.now();
    final List<DateTime> dates = [];
    bool isSingleDay = false;

    if (_historyDateRange != null) {
      DateTime d = _historyDateRange!.start;
      while (d.isBefore(_historyDateRange!.end.add(const Duration(days: 1)))) {
        dates.add(DateTime(d.year, d.month, d.day));
        d = d.add(const Duration(days: 1));
      }
      if (dates.length == 1) isSingleDay = true;
    } else {
      // Default to last 7 days
      for (int i = 6; i >= 0; i--) {
        final d = now.subtract(Duration(days: i));
        dates.add(DateTime(d.year, d.month, d.day));
      }
    }

    final List<double> chartData;
    final List<String> labels;

    if (isSingleDay) {
      // Hourly breakdown for single day
      final targetDate = dates.first;
      // We'll show blocks: 8am, 10am, 12pm, 2pm, 4pm, 6pm, 8pm (common business hours)
      final hours = [8, 10, 12, 14, 16, 18, 20];
      chartData = hours.map((h) {
        return sales
            .where((s) => s.timestamp.year == targetDate.year && 
                          s.timestamp.month == targetDate.month && 
                          s.timestamp.day == targetDate.day &&
                          s.timestamp.hour >= h && s.timestamp.hour < h + 2 &&
                          s.status != SaleStatus.cancelled)
            .fold(0.0, (sum, s) => sum + s.totalAmount);
      }).toList();
      labels = hours.map((h) => '${h > 12 ? h - 12 : h}${h >= 12 ? 'pm' : 'am'}').toList();
    } else {
      chartData = dates.map((date) {
        return sales
            .where((s) => s.timestamp.year == date.year && s.timestamp.month == date.month && s.timestamp.day == date.day && s.status != SaleStatus.cancelled)
            .fold(0.0, (sum, s) => sum + s.totalAmount);
      }).toList();
      labels = dates.map((d) => DateFormat('E').format(d).substring(0, 1)).toList();
    }

    final maxTotal = chartData.isEmpty ? 100.0 : (chartData.reduce((a, b) => a > b ? a : b) + 50.0);

    return Container(
      height: 200,
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: theme.dividerColor),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxTotal,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.primary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '₵${rod.toY.toStringAsFixed(0)}',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < labels.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        labels[index],
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
                reservedSize: 28,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(chartData.length, (index) {
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: chartData[index],
                  color: theme.colorScheme.primary,
                  width: isSingleDay ? 24 : 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildProductQtyList(Map<String, ({double qty, String category})> statsMap, ThemeData theme) {
    final sortedProducts = statsMap.entries.toList()
      ..sort((a, b) => b.value.qty.compareTo(a.value.qty));
    
    final totalQty = statsMap.values.fold(0.0, (sum, val) => sum + val.qty);

    return Column(
      children: sortedProducts.take(10).map((e) {
        final double percentage = totalQty > 0 ? (e.value.qty / totalQty) : 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(AppRadius.s),
            border: Border.all(color: theme.dividerColor),
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
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(e.value.category.toUpperCase(), style: TextStyle(fontSize: 9, color: theme.colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  Text(WeightConverter.formatShort(e.value.qty, unit: 'kg'), 
                    style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w900, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percentage,
                  minHeight: 6,
                  backgroundColor: theme.dividerColor,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _showReceiptOptionsDialog(SaleRecord sale) {
    final currentBranch = ref.read(currentBranchProvider);
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), // Rectangular
          title: const Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppColors.primaryMaroon),
              SizedBox(width: 12),
              Text('RECEIPT OPTIONS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 16)),
            ],
          ),
          content: isProcessing 
            ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _receiptOptionTile(
                    context,
                    icon: Icons.print_rounded,
                    title: 'PRINT RECEIPT',
                    subtitle: 'Send to thermal printer',
                    onTap: () async {
                      setState(() => isProcessing = true);
                      await ReceiptService.printReceipt(sale);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 10),
                  _receiptOptionTile(
                    context,
                    icon: Icons.sms_rounded,
                    title: 'SEND VIA SMS',
                    subtitle: sale.customerPhone ?? 'Enter custom number',
                    enabled: true,
                    onTap: () async {
                      String? targetPhone = sale.customerPhone;
                      
                      if (targetPhone == null || targetPhone.isEmpty) {
                        targetPhone = await PhonePromptDialog.show(context);
                      }

                      if (targetPhone != null && targetPhone.isNotEmpty) {
                        setState(() => isProcessing = true);
                        final success = await SmsService.sendReceiptSms(
                          sale, 
                          branchName: currentBranch?.name,
                          customPhone: targetPhone,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success ? 'SMS Sent' : 'SMS Failed'),
                              backgroundColor: success ? Colors.green : Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _receiptOptionTile(
                    context,
                    icon: Icons.share_rounded,
                    title: 'SHARE PDF (WHATSAPP)',
                    subtitle: 'Share via WhatsApp or Email',
                    onTap: () async {
                      setState(() => isProcessing = true);
                      await ReceiptService.shareReceipt(sale);
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ],
              ),
          actions: [
            TextButton(
              onPressed: isProcessing ? null : () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _receiptOptionTile(BuildContext context, {
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: enabled ? theme.colorScheme.primary.withValues(alpha: 0.05) : theme.disabledColor.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: enabled ? theme.colorScheme.primary.withValues(alpha: 0.1) : theme.disabledColor.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            Icon(icon, color: enabled ? theme.colorScheme.primary : theme.disabledColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: enabled ? theme.colorScheme.onSurface : theme.disabledColor, letterSpacing: 0.5)),
                  Text(subtitle, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (enabled) Icon(Icons.keyboard_arrow_right_rounded, color: theme.colorScheme.primary.withValues(alpha: 0.3), size: 18),
          ],
        ),
      ),
    );
  }

  void _showSaleDetails(SaleRecord sale) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final theme = Theme.of(context);
          
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
            backgroundColor: theme.colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450, maxHeight: 650),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.l)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Transaction Details',
                                style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                sale.id,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('STATUS', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _getStatusColor(sale.status).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        sale.status.name.toUpperCase(),
                                        style: TextStyle(color: _getStatusColor(sale.status), fontSize: 10, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('DATE', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('MMM dd, yyyy HH:mm').format(sale.timestamp), 
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.right,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          Row(
                            children: [
                              const Icon(Icons.person_outline, size: 16, color: AppColors.textLight),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('CUSTOMER', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                    Text(sale.customerName ?? 'Walk-in Customer', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('CASHIER', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                                    Text(sale.cashierName.split(' ')[0], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          Text('ITEMS', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          ...sale.items.map((item) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.product.category.toUpperCase(), style: TextStyle(color: theme.colorScheme.primary, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                      Text(item.product.name, 
                                        style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 13),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text('${WeightConverter.formatShort(item.quantity, unit: item.product.unit)} x ₵${item.priceAtSale.toStringAsFixed(2)}', 
                                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text('₵${item.total.toStringAsFixed(2)}', 
                                  style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: 13)
                                ),
                              ],
                            ),
                          )),
                          const Divider(height: 32),
                          if (sale.totalDiscount > 0) ...[
                            _detailRow('Gross Amount', '₵${sale.baseTotal.toStringAsFixed(2)}'),
                            _detailRow('Total Discount', '-₵${sale.totalDiscount.toStringAsFixed(2)}', color: Colors.green),
                            const SizedBox(height: 4),
                          ],
                          _detailRow('NET INVOICE VALUE', '₵${sale.netInvoiceValue.toStringAsFixed(2)}', isBold: true, color: theme.colorScheme.primary),
                          const Divider(height: 32),
                          Text('PAYMENT HISTORY', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          ...sale.payments.map((p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      p.method == PaymentMethod.cash ? Icons.money : 
                                      (p.method == PaymentMethod.mobileMoney ? Icons.smartphone : Icons.account_balance), 
                                      size: 14, color: theme.colorScheme.onSurfaceVariant
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      p.method.name.toUpperCase(), 
                                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface)
                                    ),
                                    if (p.reference != null)
                                      Text(' (${p.reference})', style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                                Text('₵${p.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )),
                          if (sale.balance > 0.01) ...[
                             const SizedBox(height: 8),
                             _detailRow('BALANCE DUE', '₵${sale.balance.toStringAsFixed(2)}', color: Colors.red, isBold: true),
                          ],
                          if (sale.bankReceiptUrl != null) ...[
                            const Divider(height: 32),
                            Text('BANK DEPOSIT RECEIPT', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            InkWell(
                              onTap: () => _viewBankReceipt(sale.bankReceiptUrl!, receiptId: sale.bankReceiptId),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: theme.dividerColor),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.image_outlined, size: 20, color: Colors.purple),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('View Uploaded Receipt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple)),
                                          if (sale.bankReceiptId != null)
                                            Text('ID: ${sale.bankReceiptId}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.open_in_new, size: 16, color: Colors.purple),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.m),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(top: BorderSide(color: theme.dividerColor)),
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadius.l)),
                    ),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowSpacing: 8,
                      children: [
                        if (sale.status == SaleStatus.awaitingDeposit)
                          ElevatedButton.icon(
                            onPressed: () => _showBankReceiptUploadDialog(sale),
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('UPLOAD RECEIPT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                          ),
                        if (!sale.isVerified && sale.status != SaleStatus.awaitingDeposit)
                          ElevatedButton.icon(
                            onPressed: () {
                              ref.read(saleHistoryProvider.notifier).verifySale(sale.id);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Transaction Verified. Inventory updated.'), backgroundColor: Colors.green),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('VERIFY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                          ),
                        if (sale.status == SaleStatus.completed)
                          TextButton.icon(
                            onPressed: () => _showReportErrorDialog(sale),
                            icon: const Icon(Icons.report_problem_outlined, color: Colors.orange, size: 16),
                            label: const Text('Report Error', style: TextStyle(color: Colors.orange, fontSize: 11)),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context), 
                          child: Text('Close', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12))
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showReceiptOptionsDialog(sale),
                          icon: const Icon(Icons.receipt_long_rounded, size: 14),
                          label: const Text('RECEIPT OPTIONS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentOrange, 
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }

  void _showBankReceiptUploadDialog(SaleRecord sale) {
    final receiptIdController = TextEditingController();
    Uint8List? selectedImageBytes;
    bool isUploading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: const Row(
            children: [
              Icon(Icons.account_balance, color: Colors.purple),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Complete Bank Deposit',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please provide the bank transaction reference/ID and a photo of the deposit slip.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: receiptIdController,
                    decoration: const InputDecoration(
                      labelText: 'Bank Receipt ID / Reference',
                      hintText: 'e.g. UMB-123456',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag),
                    ),
                    onChanged: (_) => setState(() {}), // Refresh to enable/disable button
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picker = ImagePicker();
                      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        setState(() => selectedImageBytes = bytes);
                      }
                    },
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selectedImageBytes != null ? Colors.purple : Colors.grey.shade300),
                      ),
                      child: selectedImageBytes != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(selectedImageBytes!, fit: BoxFit.cover),
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined, color: Colors.purple, size: 32),
                                SizedBox(height: 8),
                                Text('Select Deposit Slip Photo', style: TextStyle(fontSize: 11, color: Colors.purple)),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (isUploading || selectedImageBytes == null || receiptIdController.text.isEmpty)
                  ? null
                  : () async {
                      setState(() => isUploading = true);
                      try {
                        final fileName = 'bank_${sale.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                        final url = await ref.read(expenseProvider.notifier).uploadReceipt(selectedImageBytes!, fileName);
                        
                        if (url != null) {
                          await ref.read(saleHistoryProvider.notifier).verifySale(
                            sale.id, 
                            bankReceiptUrl: url,
                            bankReceiptId: receiptIdController.text.trim(),
                          );
                          if (context.mounted) {
                            Navigator.pop(context); // Close dialog
                            Navigator.pop(context); // Close sale details
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Bank details saved & sale verified!'), backgroundColor: Colors.green),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => isUploading = false);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
              child: isUploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirm & Verify'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewBankReceipt(String url, {String? receiptId}) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bank Deposit Slip', style: TextStyle(fontSize: 16)),
                  if (receiptId != null)
                    Text('REF: $receiptId', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                ],
              ),
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.m),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stackTrace) => const Center(child: Text('Could not load image')),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportErrorDialog(SaleRecord sale) {
    final theme = Theme.of(context);
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: const Row(
          children: [
            Icon(Icons.report_problem_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('Report Sale Error'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Please describe the error (e.g., wrong weight). This will notify the Admin for rectification.', 
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Enter reason here...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.isNotEmpty) {
                ref.read(saleHistoryProvider.notifier).updateSale(
                  sale.copyWith(
                    status: SaleStatus.pendingCorrection,
                    correctionReason: reasonController.text,
                  )
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Error reported to Administrator.'), backgroundColor: Colors.orange),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Submit Report'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(SaleStatus status) {
    switch (status) {
      case SaleStatus.completed: return Colors.green;
      case SaleStatus.rectified: return Colors.blue;
      case SaleStatus.pendingCorrection: return Colors.orange;
      case SaleStatus.cancelled: return Colors.red;
      case SaleStatus.reversed: return Colors.red.shade900;
      case SaleStatus.awaitingDeposit: return Colors.purple;
    }
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(value, 
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? theme.colorScheme.onSurface)
            ),
          ),
        ],
      ),
    );
  }

  String _getMappedCategory(Product p) {
    final cat = p.category.toUpperCase();
    final name = p.name.toUpperCase();
    if (cat.contains('HARD') || cat.contains('LAYER') || (cat.contains('CHICKEN') && name.contains('HARD'))) {
      return 'HARD CHICKEN';
    }
    if (cat.contains('SOFT') || cat.contains('BROILER') || (cat.contains('CHICKEN') && name.contains('SOFT'))) {
      return 'SOFT CHICKEN';
    }
    return cat;
  }

  int _compareNaturally(String a, String b) {
    final RegExp digitRegex = RegExp(r'(\d+\.?\d*)');
    final Match? aMatch = digitRegex.firstMatch(a);
    final Match? bMatch = digitRegex.firstMatch(b);

    if (aMatch != null && bMatch != null) {
      final aNum = double.tryParse(aMatch.group(0)!) ?? 0;
      final bNum = double.tryParse(bMatch.group(0)!) ?? 0;
      if (aNum != bNum) return aNum.compareTo(bNum);
    }
    return a.toLowerCase().compareTo(b.toLowerCase());
  }
}

class ProductWeightDialog extends StatefulWidget {
  final Product product;
  final Customer? customer;
  final Function(double weight, double price, double original) onAdd;

  const ProductWeightDialog({super.key, required this.product, this.customer, required this.onAdd});

  @override
  State<ProductWeightDialog> createState() => _ProductWeightDialogState();
}

class _ProductWeightDialogState extends State<ProductWeightDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weightController;
  final _qtyController = TextEditingController(text: '1');
  final _moneyController = TextEditingController(); // NEW: For money-to-weight calculation
  WeightUnit _unit = WeightUnit.kg;
  double _weight = 1.0;
  int _quantity = 1;
  bool _isHalf = false; 

  void _toggleUnit(WeightUnit unit) {
    if (_unit == unit) return;
    setState(() {
      if (_unit != WeightUnit.unit && unit != WeightUnit.unit) {
        if (unit == WeightUnit.kg) {
          _weight = WeightConverter.toKg(_weight);
        } else {
          _weight = WeightConverter.toLb(_weight);
        }
      }
      _unit = unit;
      _weightController.text = _weight.toStringAsFixed(2);
      _moneyController.clear(); // Clear money when unit changes to avoid confusion
    });
  }

  @override
  void initState() {
    super.initState();
    final String pName = widget.product.name.toUpperCase();
    final String pCat = widget.product.category.toUpperCase();
    
    if (pName.contains('HEAD') && (pCat.contains('GOAT') || pCat.contains('SHEEP'))) {
      _unit = WeightUnit.unit;
      _weight = 1.0;
    } else {
      _unit = WeightUnit.values.firstWhere(
        (u) => u.name == widget.product.unit, 
        orElse: () => WeightUnit.kg
      );
      _weight = 1.0;
    }
    
    _weightController = TextEditingController(text: _weight.toStringAsFixed(_unit == WeightUnit.unit ? 0 : 1));
  }

  @override
  void dispose() {
    _weightController.dispose();
    _qtyController.dispose();
    _moneyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isWholeChicken = widget.product.name.contains('Whole Chicken');

    return Consumer(
      builder: (context, ref, _) {
        final isWholesale = ref.watch(isWholesaleProvider);
        final isPcs = _unit == WeightUnit.unit;
        
        final currentPrice = widget.product.getPrice(isWholesale, weight: isPcs ? 1.0 : _weight, customer: widget.customer);
        final hasPromo = widget.product.isPromoActiveFor(isWholesale, widget.customer);
        final basePrice = isWholesale ? (widget.product.wholesalePrice) : (widget.product.retailPrice);
        
        double comparisonPrice = basePrice;
        final brackets = isWholesale ? widget.product.wholesaleBrackets : widget.product.retailBrackets;
        if (!isPcs && _weight > 0 && brackets != null && brackets.isNotEmpty) {
           double kgCheck = _unit == WeightUnit.lb ? WeightConverter.toKg(_weight) : (_unit == WeightUnit.g ? WeightConverter.fromG(_weight) : _weight);
           for (var bracket in brackets) {
            if (kgCheck >= bracket.minWeight && kgCheck <= bracket.maxWeight) {
              comparisonPrice = bracket.price;
              break;
            }
          }
        }

        final double finalEffectiveQty = _isHalf ? 0.5 : _weight;
        final double finalPrice = currentPrice;
        
        double kgWeight = _weight;
        if (_unit == WeightUnit.lb) {
          kgWeight = WeightConverter.toKg(_weight);
        } else if (_unit == WeightUnit.g) {
          kgWeight = WeightConverter.fromG(_weight);
        }

        final double total = isPcs 
            ? (finalEffectiveQty * finalPrice * _quantity) 
            : (kgWeight * currentPrice * _quantity);

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.l),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.product.category.toUpperCase(),
                      style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    Text(
                      widget.product.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    
                    // MONEY INPUT (CALCULATE WEIGHT FROM PRICE)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CALCULATE FROM MONEY (₵)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _moneyController,
                            decoration: const InputDecoration(
                              hintText: 'Enter customer amount...',
                              isDense: true,
                              prefixText: '₵ ',
                              border: InputBorder.none,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: theme.colorScheme.primary),
                            onChanged: (v) {
                              final amount = double.tryParse(v) ?? 0;
                              if (amount > 0 && finalPrice > 0) {
                                setState(() {
                                  double calcWeight = amount / finalPrice;
                                  // Normalize to selected unit
                                  if (_unit == WeightUnit.lb) {
                                    _weight = WeightConverter.toLb(calcWeight);
                                  } else if (_unit == WeightUnit.g) {
                                    _weight = calcWeight * 1000;
                                  } else {
                                    _weight = calcWeight;
                                  }
                                  _weightController.text = _weight.toStringAsFixed(_unit == WeightUnit.unit ? 0 : 2);
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),

                    if (isWholeChicken) ...[
                      const Text('SELECT SIZE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('FULL BIRD')),
                              selected: !_isHalf,
                              onSelected: (v) => setState(() => _isHalf = false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('HALF BIRD')),
                              selected: _isHalf,
                              onSelected: (v) => setState(() => _isHalf = true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.m),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            const Text('SELECT UNIT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                            const SizedBox(height: 4),
                            ToggleButtons(
                              constraints: const BoxConstraints(minWidth: 55, minHeight: 40),
                              isSelected: [
                                _unit == WeightUnit.kg, 
                                _unit == WeightUnit.g,
                                _unit == WeightUnit.lb,
                                _unit == WeightUnit.unit,
                              ],
                              onPressed: (index) => _toggleUnit(WeightUnit.values[index]),
                              borderRadius: BorderRadius.circular(8),
                              selectedColor: Colors.white,
                              fillColor: theme.colorScheme.primary,
                              children: const [
                                Text('kg', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                Text('g', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                Text('lb', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                Text('pcs', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            textAlign: TextAlign.center,
                            enabled: !_isHalf,
                            decoration: InputDecoration(
                              labelText: isPcs ? 'Quantity' : 'Weight',
                              suffixText: isPcs ? 'pcs' : _unit.name,
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              errorText: (isPcs ? finalEffectiveQty : kgWeight) > widget.product.stockQuantity 
                                ? 'Only ${widget.product.stockQuantity}${isPcs ? "pcs" : "kg"} available' 
                                : null,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                            onChanged: (v) {
                              setState(() => _weight = double.tryParse(v) ?? 0);
                              _moneyController.clear(); // Clear money if manually typing weight
                            },
                            validator: (v) {
                              if (_isHalf) return null;
                              if (v == null || (double.tryParse(v) ?? 0) <= 0) return '!';
                              final val = double.tryParse(v) ?? 0;
                              final checkWeight = isPcs ? val : (_unit == WeightUnit.kg ? val : WeightConverter.toKg(val));
                              if (checkWeight > widget.product.stockQuantity) return 'Insufficient Stock';
                              return null;
                            },
                          ),
                        ),
                        if (!isPcs) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _qtyController,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: 'Packs',
                                suffixText: 'qty',
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                errorText: (kgWeight * _quantity) > widget.product.stockQuantity
                                  ? 'Exceeds total stock'
                                  : null,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (v) => setState(() => _quantity = int.tryParse(v) ?? 1),
                              validator: (v) {
                                if (v == null || (int.tryParse(v) ?? 0) <= 0) return '!';
                                if ((kgWeight * (int.tryParse(v) ?? 1)) > widget.product.stockQuantity) return 'Exceeds stock';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    if (widget.product.stockQuantity <= 0)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red, size: 16),
                            SizedBox(width: 8),
                            Text('FINISHED: OUT OF STOCK', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ),
                    const SizedBox(height: AppSpacing.m),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasPromo) ...[
                              Text('₵${comparisonPrice.toStringAsFixed(2)}', 
                                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, decoration: TextDecoration.lineThrough, fontSize: 12)),
                              const SizedBox(width: 6),
                            ],
                            Text('₵${finalPrice.toStringAsFixed(2)}/${isPcs ? "unit" : "kg"}', 
                              style: TextStyle(color: hasPromo ? Colors.orange.shade800 : theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        Text(
                          'Total: ₵${total.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: theme.colorScheme.primary),
                        ),
                        if (_isHalf)
                          const Text('(Half Bird Pricing Applied)', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.m),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (widget.product.stockQuantity <= 0 || (isPcs ? finalEffectiveQty : (kgWeight * _quantity)) > widget.product.stockQuantity)
                          ? null 
                          : () {
                            if (_formKey.currentState!.validate()) {
                              final isWholesale = ref.read(isWholesaleProvider);
                              
                              // Calculate final normalized weight/qty for inventory
                              double effectiveQty = _isHalf ? 0.5 : _weight;
                              if (_unit == WeightUnit.lb && !_isHalf) {
                                effectiveQty = WeightConverter.toKg(_weight);
                              } else if (_unit == WeightUnit.g && !_isHalf) {
                                effectiveQty = WeightConverter.fromG(_weight);
                              }

                              final double actualSalePrice = widget.product.getPrice(isWholesale, weight: isPcs ? 1.0 : effectiveQty, customer: widget.customer);
                              
                              double comparisonPrice = isWholesale ? (widget.product.wholesalePrice) : (widget.product.retailPrice);
                              
                              widget.onAdd(effectiveQty * (_isHalf ? 1 : _quantity), actualSalePrice, comparisonPrice);
                              Navigator.pop(context);
                            }
                          },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                        ),
                        child: Text(widget.product.stockQuantity <= 0 ? 'ITEM FINISHED' : 'Add to Cart', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CustomerSelectionDialog extends ConsumerStatefulWidget {
  final Function(Customer) onSelected;
  final bool isBulk;
  const CustomerSelectionDialog({super.key, required this.onSelected, this.isBulk = false});

  @override
  ConsumerState<CustomerSelectionDialog> createState() => _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends ConsumerState<CustomerSelectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _locationController = TextEditingController();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late bool _isNewCustomer;
  bool _isWholesaler = false; // NEW

  @override
  void initState() {
    super.initState();
    _isNewCustomer = widget.isBulk; 
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customerProvider);
    final metrics = ref.watch(customerMetricsProvider);
    final theme = Theme.of(context);

    final List<Customer> sortedCustomers = List.from(customers);
    if (_searchQuery.isEmpty) {
      // Sort by spending when not searching
      sortedCustomers.sort((a, b) {
        final spendA = metrics[a.phone]?.totalSpend ?? 0;
        final spendB = metrics[b.phone]?.totalSpend ?? 0;
        return spendB.compareTo(spendA);
      });
    }

    final filtered = sortedCustomers.where((c) => 
      c.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
      c.phone.contains(_searchQuery)
    ).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _isNewCustomer ? 'REGISTER CUSTOMER' : 'SELECT CUSTOMER',
                      style: TextStyle(
                        color: theme.colorScheme.primary, 
                        fontSize: ResponsiveLayout.isMobile(context) ? 12 : 13, 
                        fontWeight: FontWeight.w900, 
                        letterSpacing: 1.2
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(_isNewCustomer ? Icons.group_rounded : Icons.person_add_alt_1_rounded, color: theme.colorScheme.primary, size: 20),
                    onPressed: () => setState(() => _isNewCustomer = !_isNewCustomer),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              if (!_isNewCustomer) ...[
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search name or phone...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: filtered.isEmpty
                    ? const Center(child: Text('No matches found.', style: TextStyle(color: AppColors.textLight, fontSize: 12)))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                              child: Icon(c.isFavorite ? Icons.star : Icons.person,
                                  color: c.isFavorite ? Colors.orange : theme.colorScheme.primary, size: 20),
                            ),
                            title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(
                              '${c.isWholesaler ? "WHOLESALER" : "RETAILER"} • ${c.phone}${c.location != null ? " • ${c.location}" : ""}', 
                              style: TextStyle(fontSize: 10, color: c.isWholesaler ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant, fontWeight: c.isWholesaler ? FontWeight.bold : FontWeight.normal)
                            ),
                            onTap: () {
                              widget.onSelected(c);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                ),
              ] else ...[
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.badge_outlined)),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(labelText: 'Primary Phone', prefixIcon: Icon(Icons.phone_outlined)),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                            validator: (v) => v!.length != 10 ? 'Invalid' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _phone2Controller,
                            decoration: const InputDecoration(labelText: 'Alternative Phone (Optional)', prefixIcon: Icon(Icons.phone_iphone_rounded)),
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _locationController,
                            decoration: const InputDecoration(labelText: 'Location / Area', prefixIcon: Icon(Icons.location_on_outlined)),
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 16),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Customer Category', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(child: Text('RETAILER')),
                                  selected: !_isWholesaler,
                                  onSelected: (v) => setState(() => _isWholesaler = false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: const Center(child: Text('WHOLESALER')),
                                  selected: _isWholesaler,
                                  onSelected: (v) => setState(() => _isWholesaler = true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  final user = ref.read(currentUserProvider);
                                  final String validUuid = UuidUtils.generate();

                                  final newCustomer = Customer(
                                    id: validUuid,
                                    branchCode: user?.branchCode,
                                    name: _nameController.text,
                                    phone: _phoneController.text,
                                    phone2: _phone2Controller.text.isEmpty ? null : _phone2Controller.text,
                                    location: _locationController.text,
                                    isBulkPurchaser: widget.isBulk,
                                    isWholesaler: _isWholesaler,
                                  );
                                  
                                  try {
                                    // 1. Trigger the add (now optimistic and non-blocking for network)
                                    ref.read(customerProvider.notifier).addCustomer(newCustomer);
                                    
                                    // 2. Immediately select and close dialog
                                    widget.onSelected(newCustomer);
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error adding customer: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary, 
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Register & Select', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text('DISMISS', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PaymentDialog extends ConsumerStatefulWidget {
  final double totalAmount;
  final Function(List<PaymentDetail>, String?) onComplete;

  const PaymentDialog({super.key, required this.totalAmount, required this.onComplete});

  @override
  ConsumerState<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<PaymentDetail> _payments = [];
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  final _amountController = TextEditingController();
  final _refController = TextEditingController();

  String? _receiptUrl;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.totalAmount.toStringAsFixed(2);
  }

  void _addPayment() {
    if (_formKey.currentState!.validate()) {
      final amount = double.tryParse(_amountController.text) ?? 0;
      // Allow zero amount for credit/debt sales
      if (amount < 0) return; 

      setState(() {
        _payments.add(PaymentDetail(
          method: _selectedMethod,
          amount: amount,
          reference: _refController.text.isEmpty ? null : _refController.text,
          isPaystack: false,
        ));
        final paid = _payments.fold(0.0, (sum, p) => sum + p.amount);
        final remaining = (widget.totalAmount - paid).clamp(0.0, widget.totalAmount);
        _amountController.text = remaining > 0 ? remaining.toStringAsFixed(2) : '0.00';
        _refController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = _payments.fold(0.0, (sum, p) => sum + p.amount);
    final remaining = (widget.totalAmount - paid).clamp(0.0, widget.totalAmount);
    final bool isMoMo = _selectedMethod == PaymentMethod.mobileMoney;
    final bool isBank = _selectedMethod == PaymentMethod.bankDeposit;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.l, AppSpacing.l, AppSpacing.l, AppSpacing.m),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.payments_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'COLLECT PAYMENT',
                    style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                  ),
                ],
              ),
              const Divider(height: 24),
              SingleChildScrollView(
                child: Column(
                  children: [
                    // Compact Summary Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: AppSpacing.m),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.m),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        children: [
                          _billRow(context, 'Total Invoice', '₵${widget.totalAmount.toStringAsFixed(2)}', theme),
                          const SizedBox(height: 6),
                          _billRow(context, 'Balance Due', '₵${remaining.toStringAsFixed(2)}', theme, 
                            color: remaining > 0 ? Colors.red : Colors.green, isBold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Compact Method Selector
                    Row(
                      children: PaymentMethod.values.map((m) {
                        final isSelected = _selectedMethod == m;
                        String label = m.name.toUpperCase();
                        if (m == PaymentMethod.mobileMoney) label = 'MOMO';
                        if (m == PaymentMethod.bankDeposit) label = 'BANK';

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () {
                              setState(() {
                                _selectedMethod = m;
                                _amountController.text = remaining.toStringAsFixed(2);
                              });
                            },
                              borderRadius: BorderRadius.circular(AppRadius.s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(AppRadius.s),
                                  border: Border.all(color: isSelected ? theme.colorScheme.primary : theme.dividerColor),
                                  boxShadow: isSelected ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))] : null,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      m == PaymentMethod.cash ? Icons.money_rounded : 
                                      (m == PaymentMethod.mobileMoney ? Icons.smartphone_rounded : Icons.account_balance_rounded),
                                      color: isSelected ? Colors.white : theme.colorScheme.primary,
                                      size: 22,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 10, 
                                        fontWeight: FontWeight.w900, 
                                        color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _amountController, 
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              labelText: 'Amount to Apply', 
                              prefixText: '₵ ', 
                              isDense: true,
                              helperText: isBank ? 'Customer will provide deposit slip later' : 'Enter 0 for full credit/debt sale',
                              helperStyle: const TextStyle(fontSize: 9),
                            ),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => setState(() {}),
                            validator: (v) {
                              if (v == null || v.isEmpty) return '!';
                              final val = double.tryParse(v);
                              if (val == null || val < 0) return '!';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _refController,
                            decoration: InputDecoration(
                              labelText: isMoMo ? 'MoMo Number' : 'Note (Optional)',
                              prefixIcon: Icon(isMoMo ? Icons.phone_iphone_rounded : Icons.note_alt_outlined),
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            keyboardType: isMoMo ? TextInputType.phone : TextInputType.text,
                          ),
                        ],
                      ),
                    ),
                    if (isBank) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isUploading ? null : _uploadBankReceipt,
                          icon: _isUploading 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(_receiptUrl != null ? Icons.check_circle : Icons.add_a_photo, color: _receiptUrl != null ? Colors.green : null),
                          label: Text(_receiptUrl != null ? 'RECEIPT ATTACHED' : 'UPLOAD DEPOSIT SLIP'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _receiptUrl != null ? Colors.green : Colors.purple,
                            side: BorderSide(color: _receiptUrl != null ? Colors.green : Colors.purple),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addPayment,
                        icon: Icon(isMoMo ? Icons.smartphone_rounded : (isBank ? Icons.account_balance : Icons.add_circle_outline), size: 18),
                        label: Text(isMoMo ? 'APPLY MOMO PAYMENT' : (isBank ? 'APPLY BANK DEPOSIT' : 'APPLY PAYMENT')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isBank ? Colors.purple : AppColors.accentGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),

                    if (_payments.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      ..._payments.map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.s),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              p.method == PaymentMethod.cash ? Icons.money : 
                              (p.method == PaymentMethod.mobileMoney ? Icons.smartphone : Icons.account_balance), 
                              size: 16, color: Colors.green
                            ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(
                                      p.method.name.toUpperCase(), 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)
                                    )),
                                    Text('₵${p.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red, size: 16), 
                              onPressed: () => setState(() => _payments.remove(p))
                            ),
                          ],
                        ),
                      )),
                    ],
                  ],
                ),
              ),
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                      ),
                      child: Text('CANCEL', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onComplete(_payments, _receiptUrl);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary, 
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                      ),
                      child: FittedBox(
                        child: Text(
                          _payments.isEmpty ? 'RECORD AS DEBT' : 'COMPLETE SALE', 
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _uploadBankReceipt() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() => _isUploading = true);
    try {
      final bytes = await image.readAsBytes();
      final url = await ref.read(expenseProvider.notifier).uploadReceipt(
        bytes, 
        'bank_${DateTime.now().millisecondsSinceEpoch}.jpg'
      );
      if (mounted) setState(() => _receiptUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _billRow(BuildContext context, String label, String value, ThemeData theme, {bool isTotal = false, Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, 
              style: TextStyle(
                fontSize: isTotal ? 13 : 12, 
                color: isTotal ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                fontWeight: (isTotal || isBold) ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(
              fontSize: isTotal ? 16 : 14, 
              fontWeight: (isTotal || isBold) ? FontWeight.bold : FontWeight.w600,
              color: color ?? theme.colorScheme.onSurface,
            )),
          ),
        ],
      ),
    );
  }
}

class ReceiptSuccessDialog extends StatefulWidget {
  final SaleRecord sale;
  final WidgetRef ref;

  const ReceiptSuccessDialog({super.key, required this.sale, required this.ref});

  @override
  State<ReceiptSuccessDialog> createState() => _ReceiptSuccessDialogState();
}

class _ReceiptSuccessDialogState extends State<ReceiptSuccessDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 400),
        height: 520, // Compact but fits details
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                  SizedBox(width: 8),
                  Text('SALE SUCCESSFUL', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.2)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Digital Receipt Card
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.m),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.s),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)],
                ),
                child: Column(
                  children: [
                    const Text('Mi CORAZON', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                    const Text('Digital Copy', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    if (widget.sale.balance > 0.01)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(4)),
                        child: const Text('DEBT / CREDIT SALE', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    const Divider(height: 24),
                    _receiptPreviewRow('Invoice ID', widget.sale.id.substring(widget.sale.id.length - 8).toUpperCase()),
                    _receiptPreviewRow('Cashier', widget.sale.cashierName.split(' ')[0]),
                    const Divider(height: 24),
                    Expanded(
                      child: ListView.builder(
                        itemCount: widget.sale.items.length,
                        itemBuilder: (context, index) {
                          final item = widget.sale.items[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.product.name, 
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('₵${item.total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text('TOTAL', 
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₵${widget.sale.totalAmount.toStringAsFixed(2)}', 
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.black)),
                        ),
                      ],
                    ),
                    if (widget.sale.balance > 0.01) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text('AMOUNT PAID', 
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('₵${widget.sale.amountPaid.toStringAsFixed(2)}', 
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text('BALANCE DUE (DEBT)', 
                              style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('₵${widget.sale.balance.toStringAsFixed(2)}', 
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.red)),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showReceiptOptionsDialog(widget.sale),
                icon: const Icon(Icons.receipt_long_rounded, size: 20),
                label: const Text('VIEW RECEIPT OPTIONS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: const Text('CLOSE WINDOW', style: TextStyle(color: AppColors.textLight, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiptOptionsDialog(SaleRecord sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receipt Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.print, color: Colors.blue),
              title: const Text('Print Physical Receipt'),
              onTap: () {
                Navigator.pop(context);
                ReceiptService.printReceipt(sale);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('Share Digital Receipt (PDF)'),
              onTap: () {
                Navigator.pop(context);
                ReceiptService.shareReceipt(sale);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sms, color: Colors.orange),
              title: const Text('Send SMS Confirmation'),
              onTap: () async {
                String? targetPhone = sale.customerPhone;
                if (targetPhone == null || targetPhone.isEmpty) {
                  targetPhone = await PhonePromptDialog.show(context);
                }

                if (targetPhone != null && targetPhone.isNotEmpty) {
                  final success = await SmsService.sendReceiptSms(sale, customPhone: targetPhone);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? 'SMS Sent' : 'SMS Failed'),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _receiptPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, 
              style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
