import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_settings_provider.dart';

class FeedbackService {
  static Future<void> success(WidgetRef ref) async {
    final settings = ref.read(appSettingsProvider);
    
    if (settings.hapticFeedbackEnabled) {
      await HapticFeedback.mediumImpact();
    }
    
    if (settings.systemSoundsEnabled) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  static Future<void> scan(WidgetRef ref) async {
    final settings = ref.read(appSettingsProvider);
    
    if (settings.hapticFeedbackEnabled) {
      await HapticFeedback.lightImpact();
    }
    
    if (settings.systemSoundsEnabled) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}
