import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/butcher_models.dart';

enum ButcherScreen {
  dashboard,
  animalIntake,
  slaughterLog,
  meatProcessing,
  stockTransfer,
  inventory,
  orders,
  wasteManagement,
  documents,
  reports,
  expenses,
  settings,
  profile,
  howToUse,
  carcassBreakdown,
  batchManagement
}

class ButcherNavigationNotifier extends StateNotifier<ButcherScreen> {
  ButcherNavigationNotifier() : super(ButcherScreen.dashboard);

  void setScreen(ButcherScreen screen) => state = screen;
}

final butcherNavProvider = StateNotifierProvider<ButcherNavigationNotifier, ButcherScreen>((ref) {
  return ButcherNavigationNotifier();
});

// Provider to hold the active log being broken down
final activeSlaughterLogProvider = StateProvider<SlaughterLog?>((ref) => null);
