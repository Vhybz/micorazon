import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../widgets/main_app_bar.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/app_sidebar.dart';
import '../services/menu_service.dart';
import '../services/user_provider.dart';
import '../services/theme_provider.dart';
import '../services/offline_sync_service.dart';
import '../services/app_settings_provider.dart';
import '../widgets/role_pop_scope.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<Color> themeColors = [
    AppColors.primaryMaroon,
    Colors.black,
    Color(0xFFE91E63), // Deep Pink
    Color(0xFF2962FF), // Electric Blue
    Color(0xFF00E676), // Neon Green
    Color(0xFFFF3D00), // Vivid Orange
    Color(0xFF7C4DFF), // Electric Violet
    Color(0xFFFFD600), // Yellow Gold
    Color(0xFF00B0FF), // Bright Cyan
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const Center(child: CircularProgressIndicator());

    final themeState = ref.watch(themeProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);
    final isDesktop = ResponsiveLayout.isDesktop(context);
    const currentRoute = '/settings';

    return RolePopScope(
      currentRoute: currentRoute,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: const MainAppBar(title: 'Settings & Preferences'),
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Personalization', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text('Customize your workstation appearance and system behavior', 
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: AppSpacing.xl),
                        
                        _buildSection(
                          context,
                          'Display Mode',
                          Icons.palette_outlined,
                          [
                            _buildThemeModeSelector(ref, themeState),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.l),

                        _buildSection(
                          context,
                          'Interface Color Accent',
                          Icons.color_lens_outlined,
                          [
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.m),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Select a vibrant accent color for your workstation UI:', 
                                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: themeColors.map((color) => _buildColorDot(ref, color, themeState.primaryColor)).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.l),

                        _buildSection(
                          context,
                          'Notifications & Alerts',
                          Icons.notifications_active_outlined,
                          [
                            SwitchListTile(
                              secondary: const Icon(Icons.vibration),
                              title: const Text('Push Notifications'),
                              subtitle: const Text('Receive real-time alerts for stock transfers and system updates'),
                              value: appSettings.pushNotificationsEnabled, 
                              activeThumbColor: theme.colorScheme.primary,
                              onChanged: (v) => ref.read(appSettingsProvider.notifier).togglePushNotifications(v),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              secondary: const Icon(Icons.volume_up_outlined),
                              title: const Text('System Sounds'),
                              subtitle: const Text('Play beeps during barcode/QR scanning'),
                              value: appSettings.systemSoundsEnabled,
                              activeThumbColor: theme.colorScheme.primary,
                              onChanged: (v) => ref.read(appSettingsProvider.notifier).toggleSystemSounds(v),
                            ),
                            const Divider(height: 1),
                            SwitchListTile(
                              secondary: const Icon(Icons.touch_app_outlined),
                              title: const Text('Haptic Feedback'),
                              subtitle: const Text('Vibrate on successful scans'),
                              value: appSettings.hapticFeedbackEnabled,
                              activeThumbColor: theme.colorScheme.primary,
                              onChanged: (v) => ref.read(appSettingsProvider.notifier).toggleHapticFeedback(v),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.l),

                        _buildSection(
                          context,
                          'Security',
                          Icons.security_outlined,
                          [
                            ListTile(
                              leading: const Icon(Icons.lock_outline),
                              title: const Text('Update Password'),
                              subtitle: const Text('Keep your account secure with regular updates'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _showChangePasswordDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.l),

                        _buildSection(
                          context,
                          'Storage & Data',
                          Icons.storage_rounded,
                          [
                            ListTile(
                              leading: const Icon(Icons.delete_sweep_outlined, color: Colors.red),
                              title: const Text('Clear Local Cache', style: TextStyle(color: Colors.red)),
                              subtitle: const Text('Frees up space and forces fresh data sync'),
                              onTap: () => _showClearCacheDialog(context),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 40),
                        Center(
                          child: Text('Version 1.0.0+1 • Butchery ERP Enterprise', 
                            style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                        ),
                        const SizedBox(height: 40),
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

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Local Cache?'),
        content: const Text('This will delete all offline data stored on this device. Pending sync items may be lost. You will need to re-download fresh inventory data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              await OfflineSyncService.clearAllCache();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared. Refreshing data...'), backgroundColor: Colors.green),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('CLEAR DATA'),
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
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.m),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildThemeModeSelector(WidgetRef ref, ThemeState state) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.settings_suggest_outlined), label: Text('Auto')),
        ],
        selected: {state.mode},
        onSelectionChanged: (newSelection) {
          ref.read(themeProvider.notifier).setThemeMode(newSelection.first);
        },
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return null; // Uses primary from theme
            }
            return Colors.transparent;
          }),
        ),
      ),
    );
  }

  Widget _buildColorDot(WidgetRef ref, Color color, Color selectedColor) {
    final isSelected = color.toARGB32() == selectedColor.toARGB32();
    return InkWell(
      onTap: () => ref.read(themeProvider.notifier).setPrimaryColor(color),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, spreadRadius: 2)] : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final oldPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: oldPassword, decoration: const InputDecoration(labelText: 'Current Password'), obscureText: true),
              const SizedBox(height: 12),
              TextField(controller: newPassword, decoration: const InputDecoration(labelText: 'New Password'), obscureText: true),
              const SizedBox(height: 12),
              TextField(controller: confirmPassword, decoration: const InputDecoration(labelText: 'Confirm New Password'), obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (newPassword.text != confirmPassword.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
                return;
              }
              try {
                // For settings, it's safer to re-auth if possible, but here we update directly
                await Supabase.instance.client.auth.updateUser(
                  UserAttributes(password: newPassword.text),
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully')));
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Update Password'),
          ),
        ],
      ),
    );
  }
}
