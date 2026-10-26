import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'transfer_provider.dart';
import 'customer_provider.dart';
import 'expense_provider.dart';
import 'user_provider.dart';
import 'product_service.dart';
import 'sale_provider.dart';
import 'notification_service.dart';
import 'offline_sync_service.dart';

class CloudSyncState {
  final DateTime lastSynced;
  final bool isSyncing;
  final bool isConnected;
  final int pendingCount;

  const CloudSyncState({
    required this.lastSynced,
    this.isSyncing = false,
    this.isConnected = true,
    this.pendingCount = 0,
  });

  CloudSyncState copyWith({
    DateTime? lastSynced,
    bool? isSyncing,
    bool? isConnected,
    int? pendingCount,
  }) {
    return CloudSyncState(
      lastSynced: lastSynced ?? this.lastSynced,
      isSyncing: isSyncing ?? this.isSyncing,
      isConnected: isConnected ?? this.isConnected,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

class SyncNotifier extends StateNotifier<CloudSyncState> with WidgetsBindingObserver {
  final Ref ref;
  Timer? _timer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  SyncNotifier(this.ref) : super(CloudSyncState(lastSynced: DateTime.now())) {
    WidgetsBinding.instance.addObserver(this);
    _listenConnectivity();
    _startSyncTimer();
    // Initial sync on startup
    syncAll();
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOffline = results.every((result) => result == ConnectivityResult.none);
      if (mounted) {
        state = state.copyWith(isConnected: !isOffline);
        if (!isOffline) {
          syncAll();
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('Sync Monitor: App Resumed. Processing queue & syncing...');
      _startSyncTimer();
      syncAll();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint('Sync Monitor: App Paused. Pausing sync timer to save API logs...');
      _timer?.cancel();
    }
  }

  void _startSyncTimer() {
    _timer?.cancel();
    // Run background sync check every 5 minutes instead of 30 seconds to prevent API log bloat
    _timer = Timer.periodic(const Duration(minutes: 5), (timer) {
      syncAll();
    });
  }

  Future<void> syncAll({bool forceRefreshAll = false}) async {
    if (!mounted || state.isSyncing) return;

    try {
      final results = await Connectivity().checkConnectivity();
      final isOffline = results.every((result) => result == ConnectivityResult.none);
      if (isOffline) {
        if (mounted) {
          state = state.copyWith(
            isConnected: false,
            isSyncing: false,
            pendingCount: OfflineSyncService.getPendingCount(),
          );
        }
        return;
      }

      final user = ref.read(currentUserProvider);
      if (user == null) {
        if (mounted) {
          state = state.copyWith(isConnected: true, isSyncing: false);
        }
        return;
      }

      if (mounted) {
        state = state.copyWith(isSyncing: true, isConnected: true);
      }
      
      // 1. Process offline queue first
      await OfflineSyncService.processQueue();
      
      // 2. Only perform full REST re-fetch if forced or if there were pending offline items
      if (forceRefreshAll || OfflineSyncService.getPendingCount() > 0) {
        await Future.wait([
          _safeRefresh(productsFutureProvider.notifier, (n) => n.loadProducts()),
          _safeRefresh(transferProvider.notifier, (n) => n.loadTransfers()),
          _safeRefresh(customerProvider.notifier, (n) => n.loadCustomers()),
          _safeRefresh(saleHistoryProvider.notifier, (n) => n.loadSales()),
          _safeRefresh(expenseProvider.notifier, (n) => n.loadExpenses()),
          _safeRefresh(notificationProvider.notifier, (n) => n.loadNotifications()),
        ]);
      }

      if (mounted) {
        state = state.copyWith(
          isSyncing: false,
          isConnected: true,
          lastSynced: DateTime.now(),
          pendingCount: OfflineSyncService.getPendingCount(),
        );
      }
    } catch (e) {
      debugPrint('Sync Heartbeat Warning: $e');
      if (mounted) {
        state = state.copyWith(
          isSyncing: false,
          pendingCount: OfflineSyncService.getPendingCount(),
        );
      }
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
    _connectivitySub?.cancel();
    _timer?.cancel();
    super.dispose();
  }
}

final syncProvider = StateNotifierProvider<SyncNotifier, CloudSyncState>((ref) {
  return SyncNotifier(ref);
});

final connectivityStatusProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  // Yield initial state
  yield await Connectivity().checkConnectivity();
  // Then yield subsequent changes
  yield* Connectivity().onConnectivityChanged;
});
