import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'transfer_provider.dart';
import 'customer_provider.dart';
import 'expense_provider.dart';
import 'user_provider.dart';
import 'product_service.dart';
import 'sale_provider.dart';
import 'notification_service.dart';
import 'offline_sync_service.dart';

class SyncNotifier extends StateNotifier<DateTime> with WidgetsBindingObserver {
  final Ref ref;
  Timer? _timer;
  bool _isSyncing = false;

  SyncNotifier(this.ref) : super(DateTime.now()) {
    WidgetsBinding.instance.addObserver(this);
    _startSyncTimer();
    // Initial sync on startup
    _syncAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('Sync Monitor: App Resumed. Forcing immediate cloud sync...');
      _syncAll();
    }
  }

  void _startSyncTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _syncAll();
    });
  }

  Future<void> _syncAll() async {
    if (!mounted || _isSyncing) return;

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return;

      _isSyncing = true;
      
      // 1. Process offline queue first
      await OfflineSyncService.processQueue();
      
      // 2. Refresh key data sets to ensure cache is hot and Supabase is source of truth
      // Note: Realtime streams also handle this, but manual refresh ensures Req 3 is met.
      await Future.wait([
        _safeRefresh(productsFutureProvider.notifier, (n) => n.loadProducts()),
        _safeRefresh(transferProvider.notifier, (n) => n.loadTransfers()),
        _safeRefresh(customerProvider.notifier, (n) => n.loadCustomers()),
        _safeRefresh(saleHistoryProvider.notifier, (n) => n.loadSales()),
        _safeRefresh(expenseProvider.notifier, (n) => n.loadExpenses()),
        _safeRefresh(notificationProvider.notifier, (n) => n.loadNotifications()),
      ]);

      if (mounted) {
        state = DateTime.now(); 
      }
    } catch (e) {
      debugPrint('Sync Heartbeat Warning: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _safeRefresh<T>(ProviderListenable<T> provider, Future<void> Function(T) action) async {
    try {
      final notifier = ref.read(provider);
      await action(notifier);
    } catch (e) {
      // Silently ignore if provider is disposed or not found
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, DateTime>((ref) {
  return SyncNotifier(ref);
});
