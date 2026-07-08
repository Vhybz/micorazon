import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../services/butcher_service.dart';
import '../../services/product_service.dart';
import '../../models/butcher_models.dart';
import '../../models/product.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cutsAsync = ref.watch(recentCutsProvider);
    final productsAsync = ref.watch(productsFutureProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isMobile = constraints.maxWidth < 600;
              return Flex(
                direction: isMobile ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Inventory Control', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                      Text('Monitoring stock from slaughter to retail', style: TextStyle(color: AppColors.textLight)),
                    ],
                  ),
                  if (isMobile) const SizedBox(height: AppSpacing.m),
                  Container(
                    width: isMobile ? double.infinity : 300,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(AppRadius.m),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.primaryMaroon,
                        borderRadius: BorderRadius.circular(AppRadius.m),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppColors.textLight,
                      tabs: const [
                        Tab(text: 'Slaughterhouse'),
                        Tab(text: 'Retail Store'),
                      ],
                    ),
                  ),
                ],
              );
            }
          ),
          const SizedBox(height: AppSpacing.l),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCutsView(cutsAsync),
                _buildRetailView(productsAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCutsView(AsyncValue<List<MeatCut>> cutsAsync) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 1000 ? 3 : 4);
        return Column(
          children: [
            _buildInventoryStats(cutsAsync.value ?? []),
            const SizedBox(height: AppSpacing.m),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search internal stock...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: AppSpacing.l),
            Expanded(
              child: cutsAsync.when(
                data: (cuts) {
                  final filtered = cuts.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
                  if (filtered.isEmpty) return const Center(child: Text('No matching internal inventory records.'));
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.m,
                      mainAxisSpacing: AppSpacing.m,
                      childAspectRatio: constraints.maxWidth < 600 ? 0.9 : 1.1,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) => _buildInventoryCard(filtered[index]),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildInventoryStats(List<MeatCut> cuts) {
    final totalWeight = cuts.fold(0.0, (sum, c) => sum + c.weight);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.primaryMaroon.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppRadius.m),
        border: Border.all(color: AppColors.primaryMaroon.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: AppColors.primaryMaroon, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${totalWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Text('Total Internal Net Weight', style: TextStyle(fontSize: 10, color: AppColors.textLight)),
            ],
          ),
          const Spacer(),
          Text('${cuts.length} Items', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryMaroon)),
        ],
      ),
    );
  }

  Widget _buildRetailView(AsyncValue<List<Product>> productsAsync) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int crossAxisCount = constraints.maxWidth < 600 ? 2 : (constraints.maxWidth < 1000 ? 3 : 4);
        return Column(
          children: [
            _buildStockAlerts('Monitoring Retail: Real-time stock levels available at the POS terminal.'),
            const SizedBox(height: AppSpacing.m),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search retail stock...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: AppSpacing.l),
            Expanded(
              child: productsAsync.when(
                data: (products) {
                  final activeProducts = products.where((p) => 
                    !p.isDeleted && p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
                  if (activeProducts.isEmpty) return const Center(child: Text('No matching retail products found.'));
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: AppSpacing.m,
                      mainAxisSpacing: AppSpacing.m,
                      childAspectRatio: constraints.maxWidth < 600 ? 0.9 : 1.1,
                    ),
                    itemCount: activeProducts.length,
                    itemBuilder: (context, index) => _buildProductInventoryCard(activeProducts[index]),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildStockAlerts(String message) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(AppRadius.m),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.orange, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                    children: [
                      const TextSpan(text: 'Monitor: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      TextSpan(text: message),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildInventoryCard(MeatCut cut) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.inventory_2_outlined, color: AppColors.primaryMaroon, size: 18),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('INTERNAL', style: TextStyle(color: Colors.green, fontSize: 7, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(cut.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('ID: ${cut.batchId.substring(0, 8).toUpperCase()}', style: const TextStyle(color: AppColors.textLight, fontSize: 9), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Weight/Qty', style: TextStyle(fontSize: 8, color: AppColors.textLight)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${cut.weight.toStringAsFixed(cut.unit == 'Qty' ? 0 : 1)} ${cut.unit}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.history, size: 16), 
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {}
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductInventoryCard(Product product) {
    final bool isLow = product.stockQuantity <= product.lowStockThreshold;
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.m),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.storefront_outlined, color: Colors.blue, size: 18),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isLow ? Colors.red : Colors.blue).withValues(alpha: 0.1), 
                      borderRadius: BorderRadius.circular(4)
                    ),
                    child: Text(isLow ? 'LOW' : 'RETAIL', 
                      style: TextStyle(color: isLow ? Colors.red : Colors.blue, fontSize: 7, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(product.category, style: const TextStyle(color: AppColors.textLight, fontSize: 9), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Stock', style: TextStyle(fontSize: 8, color: AppColors.textLight)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('${product.stockQuantity.toStringAsFixed(1)} ${product.unit}', 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isLow ? Colors.red : AppColors.textDark)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.trending_up, size: 16, color: AppColors.accentGreen),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
