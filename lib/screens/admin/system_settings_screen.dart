import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/app_sidebar.dart';
import '../../services/menu_service.dart';
import '../../services/user_provider.dart';
import '../../models/user_model.dart';
import '../../services/theme_provider.dart';
import '../../services/branch_provider.dart';
import '../../services/product_seeder.dart';
import '../../widgets/role_pop_scope.dart';

class SystemSettingsScreen extends ConsumerStatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  ConsumerState<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends ConsumerState<SystemSettingsScreen> {
  bool _isSeeding = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/admin/settings';
    final currentBranch = ref.watch(currentBranchProvider);

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'System Settings', showMenuButton: true),
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.l),
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeroHeader(theme),
                        const SizedBox(height: AppSpacing.xl),
                        _buildSection(
                          context,
                          'Branding & Theme',
                          Icons.palette_rounded,
                          [
                            _buildThemeColorSelector(context),
                            _buildThemeModeToggle(context),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _buildSection(
                          context,
                          'Personal Profile',
                          Icons.person_outline_rounded,
                          [
                            _buildProfileSection(context, user, theme),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _buildSection(
                          context,
                          'Shop Identification',
                          Icons.business_rounded,
                          [
                            _settingTile(context, Icons.store_rounded, 'Branch Name', currentBranch?.name ?? 'Mi~CORAZON FRESHMEAT BUTCHERY'),
                            _settingTile(context, Icons.location_on_rounded, 'Branch Location', currentBranch?.location ?? 'HQ'),
                            _settingTile(context, Icons.gps_fixed_rounded, 'Digital Address (GPS)', 'BS-0006-1566'),
                            _settingTile(context, Icons.phone_android_rounded, 'Emergency Contacts', '0209276200 / 0243672146'),
                          ],
                        ),
                        _buildSection(
                          context,
                          'Configuration & Defaults',
                          Icons.settings_suggest_rounded,
                          [
                            _settingTile(context, Icons.currency_exchange_rounded, 'System Currency', 'Ghana Cedi (GHS)'),
                            _settingTile(context, Icons.percent_rounded, 'VAT/Tax Rate', '15.0%'),
                            _settingTile(context, Icons.auto_awesome_rounded, 'Brand Slogan', 'Uncompromising Quality, Unforgettable Taste'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _buildSection(
                          context,
                          'Maintenance & Data',
                          Icons.storage_rounded,
                          [
                            _buildSeedingTile(context, theme),
                            _settingTile(context, Icons.cloud_done_rounded, 'Cloud Sync Status', 'Live & Secure', color: Colors.green),
                            _settingTile(context, Icons.history_edu_rounded, 'System Logs', 'View administrative audit trail'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _buildFooter(theme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.l),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.settings_applications_rounded, color: Colors.white, size: 40),
          const SizedBox(height: 16),
          const Text(
            'System Control Center',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          Text(
            'Configure global parameters, branding, and theme for Mi~Corazon.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, IconData icon, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: theme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.l),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _settingTile(BuildContext context, IconData icon, String label, String value, {Color? color}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (color ?? theme.colorScheme.primary).withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color ?? theme.colorScheme.primary, size: 22),
      ),
      title: Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
      subtitle: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: theme.dividerColor),
      onTap: () {
        // Future: Show individual edit dialogs
      },
    );
  }

  Widget _buildSeedingTile(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.inventory_2_rounded, color: theme.colorScheme.secondary, size: 22),
      ),
      title: const Text('Initial Product Catalog', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: const Text('Populate database with default product categories', style: TextStyle(fontSize: 12)),
      trailing: _isSeeding 
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('RUN SEEDER', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
      onTap: _isSeeding ? null : () async {
        setState(() => _isSeeding = true);
        try {
          await ref.read(productSeederProvider).seedProducts();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Product catalog populated successfully!'), backgroundColor: Colors.green),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        } finally {
          if (mounted) setState(() => _isSeeding = false);
        }
      },
    );
  }

  Widget _buildThemeColorSelector(BuildContext context) {
    final theme = Theme.of(context);
    final themeState = ref.watch(themeProvider);
    
    final List<Color> themeColors = [
      AppColors.primaryMaroon,
      AppColors.primaryPink,
      AppColors.primaryBlue,
      AppColors.primaryGreen,
      Colors.teal.shade700,
      Colors.indigo.shade700,
      Colors.deepPurple.shade700,
      Colors.brown.shade700,
      Colors.black87,
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.color_lens_rounded, color: theme.colorScheme.primary, size: 22),
      ),
      title: const Text('Primary Theme Color', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: themeColors.map((color) {
            final isSelected = themeState.primaryColor == color;
            return InkWell(
              onTap: () => ref.read(themeProvider.notifier).setPrimaryColor(color),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected 
                    ? Border.all(color: theme.colorScheme.onSurface, width: 2)
                    : Border.all(color: Colors.white24, width: 1),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 1)
                  ],
                ),
                child: isSelected 
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildThemeModeToggle(BuildContext context) {
    final theme = Theme.of(context);
    final themeState = ref.watch(themeProvider);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          themeState.mode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, 
          color: theme.colorScheme.primary, 
          size: 22
        ),
      ),
      title: const Text('Display Mode', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
            ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_outlined), label: Text('Auto')),
          ],
          selected: {themeState.mode},
          onSelectionChanged: (newSelection) {
            ref.read(themeProvider.notifier).setThemeMode(newSelection.first);
          },
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context, UserAccount user, ThemeData theme) {
    return ListTile(
      contentPadding: const EdgeInsets.all(AppSpacing.l),
      leading: CircleAvatar(
        radius: 30,
        backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
        child: user.photoUrl == null ? const Icon(Icons.person, size: 30) : null,
      ),
      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user.email, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(user.role.name.toUpperCase(), 
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
          ),
        ],
      ),
      trailing: OutlinedButton(
        onPressed: () => Navigator.pushNamed(context, '/profile'),
        child: const Text('EDIT'),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.verified_user_rounded, color: theme.colorScheme.primary.withValues(alpha: 0.5), size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            'Mi~Corazon Freshmeat Butchery Management',
            style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          Text(
            'Version 1.0.0 (Build +1) • Enterprise Edition',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
