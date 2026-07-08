import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../core/uuid_utils.dart';
import '../models/product.dart';
import 'supabase_product_service.dart';
import 'user_provider.dart';
import 'notification_service.dart';
import 'sms_service.dart';
import 'audit_service.dart';
import 'offline_sync_service.dart';
import '../models/system_models.dart';
import '../core/supabase_config.dart';

abstract class ProductService {
  Future<List<Product>> getProducts(String branchCode);
  Future<Product> getProductById(String id);
  Future<void> addProduct(Product product);
  Future<void> updateProduct(Product product);
  Future<void> deleteProduct(String id);
  Future<void> updateStock(String id, double newQuantity);
  Future<void> applyPromotion(String id, double percentage, DateTime? start, DateTime? end, PromoTarget target, PromoCustomerTarget customerTarget);
  Future<String?> uploadProductImage(Uint8List bytes, String fileName);
  Stream<List<Product>> watchProducts(String branchCode);
}

final productServiceProvider = Provider<ProductService>((ref) {
  return SupabaseProductService();
});

// Moved to top to resolve potential circular resolution issues
final productsFutureProvider = StateNotifierProvider<ProductNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductNotifier(ref.watch(productServiceProvider), ref);
});

class ProductNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  final ProductService _service;
  final Ref ref;
  StreamSubscription<List<Product>>? _subscription;

  ProductNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    // 0. Load from local Hive cache immediately for offline support
    _loadFromCache();

    // 1. Watch current user and restart subscription if branch changes
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });

    // 2. Background Heartbeat: Silent refresh logic every 3 seconds
    ref.listen(liveHeartbeatProvider, (_, _) {
      final products = state.value;
      if (products != null) {
        _checkStockAlerts(products);
      }
    });
    
    _startSubscription();
  }

  void _loadFromCache() {
    try {
      final box = Hive.box(OfflineSyncService.productsBoxName);
      if (box.isNotEmpty) {
        final List<Product> cached = box.values
            .map((json) => Product.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        state = AsyncValue.data(cached);
        debugPrint('Product Engine: ${cached.length} products loaded from local cache.');
      }
    } catch (e) {
      debugPrint('Product Engine Cache Error: $e');
    }
  }

  void _saveToCache(List<Product> products) {
    try {
      final box = Hive.box(OfflineSyncService.productsBoxName);
      // Update with fresh data
      box.clear();
      for (var p in products) {
        box.put(p.id, p.toJson());
      }
    } catch (e) {
      debugPrint('Product Engine Save Error: $e');
    }
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user != null && user.branchCode != null) {
      _subscription = _service.watchProducts(user.branchCode!).listen(
        (products) {
          state = AsyncValue.data(products);
          _saveToCache(products); // Persist for next offline session
          _checkStockAlerts(products);
        },
        onError: (e, st) {
          // If we have cached data, don't show error, just stay on cached data
          if (state.hasValue) {
            debugPrint('Product Stream Error (Offline?): Using cached data.');
          } else {
            state = AsyncValue.error(e, st);
          }
        },
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  void _checkStockAlerts(List<Product> products) {
    for (final product in products) {
      if (!product.isDeleted && 
          product.lastStockUpdate != null && // Avoid alerts for brand new/uninitialized items
          product.stockQuantity <= product.lowStockThreshold) {
        final title = 'LOW STOCK ALERT: ${product.name}';
        final message = '${product.name} is below safety threshold (${product.stockQuantity}${product.unit} remaining).';
        
        // Avoid duplicate notifications (don't check isRead, just existence)
        // This prevents the alert from reappearing immediately after being cleared/read
        final notifications = ref.read(notificationProvider);
        final existing = notifications.any((n) => n.title == title);

        if (!existing) {
          ref.read(notificationProvider.notifier).addNotification(title, message);
          
          // Optionally notify admin via SMS
          SmsService.notifyAdmin(title: title, message: message);
        }
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> loadProducts() async {
    // The stream handles loading automatically, but we can keep this for manual refreshes if needed
    _startSubscription();
  }

  Future<void> addProduct(Product product) async {
    final user = ref.read(currentUserProvider);
    final productWithBranch = product.copyWith(branchCode: user?.branchCode);
    
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.addProduct(productWithBranch);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      // Use Offline Queue
      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_PRODUCT',
        data: productWithBranch.toJson(),
      );
      
      // Update local state immediately for responsiveness
      state.whenData((products) {
        final newList = [...products, productWithBranch];
        state = AsyncValue.data(newList);
        _saveToCache(newList);
      });
    }
  }

  Future<void> updateProduct(Product updatedProduct) async {
    try {
      final oldProduct = state.value?.firstWhere((p) => p.id == updatedProduct.id);
      
      // Audit Log
      await AuditService.log(
        ref: ref,
        action: 'PRODUCT_UPDATED',
        entityType: 'PRODUCT',
        entityId: updatedProduct.id,
        oldData: oldProduct?.toJson(),
        newData: updatedProduct.toJson(),
      );

      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateProduct(updatedProduct);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_PRODUCT',
        data: updatedProduct.toJson(),
      );

      state.whenData((products) {
        final newList = products.map((p) => p.id == updatedProduct.id ? updatedProduct : p).toList();
        state = AsyncValue.data(newList);
        _saveToCache(newList);
      });
    }
  }

  Future<void> deleteProduct(String id) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.deleteProduct(id);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      await OfflineSyncService.addToQueue(
        actionType: 'DELETE_PRODUCT',
        data: {'id': id},
      );

      state.whenData((products) {
        final newList = products.where((p) => p.id != id).toList();
        state = AsyncValue.data(newList);
        _saveToCache(newList);
      });
    }
  }

  Future<void> restoreProduct(String id) async {
    state.whenData((products) async {
      final updated = products.map((p) => p.id == id ? p.copyWith(isDeleted: false) : p).toList();
      state = AsyncValue.data(updated);
      
      final product = updated.firstWhere((p) => p.id == id);
      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_PRODUCT',
        data: product.toJson(),
      );
    });
  }

  Future<void> updateStock(String id, double quantityChange, {String reason = 'ADJUSTMENT', String? referenceId}) async {
    final products = state.value;
    final now = DateTime.now();
    final user = ref.read(currentUserProvider);

    try {
      Product? product;
      if (products != null) {
        product = products.where((p) => p.id == id).firstOrNull;
      }
      
      // If not in local state, fetch from remote to be sure
      if (product == null) {
        debugPrint('Product Engine: Product $id not in local state. Fetching from service...');
        product = await _service.getProductById(id);
      }

      double currentDailyAdded = product.dailyStockAdded;
      
      // Reset daily added if it's a new day
      if (product.lastStockUpdate != null) {
        final lastUpdate = product.lastStockUpdate!;
        if (lastUpdate.year != now.year || lastUpdate.month != now.month || lastUpdate.day != now.day) {
          currentDailyAdded = 0;
        }
      }

      final newQuantity = product.stockQuantity + quantityChange;
      // Only track positive additions to stock for "added today"
      final newDailyAdded = quantityChange > 0 ? (currentDailyAdded + quantityChange) : currentDailyAdded;
      
      final updatedProduct = product.copyWith(
        stockQuantity: newQuantity,
        dailyStockAdded: newDailyAdded,
        lastStockUpdate: now,
      );

      // 1. Update Remote - Atomic Increment for high concurrency (Multiple users)
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        // ATOMIC: Use database function to add to the existing quantity on the server
        await SupabaseConfig.client.rpc('increment_stock', params: {
          'p_id': id,
          'p_amount': quantityChange,
        });
        
        // Update metadata separately (last update time, daily added tracker)
        // We don't include 'stock_quantity' in this update to prevent overwriting the RPC result
        final metadata = {
          'daily_stock_added': updatedProduct.dailyStockAdded,
          'last_stock_update': updatedProduct.lastStockUpdate?.toIso8601String(),
        };
        
        await SupabaseConfig.client
            .from('products')
            .update(metadata)
            .eq('id', id);
      } else {
        await OfflineSyncService.addToQueue(
          actionType: 'UPDATE_PRODUCT_STOCK',
          data: {
            'id': id,
            'change_amount': quantityChange,
            'timestamp': now.toIso8601String(),
          },
        );
        
        // Also send a general update for metadata (daily added, etc.)
        await OfflineSyncService.addToQueue(
          actionType: 'UPDATE_PRODUCT',
          data: updatedProduct.toJson(),
        );
      }
      
      // 2. Audit Log for Stock Change
      await AuditService.log(
        ref: ref,
        action: 'STOCK_ADJUSTED',
        entityType: 'PRODUCT',
        entityId: id,
        newData: {'change': quantityChange, 'new_total': newQuantity, 'reason': reason},
      );

      // 3. Log Stock History
      final historyEntry = StockHistory(
        id: UuidUtils.generate(),
        branchCode: user?.branchCode,
        productId: id,
        changeAmount: quantityChange,
        newQuantity: newQuantity,
        reason: reason,
        referenceId: referenceId,
        timestamp: now,
      );

      await OfflineSyncService.addToQueue(
        actionType: 'STOCK_HISTORY',
        data: historyEntry.toJson(),
      );

      // 4. Update local state immediately if available
      if (products != null) {
        state = AsyncValue.data(products.map((p) {
          if (p.id == id) return updatedProduct;
          return p;
        }).toList());
      }
    } catch (e) {
      debugPrint('Stock Update Error: $e');
      rethrow;
    }
  }

  Future<void> applyPromotion(double percentage, DateTime start, DateTime end, PromoTarget target, PromoCustomerTarget customerTarget, {List<String>? selectedIds}) async {
    state.whenData((products) async {
      final productsToUpdate = selectedIds == null 
          ? products 
          : products.where((p) => selectedIds.contains(p.id)).toList();
      
      try {
        for (var p in productsToUpdate) {
          final data = {
            'discount_percentage': percentage,
            'promo_start': start.toIso8601String(),
            'promo_end': end.toIso8601String(),
            'promo_target': target.name,
            'promo_customer_target': customerTarget.name,
          };
          
          await OfflineSyncService.addToQueue(
            actionType: 'PROMOTION',
            data: {'id': p.id, 'data': data},
          );
        }
        
        state = AsyncValue.data(products.map((p) {
          if (selectedIds == null || selectedIds.contains(p.id)) {
            return p.copyWith(
              discountPercentage: percentage,
              promoStartDate: start,
              promoEndDate: end,
              promoTarget: target,
              promoCustomerTarget: customerTarget,
            );
          }
          return p;
        }).toList());
      } catch (e) {
        debugPrint('Apply Promotion Error: $e');
      }
    });
  }

  Future<void> clearPromotions() async {
    state.whenData((products) async {
      try {
        for (var p in products) {
          if (p.discountPercentage > 0) {
            final data = {
              'discount_percentage': 0,
              'promo_start': null,
              'promo_end': null,
              'promo_target': PromoTarget.both.name,
              'promo_customer_target': PromoCustomerTarget.all.name,
            };
            
            await OfflineSyncService.addToQueue(
              actionType: 'PROMOTION',
              data: {'id': p.id, 'data': data},
            );
          }
        }
        state = AsyncValue.data(products.map((p) => p.copyWith(
          discountPercentage: 0,
          promoStartDate: null,
          promoEndDate: null,
        )).toList());
      } catch (e) {
        debugPrint('Clear Promotions Error: $e');
      }
    });
  }

  Future<void> removePromotion(String productId) async {
    state.whenData((products) async {
      try {
        final data = {
          'discount_percentage': 0,
          'promo_start': null,
          'promo_end': null,
          'promo_target': PromoTarget.both.name,
          'promo_customer_target': PromoCustomerTarget.all.name,
        };
        
        await OfflineSyncService.addToQueue(
          actionType: 'PROMOTION',
          data: {'id': productId, 'data': data},
        );

        state = AsyncValue.data(products.map((p) {
          if (p.id == productId) {
            return p.copyWith(
              discountPercentage: 0,
              promoStartDate: null,
              promoEndDate: null,
            );
          }
          return p;
        }).toList());
      } catch (e) {
        debugPrint('Remove Promotion Error: $e');
      }
    });
  }

  Future<void> clearAllStock() async {
    state.whenData((products) async {
      try {
        for (var p in products) {
          await OfflineSyncService.addToQueue(
            actionType: 'UPDATE_PRODUCT_STOCK',
            data: {
              'id': p.id,
              'change_amount': -p.stockQuantity,
              'timestamp': DateTime.now().toIso8601String(),
            },
          );
        }
        state = AsyncValue.data(products.map((p) => p.copyWith(stockQuantity: 0)).toList());
      } catch (e) {
        debugPrint('Clear Stock Error: $e');
      }
    });
  }

  Future<String?> uploadImage(Uint8List bytes, String fileName) async {
    return await _service.uploadProductImage(bytes, fileName);
  }
}
