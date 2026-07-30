import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import 'user_provider.dart';
import 'customer_provider.dart';
import 'sale_provider.dart';
import 'product_service.dart';
import 'expense_provider.dart';
import 'branch_provider.dart';
import 'transfer_provider.dart';
import 'butcher_service.dart';
import 'notification_service.dart';
import 'cart_provider.dart';
import 'audit_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

class GlobalLogout {
  /// Primary logout method for UI components (Screens/Widgets)
  static Future<void> perform(WidgetRef ref) async {
    try {
      // 0. Log Audit Event before clearing session
      await AuditService.log(
        ref: ref,
        action: 'USER_SIGNED_OUT',
        entityType: 'USER',
      );

      // 1. Sign out from Supabase
      await ref.read(authServiceProvider).signOut();

      // 2. Clear all local session providers
      ref.read(currentUserIdProvider.notifier).state = null;
      ref.read(sessionUserProfileProvider.notifier).state = null;
      
      // 3. Invalidate/Reset all state providers to clear cache
      _invalidateAll(ref);
      
      debugPrint('Global Logout: All providers invalidated and signed out.');
    } catch (e) {
      debugPrint('Logout Error: $e');
    }
  }

  /// Use this version inside other Providers or Notifiers where you have Ref
  static Future<void> performFromProvider(Ref ref) async {
    try {
      // 0. Log Audit Event before clearing session
      await AuditService.log(
        ref: ref,
        action: 'USER_SIGNED_OUT',
        entityType: 'USER',
      );

      await ref.read(authServiceProvider).signOut();

      ref.read(currentUserIdProvider.notifier).state = null;
      ref.read(sessionUserProfileProvider.notifier).state = null;
      
      _invalidateAll(ref);
      
      debugPrint('Global Logout (Provider): All providers invalidated.');
    } catch (e) {
      debugPrint('Logout Error: $e');
    }
  }

  static void _invalidateAll(dynamic ref) {
    ref.invalidate(userProvider);
    ref.invalidate(customerProvider);
    ref.invalidate(saleHistoryProvider);
    ref.invalidate(productsFutureProvider);
    ref.invalidate(expenseProvider);
    ref.invalidate(branchesProvider);
    ref.invalidate(transferProvider);
    ref.invalidate(slaughterLogsProvider);
    ref.invalidate(activeBatchesProvider);
    ref.invalidate(recentCutsProvider);
    ref.invalidate(butcherWasteProvider);
    ref.invalidate(notificationProvider);
    ref.invalidate(cartProvider);
  }
}
