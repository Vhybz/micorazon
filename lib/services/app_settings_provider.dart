import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'offline_sync_service.dart';

class AppSettings {
  final bool pushNotificationsEnabled;
  final bool systemSoundsEnabled;
  final bool hapticFeedbackEnabled;

  AppSettings({
    this.pushNotificationsEnabled = true,
    this.systemSoundsEnabled = true,
    this.hapticFeedbackEnabled = true,
  });

  AppSettings copyWith({
    bool? pushNotificationsEnabled,
    bool? systemSoundsEnabled,
    bool? hapticFeedbackEnabled,
  }) {
    return AppSettings(
      pushNotificationsEnabled: pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      systemSoundsEnabled: systemSoundsEnabled ?? this.systemSoundsEnabled,
      hapticFeedbackEnabled: hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(AppSettings()) {
    _init();
  }

  void _init() {
    final box = Hive.box(OfflineSyncService.settingsBoxName);
    state = AppSettings(
      pushNotificationsEnabled: box.get('push_notifications', defaultValue: true),
      systemSoundsEnabled: box.get('system_sounds', defaultValue: true),
      hapticFeedbackEnabled: box.get('haptic_feedback', defaultValue: true),
    );
  }

  void togglePushNotifications(bool value) {
    state = state.copyWith(pushNotificationsEnabled: value);
    _save('push_notifications', value);
  }

  void toggleSystemSounds(bool value) {
    state = state.copyWith(systemSoundsEnabled: value);
    _save('system_sounds', value);
  }

  void toggleHapticFeedback(bool value) {
    state = state.copyWith(hapticFeedbackEnabled: value);
    _save('haptic_feedback', value);
  }

  void _save(String key, bool value) {
    final box = Hive.box(OfflineSyncService.settingsBoxName);
    box.put(key, value);
  }
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});
