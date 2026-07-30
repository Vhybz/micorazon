import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'supabase_system_service.dart';
import 'user_provider.dart';
import 'offline_sync_service.dart';
import '../models/user_model.dart';
import '../models/system_models.dart';

final systemServiceProvider = Provider<SupabaseSystemService>((ref) {
  return SupabaseSystemService();
});

final auditLogProvider = StateNotifierProvider<AuditNotifier, List<AuditLog>>((ref) {
  return AuditNotifier(ref.watch(systemServiceProvider), ref);
});

class AuditNotifier extends StateNotifier<List<AuditLog>> {
  final SupabaseSystemService _service;
  final Ref ref;

  AuditNotifier(this._service, this.ref) : super([]) {
    _init();
  }

  void _init() {
    _loadFromCache();
    
    // Refresh whenever user changes
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        refreshLogs();
      }
    });

    refreshLogs();
  }

  void _loadFromCache() {
    try {
      final box = Hive.box(OfflineSyncService.auditBoxName);
      if (box.isNotEmpty) {
        final List<AuditLog> cached = box.values
            .map((json) => AuditLog.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        state = cached;
        debugPrint('Audit Engine: ${cached.length} logs loaded from local cache.');
      }
    } catch (e) {
      debugPrint('Audit Engine Cache Error: $e');
    }
  }

  void _saveToCache(List<AuditLog> logs) {
    try {
      final box = Hive.box(OfflineSyncService.auditBoxName);
      box.clear();
      // Keep only last 100 logs offline
      final toCache = logs.take(100).toList();
      for (var l in toCache) {
        box.add(l.toJson());
      }
    } catch (e) {
      debugPrint('Audit Engine Save Error: $e');
    }
  }

  Future<void> refreshLogs() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    try {
      // Super Admin sees ALL logs, others see only branch logs
      final logs = user.role == UserRole.superAdmin 
          ? await _service.getGlobalAuditLogs()
          : await _service.getAuditLogs(user.branchCode ?? '');
      state = logs;
      _saveToCache(logs);
    } catch (e) {
      debugPrint('Refresh Audit Logs Error: $e');
    }
  }
}

final notificationsFutureProvider = FutureProvider<List<SystemNotification>>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return [];
  return ref.watch(systemServiceProvider).getNotifications(user.branchCode ?? '', user.id);
});

final customerPaymentsProvider = FutureProvider.family<List<CustomerPayment>, String>((ref, customerId) async {
  return ref.watch(systemServiceProvider).getCustomerPayments(customerId);
});

final stockHistoryProvider = FutureProvider.family<List<StockHistory>, String>((ref, productId) async {
  return ref.watch(systemServiceProvider).getStockHistory(productId);
});
