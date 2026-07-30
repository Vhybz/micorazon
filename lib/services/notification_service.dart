import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/uuid_utils.dart';
import 'push_notification_service.dart';
import 'sms_service.dart';
import 'offline_sync_service.dart';
import 'supabase_notification_service.dart';
import 'transfer_provider.dart';
import 'product_service.dart';
import '../models/system_models.dart';
import '../models/user_model.dart';
import 'user_provider.dart';

class NotificationNotifier extends StateNotifier<List<SystemNotification>> {
  final Ref ref;
  final SupabaseNotificationService _service = SupabaseNotificationService();
  StreamSubscription? _subscription;

  NotificationNotifier(this.ref) : super([]) {
    _init();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.id != previous?.id || next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user != null) {
      final bool isSuperAdmin = user.activePrimaryRole == UserRole.superAdmin;
      final String? userBranch = user.branchCode?.trim();
      
      _subscription = _service.watchNotifications(userBranch, user.id, isSuperAdmin: isSuperAdmin).listen(
        (notifications) {
          debugPrint('Notification Engine: Stream update. Total alerts: ${notifications.length}');

          // Determine which notifications are "new" to this device session
          final List<SystemNotification> newItems = state.isEmpty 
              ? notifications.take(3).toList() // On first load, check the last few
              : notifications.where((n) => !state.any((old) => old.id == n.id)).toList();

          for (final n in newItems) {
            final title = n.title.toUpperCase();
            final msg = n.message.toUpperCase();
            
            // Determine if we should trigger a background sync for stock
            final bool isStockAlert = title.contains('TRANSFER') || 
                                      title.contains('DISPATCH') || 
                                      title.contains('STOCK') ||
                                      title.contains('VERIFICATION') ||
                                      title.contains('INCOMING') ||
                                      msg.contains('DISPATCHED') ||
                                      msg.contains('ON THE WAY') ||
                                      msg.contains('TRANSFER');

            if (isStockAlert) {
              debugPrint('Notification Engine: Stock event detected. Refreshing...');
              Future.delayed(const Duration(milliseconds: 500), () {
                try {
                  ref.read(transferProvider.notifier).loadTransfers();
                  ref.read(productsFutureProvider.notifier).loadProducts();
                } catch (e) {
                  debugPrint('Notification Sync Error: $e');
                }
              });
            }
            
            // Show push notification popup if recent AND unread
            if (!n.isRead && DateTime.now().difference(n.createdAt).inMinutes < 10) {
              PushNotificationService.showNotification(
                  id: n.createdAt.millisecondsSinceEpoch ~/ 1000,
                  title: n.title,
                  body: n.message,
              );
            }
          }
          state = notifications;
        },
        onError: (e) {
          debugPrint('Notification Stream Connection Error (Resuming?): $e');
        },
        cancelOnError: false,
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void addNotification(String title, String message, {String type = 'info', String? targetBranchCode, bool isGlobal = false}) async {
    final user = ref.read(currentUserProvider);
    
    final notification = SystemNotification(
      id: UuidUtils.generate(),
      branchCode: isGlobal ? null : (targetBranchCode ?? user?.branchCode),
      userId: (isGlobal || targetBranchCode != null) ? null : user?.id,
      title: title,
      message: message,
      type: type,
      createdAt: DateTime.now(),
    );
    
    state = [notification, ...state];

    // 1. Persist to Offline Queue
    await OfflineSyncService.addToQueue(
      actionType: 'NOTIFICATION', 
      data: notification.toJson(),
    );

    // 2. Show System Tray "Popup" Notification
    PushNotificationService.showNotification(
      id: notification.createdAt.millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: message,
    );

    // 3. If it's a critical alert, send SMS to Admin (Works even if app is closed/offline)
    final criticalKeywords = ['BUTCHER', 'RECTIFIED', 'URGENT', 'LOW STOCK', 'CORRECTION'];
    bool isCritical = criticalKeywords.any((k) => title.toUpperCase().contains(k));

    if (isCritical) {
      SmsService.notifyAdmin(
        title: title,
        message: message,
      );
    }
  }

  void markAsRead(String id) async {
    await _service.markAsRead(id);
  }

  Future<void> loadNotifications() async {
    _startSubscription();
  }

  void markAllAsRead() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    
    final bool isSuperAdmin = user.activePrimaryRole == UserRole.superAdmin;
    await _service.markAllAsRead(user.id, user.branchCode, isSuperAdmin: isSuperAdmin);
  }

  void deleteNotification(String id) {
    state = state.where((n) => n.id != id).toList();
  }
}

final notificationProvider = StateNotifierProvider<NotificationNotifier, List<SystemNotification>>((ref) {
  return NotificationNotifier(ref);
});
