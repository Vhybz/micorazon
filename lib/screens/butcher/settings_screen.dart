import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../services/theme_provider.dart';
import '../../services/offline_sync_service.dart';
import '../../services/app_settings_provider.dart';

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
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final appSettings = ref.watch(appSettingsProvider);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workstation Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const Text('Configure hardware and visual behavior for this terminal', style: TextStyle(color: AppColors.textLight)),
          const SizedBox(height: AppSpacing.xl),

          _buildSettingsSection(
            context,
            'Display & Theme',
            [
              const ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text('Appearance Mode'),
                subtitle: Text('Switch between Light and Dark themes'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              const Divider(height: 32),
              const ListTile(
                leading: Icon(Icons.color_lens_outlined),
                title: Text('Interface Color Accent'),
                subtitle: Text('Select a vibrant workspace color'),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: themeColors.map((color) => _buildColorDot(ref, color, themeState.primaryColor)).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),

          _buildSettingsSection(
            context,
            'Hardware Configuration',
            [
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: const Text('Label Printer'),
                subtitle: const Text('Zebra ZD421 - Connected'),
                trailing: TextButton(onPressed: () {}, child: const Text('Configure')),
              ),
              ListTile(
                leading: const Icon(Icons.scale_outlined),
                title: const Text('Digital Scale'),
                subtitle: const Text('Toledo 8450 - Calibrated'),
                trailing: TextButton(onPressed: () {}, child: const Text('Recalibrate')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          _buildSettingsSection(
            context,
            'Notifications & Feedback',
            [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: const Text('Real-time Alerts'),
                subtitle: const Text('System and transfer notifications'),
                value: appSettings.pushNotificationsEnabled,
                onChanged: (v) => ref.read(appSettingsProvider.notifier).togglePushNotifications(v),
                activeThumbColor: theme.colorScheme.primary,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('Audio Feedback'),
                subtitle: const Text('Sound on successful scan/weight'),
                value: appSettings.systemSoundsEnabled,
                onChanged: (v) => ref.read(appSettingsProvider.notifier).toggleSystemSounds(v),
                activeThumbColor: theme.colorScheme.primary,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_outlined),
                title: const Text('Haptic Feedback'),
                subtitle: const Text('Vibrate on barcode recognition'),
                value: appSettings.hapticFeedbackEnabled,
                onChanged: (v) => ref.read(appSettingsProvider.notifier).toggleHapticFeedback(v),
                activeThumbColor: theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          _buildSettingsSection(
            context,
            'Storage & System',
            [
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined, color: Colors.red),
                title: const Text('Clear Local Cache', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Fixes display errors by forcing a full data re-sync'),
                onTap: () => _showClearCacheDialog(context),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Terminal Information'),
                subtitle: Text('ID: TERMINAL-MC-01 • v1.0.0'),
              ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Terminal Cache?'),
        content: const Text('This will delete all offline data on this workstation. You will need an active connection to reload.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              await OfflineSyncService.clearAllCache();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cache cleared. Data will refresh on next sync.'), backgroundColor: Colors.green),
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

  Widget _buildColorDot(WidgetRef ref, Color color, Color selectedColor) {
    final isSelected = color.toARGB32() == selectedColor.toARGB32();
    return InkWell(
      onTap: () => ref.read(themeProvider.notifier).setPrimaryColor(color),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context, String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 16, 
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.m),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}
