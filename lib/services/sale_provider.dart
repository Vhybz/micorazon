import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/sale_model.dart';
import '../models/customer_model.dart';
import '../core/uuid_utils.dart';
import 'customer_provider.dart';
import 'supabase_sale_service.dart';
import 'user_provider.dart';
import 'product_service.dart';
import 'offline_sync_service.dart';
import 'audit_service.dart';

class SaleHistoryNotifier extends StateNotifier<List<SaleRecord>> {
  final SupabaseSaleService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  SaleHistoryNotifier(this._service, this.ref) : super([]) {
    _init();
    
    // Background Heartbeat: Auto-refresh data and check for updates every 3 seconds
    ref.listen(liveHeartbeatProvider, (_, _) {
      // Force a list refresh to ensure all financial calculations are re-computed
      state = [...state];
    });
  }

  void _init() {
    _loadFromCache();
    
    // Watch current user and restart subscription if branch changes
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _initStream();
      }
    });

    _initStream();
  }

  void _loadFromCache() {
    try {
      final box = Hive.box(OfflineSyncService.salesBoxName);
      if (box.isNotEmpty) {
        final List<SaleRecord> cached = box.values
            .map((json) => SaleRecord.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        state = cached;
        debugPrint('Sale Engine: ${cached.length} records loaded from local cache.');
      }
    } catch (e) {
      debugPrint('Sale Engine Cache Error: $e');
    }
  }

  void _saveToCache(List<SaleRecord> sales) {
    try {
      final box = Hive.box(OfflineSyncService.salesBoxName);
      box.clear();
      // Keep only last 100 sales offline to save space
      final toCache = sales.take(100).toList();
      for (var s in toCache) {
        box.put(s.id, s.toJson());
      }
    } catch (e) {
      debugPrint('Sale Engine Save Error: $e');
    }
  }

  void _initStream() {
    final user = ref.read(currentUserProvider);
    if (user?.branchCode == null) return;

    _subscription?.cancel();
    _subscription = _service.getSalesStream(user!.branchCode!).listen((sales) {
      state = sales;
      _saveToCache(sales);
    }, onError: (e) {
      debugPrint('Sale Stream Error (Offline?): Using cached data.');
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> loadSales() async {
    _initStream();
  }

  Future<void> addSale(SaleRecord sale) async {
    final user = ref.read(currentUserProvider);
    final saleWithBranch = sale.copyWith(branchCode: user?.branchCode);

    try {
      // 1. Audit Log (Source of truth tracking)
      await AuditService.log(
        ref: ref,
        action: 'SALE_CREATED',
        entityType: 'SALE',
        entityId: saleWithBranch.id,
        newData: saleWithBranch.toJson(),
      );

      // 2. Try Supabase First
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.saveSale(saleWithBranch);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      // 3. Fallback to Hive Queue
      await OfflineSyncService.addToQueue(
        actionType: 'SALE', 
        data: saleWithBranch.toJson(),
      );
      // Optimistic local update
      state = [saleWithBranch, ...state];
    }

    // 4. Auto-Register Debtor as Customer if missing
    _ensureCustomerRegistered(saleWithBranch);

    // 5. Update stock if verified
    if (saleWithBranch.isVerified) {
      for (final item in saleWithBranch.items) {
        if (!item.product.isUnlimited) {
          await ref.read(productsFutureProvider.notifier).updateStock(
            item.product.id, 
            -item.quantity, 
            reason: 'SALE', 
            referenceId: saleWithBranch.id,
          );
        }
      }
    }
  }

  Future<void> verifySale(String saleId, {String? bankReceiptUrl, String? bankReceiptId}) async {
    try {
      final sale = state.firstWhere((s) => s.id == saleId);
      if (sale.isVerified) return;

      final updatedSale = sale.copyWith(
        isVerified: true, 
        status: SaleStatus.completed,
        bankReceiptUrl: bankReceiptUrl ?? sale.bankReceiptUrl,
        bankReceiptId: bankReceiptId ?? sale.bankReceiptId,
      );
      
      // Audit Log
      await AuditService.log(
        ref: ref,
        action: 'SALE_VERIFIED',
        entityType: 'SALE',
        entityId: sale.id,
        newData: updatedSale.toJson(),
      );

      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.saveSale(updatedSale);
      } else {
        await OfflineSyncService.addToQueue(
          actionType: 'SALE',
          data: updatedSale.toJson(),
        );
        state = [for (final s in state) if (s.id == saleId) updatedSale else s];
      }

      for (final item in sale.items) {
        if (!item.product.isUnlimited) {
          await ref.read(productsFutureProvider.notifier).updateStock(
            item.product.id, 
            -item.quantity, 
            reason: 'SALE', 
            referenceId: sale.id,
          );
        }
      }
    } catch (e) {
      debugPrint('Verify Sale Error: $e');
    }
  }

  Future<void> updateSale(SaleRecord updatedSale) async {
    try {
      final oldSale = state.where((s) => s.id == updatedSale.id).firstOrNull;
      if (oldSale == null) return;

      // 1. Reconciliation Logic for Stock
      // Process items in the updated sale
      for (final newItem in updatedSale.items) {
        if (newItem.product.isUnlimited) continue;
        
        final oldItem = oldSale.items.where((i) => i.product.id == newItem.product.id).firstOrNull;
        if (oldItem != null) {
          final diff = oldItem.quantity - newItem.quantity;
          if (diff != 0) {
             // If old > new, diff is positive (e.g. 10 - 8 = 2), so we add 2 back to stock.
             // If old < new, diff is negative (e.g. 5 - 7 = -2), so we subtract 2 from stock.
             await ref.read(productsFutureProvider.notifier).updateStock(
               newItem.product.id, 
               diff, 
               reason: 'SALE_RECTIFIED', 
               referenceId: updatedSale.id,
             );
          }
        } else {
          // New product added to existing receipt: subtract full quantity
          await ref.read(productsFutureProvider.notifier).updateStock(
            newItem.product.id, 
            -newItem.quantity, 
            reason: 'SALE_RECTIFIED', 
            referenceId: updatedSale.id,
          );
        }
      }
      
      // Check for removed products: add their full quantity back to stock
      for (final oldItem in oldSale.items) {
        if (oldItem.product.isUnlimited) continue;
        final stillExists = updatedSale.items.any((i) => i.product.id == oldItem.product.id);
        if (!stillExists) {
           await ref.read(productsFutureProvider.notifier).updateStock(
             oldItem.product.id, 
             oldItem.quantity, 
             reason: 'SALE_RECTIFIED', 
             referenceId: updatedSale.id,
           );
        }
      }

      // 2. Audit Log
      await AuditService.log(
        ref: ref,
        action: 'SALE_RECTIFIED',
        entityType: 'SALE',
        entityId: updatedSale.id,
        oldData: oldSale.toJson(),
        newData: updatedSale.toJson(),
      );

      // 3. Database Update
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateSale(updatedSale);
      } else {
        await OfflineSyncService.addToQueue(
          actionType: 'SALE',
          data: updatedSale.toJson(),
        );
      }

      // 4. State Update
      state = [for (final s in state) if (s.id == updatedSale.id) updatedSale else s];
      _saveToCache(state);
      
      // Auto-Register Debtor if update created a debt
      _ensureCustomerRegistered(updatedSale);
    } catch (e) {
      debugPrint('Update Sale Error: $e');
    }
  }

  void _ensureCustomerRegistered(SaleRecord sale) {
    if (sale.balance > 0.01 && sale.customerPhone != null) {
      final customers = ref.read(customerProvider);
      final exists = customers.any((c) => c.phone == sale.customerPhone);
      
      if (!exists) {
        final newCustomer = Customer(
          id: UuidUtils.generate(),
          branchCode: sale.branchCode,
          name: sale.customerName ?? 'Walk-in Debtor',
          phone: sale.customerPhone!,
          location: 'Auto-added from Debt Sale',
        );
        // addCustomer is optimistic and non-blocking
        ref.read(customerProvider.notifier).addCustomer(newCustomer);
      }
    }
  }

  Future<void> reverseSale(String saleId) async {
    try {
      final sale = state.firstWhere((s) => s.id == saleId);
      
      // 1. Audit Log (Source of truth tracking)
      await AuditService.log(
        ref: ref,
        action: 'SALE_REVERSED',
        entityType: 'SALE',
        entityId: saleId,
        newData: {'id': saleId, 'status': 'reversed', 'reason': 'ADMIN_REVERSE'},
      );

      // 2. Restore Stock
      for (final item in sale.items) {
        if (!item.product.isUnlimited) {
          // Add back the quantity sold
          await ref.read(productsFutureProvider.notifier).updateStock(
            item.product.id, 
            item.quantity, 
            reason: 'SALE_REVERSED', 
            referenceId: saleId,
          );
        }
      }

      // 3. Update status to Reversed (Do not delete)
      final reversedSale = sale.copyWith(status: SaleStatus.reversed);
      
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateSale(reversedSale);
      } else {
        await OfflineSyncService.addToQueue(
          actionType: 'SALE',
          data: reversedSale.toJson(),
        );
      }

      // 4. Update local state
      state = [
        for (final s in state)
          if (s.id == saleId) reversedSale else s
      ];
      _saveToCache(state);

    } catch (e) {
      debugPrint('Reverse Sale Error: $e');
      rethrow;
    }
  }

  Future<void> deleteSales(List<String> ids) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.deleteSales(ids);
      } else {
        for (final id in ids) {
          await OfflineSyncService.addToQueue(
            actionType: 'DELETE_SALE',
            data: {'id': id},
          );
        }
        state = state.where((s) => !ids.contains(s.id)).toList();
      }
    } catch (e) {
      debugPrint('Delete Sales Error: $e');
    }
  }

  Future<void> purgeAllRecords() async {
    try {
      final ids = state.map((s) => s.id).toList();
      for (final id in ids) {
        await OfflineSyncService.addToQueue(
          actionType: 'DELETE_SALE',
          data: {'id': id},
        );
      }
      state = [];
    } catch (e) {
      debugPrint('Purge Sales Error: $e');
    }
  }
}

final saleServiceProvider = Provider<SupabaseSaleService>((ref) {
  return SupabaseSaleService();
});

final saleHistoryProvider = StateNotifierProvider<SaleHistoryNotifier, List<SaleRecord>>((ref) {
  return SaleHistoryNotifier(ref.watch(saleServiceProvider), ref);
});
