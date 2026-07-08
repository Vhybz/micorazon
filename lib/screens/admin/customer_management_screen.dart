import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../widgets/role_pop_scope.dart';
import '../../services/customer_provider.dart';
import '../../models/customer_model.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../core/uuid_utils.dart';
import '../../models/customer_metrics.dart';
import '../../services/customer_metrics_provider.dart';

class CustomerManagementScreen extends ConsumerStatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  ConsumerState<CustomerManagementScreen> createState() => _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends ConsumerState<CustomerManagementScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final customers = ref.watch(customerProvider);
    final metrics = ref.watch(customerMetricsProvider);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/customers';

    // Filter and sort customers
    final filteredCustomers = customers.where((c) {
      final query = _searchQuery.toLowerCase();
      return c.name.toLowerCase().contains(query) || 
             c.phone.contains(query) || 
             (c.location?.toLowerCase().contains(query) ?? false);
    }).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'Customer Directory'),
        drawer: isDesktop ? null : Drawer(
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, ref),
                    const SizedBox(height: AppSpacing.m),
                    _buildSearchBar(context),
                    const SizedBox(height: AppSpacing.xl),
                    _buildMetricsSummary(context, metrics),
                    const SizedBox(height: AppSpacing.xl),
                    _buildCustomerGrid(context, ref, filteredCustomers),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 600),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search by Name (e.g. John), Phone (e.g. 020) or Location...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty 
            ? IconButton(
                icon: const Icon(Icons.clear), 
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                }
              ) 
            : null,
          filled: true,
          fillColor: theme.cardTheme.color,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.m),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsSummary(BuildContext context, Map<String, CustomerMetric> metrics) {
    final theme = Theme.of(context);
    final vips = metrics.values.where((m) => m.performanceLabel == 'VIP').length;
    final regulars = metrics.values.where((m) => m.performanceLabel == 'Regular').length;
    
    return Row(
      children: [
        _buildSummaryCard('Total Customers', metrics.length.toString(), Icons.people, Colors.blue, theme),
        const SizedBox(width: AppSpacing.m),
        _buildSummaryCard('VIP Customers', vips.toString(), Icons.stars, Colors.purple, theme),
        const SizedBox(width: AppSpacing.m),
        _buildSummaryCard('Regulars', regulars.toString(), Icons.repeat, Colors.green, theme),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, ThemeData theme) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.m),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(title, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    
    return Flex(
      direction: isMobile ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: isMobile ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage Regulars', style: TextStyle(fontSize: isMobile ? 20 : 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            Text('Maintain a directory of favorite and wholesale customers', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
        if (isMobile) const SizedBox(height: AppSpacing.m),
        ElevatedButton.icon(
          onPressed: () => _showAddCustomerDialog(context, ref),
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Add Customer', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerGrid(BuildContext context, WidgetRef ref, List<Customer> customers) {
    final theme = Theme.of(context);
    final metrics = ref.watch(customerMetricsProvider);
    
    if (customers.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(_searchQuery.isEmpty ? 'No customers in directory yet.' : 'No customers match your search.', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))));
    }

    return LayoutBuilder(builder: (context, constraints) {
      final crossAxisCount = constraints.maxWidth > 1200 ? 4 : (constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 500 ? 2 : 1));
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: customers.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: AppSpacing.m,
          mainAxisSpacing: AppSpacing.m,
          childAspectRatio: 1.5,
        ),
        itemBuilder: (context, index) {
          final c = customers[index];
          final m = metrics[c.phone];
          
          return Card(
            elevation: c.isFavorite ? 4 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.m),
              side: c.isFavorite ? BorderSide(color: Colors.orange.withValues(alpha: 0.5), width: 1) : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                        child: Icon(
                          c.isFavorite ? Icons.star : Icons.person, 
                          color: c.isFavorite ? Colors.orange : theme.colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name, 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (m != null)
                              Text(
                                m.performanceLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: m.performanceLabel == 'VIP' ? Colors.purple : (m.performanceLabel == 'Regular' ? Colors.blue : Colors.grey),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (val) {
                          if (val == 'fav') {
                            ref.read(customerProvider.notifier).toggleFavorite(c.id);
                          } else if (val == 'edit') {
                            _showEditCustomerDialog(context, ref, c);
                          } else if (val == 'del') {
                            _confirmDeleteCustomer(context, ref, c);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(value: 'fav', child: Text(c.isFavorite ? 'Remove Favorite' : 'Mark as Favorite')),
                          const PopupMenuItem(value: 'edit', child: Text('Edit Details')),
                          const PopupMenuItem(value: 'del', child: Text('Delete Record', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildMetricRow(Icons.phone_outlined, c.phone, theme),
                              const SizedBox(height: 4),
                              _buildMetricRow(Icons.shopping_bag_outlined, 'Orders: ${m?.visitCount ?? 0}', theme),
                              const SizedBox(height: 4),
                              _buildMetricRow(Icons.payments_outlined, 'Spent: GHC${m?.totalSpend.toStringAsFixed(2) ?? '0.00'}', theme),
                              const SizedBox(height: 4),
                              _buildMetricRow(Icons.money_off_outlined, 'Debt: GHC${m?.totalDebt.toStringAsFixed(2) ?? '0.00'}', theme, color: (m?.totalDebt ?? 0) > 0.01 ? Colors.red : null),
                            ],
                          ),
                        ),
                        if (m != null && m.recentSpends.length > 1)
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 40,
                              child: _CustomerTrendGraph(spends: m.recentSpends),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 12, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          c.location ?? 'No location', 
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _buildMetricRow(IconData icon, String text, ThemeData theme, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color ?? theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text, 
            style: TextStyle(fontSize: 11, color: color ?? theme.colorScheme.onSurfaceVariant, fontWeight: color != null ? FontWeight.bold : FontWeight.normal),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _confirmDeleteCustomer(BuildContext context, WidgetRef ref, Customer customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text('Are you sure you want to remove ${customer.name} from the directory? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(customerProvider.notifier).deleteCustomer(customer.id);
              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${customer.name} deleted successfully.'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditCustomerDialog(BuildContext context, WidgetRef ref, Customer customer) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: customer.name);
    final phoneController = TextEditingController(text: customer.phone);
    final locationController = TextEditingController(text: customer.location ?? '');
    bool isFavorite = customer.isFavorite;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: Text('Edit Customer: ${customer.name}'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController, 
                    decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))],
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController, 
                    decoration: const InputDecoration(labelText: 'Phone Number', hintText: '10 digits', prefixIcon: Icon(Icons.phone_outlined)), 
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length != 10) return 'Exactly 10 digits required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController, 
                    decoration: const InputDecoration(labelText: 'Location / Address', prefixIcon: Icon(Icons.location_on_outlined)),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Mark as Favorite'),
                    subtitle: const Text('Highlighted in directory'),
                    value: isFavorite,
                    onChanged: (val) => setState(() => isFavorite = val ?? false),
                    activeColor: theme.colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final updatedCustomer = customer.copyWith(
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    location: locationController.text.trim().isEmpty ? null : locationController.text.trim(),
                    isFavorite: isFavorite,
                  );
                  
                  try {
                    await ref.read(customerProvider.notifier).updateCustomer(updatedCustomer);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Customer details updated!'), backgroundColor: Colors.green),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating customer: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCustomerDialog(BuildContext context, WidgetRef ref) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final locationController = TextEditingController();
    bool isFavorite = false;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: const Text('Add Regular Customer'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController, 
                    decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline)),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s]'))],
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController, 
                    decoration: const InputDecoration(labelText: 'Phone Number', hintText: '10 digits', prefixIcon: Icon(Icons.phone_outlined)), 
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length != 10) return 'Exactly 10 digits required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: locationController, 
                    decoration: const InputDecoration(labelText: 'Location / Address', prefixIcon: Icon(Icons.location_on_outlined)),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Mark as Favorite'),
                    subtitle: const Text('Highlighted in directory'),
                    value: isFavorite,
                    onChanged: (val) => setState(() => isFavorite = val ?? false),
                    activeColor: theme.colorScheme.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  final String uniqueUuid = UuidUtils.generate();

                  final newCustomer = Customer(
                    id: uniqueUuid,
                    name: nameController.text.trim(),
                    phone: phoneController.text.trim(),
                    location: locationController.text.trim().isEmpty ? null : locationController.text.trim(),
                    isFavorite: isFavorite,
                  );
                  
                  try {
                    // Show loading
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(child: CircularProgressIndicator()),
                    );

                    await ref.read(customerProvider.notifier).addCustomer(newCustomer);
                    
                    if (context.mounted) {
                      Navigator.pop(context); // Pop loading
                      Navigator.pop(context); // Pop dialog
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Customer saved and welcome SMS sent!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context); // Pop loading
                      String errorMessage = 'Failed to save customer';
                      final String errorStr = e.toString().toLowerCase();
                      
                      if (errorStr.contains('unique') || errorStr.contains('already exists')) {
                        errorMessage = 'A customer with phone ${phoneController.text} already exists.';
                      } else {
                        errorMessage = 'Error: $e'; // Show the actual error
                      }
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(errorMessage, style: const TextStyle(fontSize: 12)), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
                      );
                      debugPrint('CUSTOMER SAVE ERROR: $e');
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white),
              child: const Text('Save Customer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerTrendGraph extends StatelessWidget {
  final List<double> spends;

  const _CustomerTrendGraph({required this.spends});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: spends.length.toDouble() - 1,
        minY: spends.reduce((a, b) => a < b ? a : b) * 0.8,
        maxY: spends.reduce((a, b) => a > b ? a : b) * 1.2,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              spends.length,
              (index) => FlSpot(index.toDouble(), spends[index]),
            ),
            isCurved: true,
            color: theme.colorScheme.primary,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
