import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/transfer_models.dart';
import '../models/user_model.dart';
import 'supabase_transfer_service.dart';
import 'product_service.dart';
import 'notification_service.dart';
import '../models/product.dart';

import 'offline_sync_service.dart';
import 'user_provider.dart';

import 'sms_service.dart';
import 'branch_provider.dart';

class TransferNotifier extends StateNotifier<List<StockTransfer>> {
  final SupabaseTransferService _service;
  final Ref ref;
  StreamSubscription? _subscription;
  Timer? _refreshTimer;
  
  // NEW: Track local status overrides with timestamps to ensure they are "sticky"
  final Map<String, (TransferStatus, DateTime)> _statusOverrides = {};

  TransferNotifier(this._service, this.ref) : super([]) {
    _init();
    _startHeartbeat();
  }

  void _init() {
    _loadFromCache();
    
    // Auto-reload when user branch changes
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        debugPrint('Transfer Sync: User branch changed to ${next?.branchCode}. Reloading...');
        _startSubscription();
      }
    });

    _startSubscription();
  }

  void _loadFromCache() {
    try {
      final box = Hive.box(OfflineSyncService.transfersBoxName);
      if (box.isNotEmpty) {
        final List<StockTransfer> cached = box.values
            .map((json) => StockTransfer.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        state = cached;
        debugPrint('Transfer Engine: ${cached.length} records loaded from local cache.');
      }
    } catch (e) {
      debugPrint('Transfer Engine Cache Error: $e');
    }
  }

  void _saveToCache(List<StockTransfer> transfers) {
    try {
      final box = Hive.box(OfflineSyncService.transfersBoxName);
      box.clear();
      for (var t in transfers) {
        box.put(t.id, t.toJson());
      }
    } catch (e) {
      debugPrint('Transfer Engine Save Error: $e');
    }
  }

  void _startSubscription() {
    _subscription?.cancel();
    try {
      _subscription = _service.watchTransfers().listen(
        (transfers) {
          debugPrint('Stock Transfer Stream: Syncing ${transfers.length} items from cloud.');
          _saveToCache(transfers);
          _applyOverridesAndSetState(transfers);
        }, 
        onError: (err) {
          debugPrint('Stock Transfer Stream Connection Error (Resuming?): $err');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('Stock Transfer Stream Init Failed: $e');
    }
  }

  void _applyOverridesAndSetState(List<StockTransfer> remoteTransfers) {
    final now = DateTime.now();
    final user = ref.read(currentUserProvider);
    
    // 1. Load pending items from Offline Queue (Hive)
    final pendingCreates = OfflineSyncService.getPendingItems('TRANSFER')
        .map((json) => StockTransfer.fromJson(json));
        
    final pendingUpdates = OfflineSyncService.getPendingItems('UPDATE_TRANSFER')
        .map((json) => StockTransfer.fromJson(json));

    // 2. Map all items by ID for easy reconciliation
    final Map<String, StockTransfer> allTransfersMap = {};

    // First, add all existing items in the current state (prioritizing optimistic ones)
    for (var t in state) {
      allTransfersMap[t.id] = t;
    }

    // Then, add/overwrite with remote data
    for (var t in remoteTransfers) {
      allTransfersMap[t.id] = t;
    }

    // Finally, add pending items from Offline Queue (Hive)
    for (var t in pendingCreates) {
      if (!allTransfersMap.containsKey(t.id)) {
        allTransfersMap[t.id] = t;
      }
    }
    
    for (var t in pendingUpdates) {
      allTransfersMap[t.id] = t;
    }

    // 3. Clean up expired overrides (older than 45 seconds)
    _statusOverrides.removeWhere((id, data) => now.difference(data.$2).inSeconds > 45);

    // 4. Apply manual status overrides
    final reconciled = allTransfersMap.values.map((t) {
      if (_statusOverrides.containsKey(t.id)) {
        final data = _statusOverrides[t.id]!;
        final localStatus = data.$1;
        final timestamp = data.$2;
        
        if (t.status == localStatus && now.difference(timestamp).inSeconds > 10) {
          _statusOverrides.remove(t.id);
          return t;
        }
        
        return t.copyWith(status: localStatus);
      }
      return t;
    }).toList();

    // 5. Final Sort (Newest first)
    reconciled.sort((a, b) => b.transferTime.compareTo(a.transferTime));

    // Debugging: Log what the notifier sees vs current user
    if (user != null && reconciled.isNotEmpty) {
      final myItems = reconciled.where((t) => 
        t.destination.trim().toLowerCase() == user.branchCode?.trim().toLowerCase()
      ).length;
      debugPrint('Transfer Engine: Total=${reconciled.length}, MyBranch(${(user.branchCode ?? "??")})=$myItems');
    }

    state = reconciled;
  }

  /// Heartbeat to ensure data stays fresh even if the stream disconnects
  void _startHeartbeat() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      loadTransfers();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadTransfers() async {
    try {
      final transfers = await _service.getTransfers();
      _applyOverridesAndSetState(transfers);
    } catch (e) {
      debugPrint('Stock Transfer Manual Error: $e');
    }
  }

  Future<void> addTransfer(StockTransfer transfer) async {
    final user = ref.read(currentUserProvider);
    final sourceBranch = user?.branchCode;
    
    // Ensure the transfer has a source branch code for filtering
    final tWithBranch = transfer.branchCode == null 
        ? transfer.copyWith(branchCode: sourceBranch) 
        : transfer;

    // 0. Optimistic Update: Add to state immediately so it's visible in UI
    state = [tWithBranch, ...state];
    _statusOverrides[tWithBranch.id] = (tWithBranch.status, DateTime.now());

    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.addTransfer(tWithBranch);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      // 1. If online failed or device is offline, add to Hive Queue
      await OfflineSyncService.addToQueue(
        actionType: 'TRANSFER', 
        data: tWithBranch.toJson(),
      );
    }
    
    // Notify destination branch users
    ref.read(notificationProvider.notifier).addNotification(
      'STOCK FOR VERIFICATION',
      'ATTENTION CASHIER: ${tWithBranch.meatType} (${tWithBranch.weight}${tWithBranch.unit}) has been dispatched to your branch.',
      targetBranchCode: tWithBranch.destination,
    );

    // Send SMS Notifications
    _sendTransferSms(tWithBranch.destination, '${tWithBranch.weight}${tWithBranch.unit} of ${tWithBranch.meatType}');
  }

  Future<void> _sendTransferSms(String branchCode, String itemDetails) async {
    try {
      final branchesAsync = ref.read(branchesProvider);
      final users = ref.read(userProvider);
      
      final branch = branchesAsync.whenOrNull(
        data: (list) => list.where((b) => b.code == branchCode).firstOrNull,
      );

      await SmsService.sendTransferNotificationSms(
        branchName: branch?.name ?? branchCode,
        branchCode: branchCode,
        itemDetails: itemDetails,
        branchUsers: users,
      );
    } catch (e) {
      debugPrint('Error sending transfer SMS: $e');
    }
  }

  Future<void> addTransfers(List<StockTransfer> transfers) async {
    try {
      final user = ref.read(currentUserProvider);
      final sourceBranch = user?.branchCode;
      final now = DateTime.now();
      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = !connectivity.contains(ConnectivityResult.none);

      final List<StockTransfer> processed = [];
      for (var t in transfers) {
        final withSource = t.branchCode == null ? t.copyWith(branchCode: sourceBranch) : t;
        processed.add(withSource);
        
        _statusOverrides[withSource.id] = (withSource.status, now);
        
        if (isOnline) {
          await _service.addTransfer(withSource);
        } else {
          await OfflineSyncService.addToQueue(
            actionType: 'TRANSFER', 
            data: withSource.toJson(),
          );
        }
      }
      
      // Update state with all new transfers immediately
      state = [...processed, ...state];
      
      // Notify destination branch
      if (processed.isNotEmpty) {
        final totalWeight = processed.fold(0.0, (sum, t) => sum + t.weight);
        ref.read(notificationProvider.notifier).addNotification(
          'INCOMING STOCK',
          'ATTENTION CASHIER: ${processed.length} items (${totalWeight.toStringAsFixed(1)}${processed.first.unit}) are on the way.',
          targetBranchCode: processed.first.destination,
          type: 'success',
        );

        // Send SMS Notifications
        _sendTransferSms(
          processed.first.destination, 
          '${processed.length} items (${totalWeight.toStringAsFixed(1)}${processed.first.unit})'
        );
      }
    } catch (e) {
      debugPrint('Error adding bulk transfers: $e');
    }
  }

  Future<void> markAsReceived(String id) async {
    try {
      final transfer = state.firstWhere((t) => t.id == id);
      final updatedTransfer = transfer.copyWith(status: TransferStatus.received);

      // 0. Record "sticky" override to prevent sync reverting the UI
      _statusOverrides[id] = (TransferStatus.received, DateTime.now());

      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateTransferStatus(id, TransferStatus.received);
      } else {
        // 1. Add to Offline Queue (Update)
        await OfflineSyncService.addToQueue(
          actionType: 'UPDATE_TRANSFER', 
          data: updatedTransfer.toJson(),
        );
      }
      
      // 2. Update Retail Stock
      final productsAsync = ref.read(productsFutureProvider);
      final products = productsAsync.value;
      
      // If products aren't loaded in memory yet, we can't reliably match here.
      // But updateStock is now robust enough to fetch from remote if needed.
      // We still need the product ID though.
      
      // Strategy: Extract the cut name (part after first ' - ') and look for it in product names
      String cutToMatch = transfer.meatType;
      String animalType = '';
      if (transfer.meatType.contains(' - ')) {
        final parts = transfer.meatType.split(' - ');
        animalType = parts[0].trim();
        cutToMatch = parts.sublist(1).join(' - ').trim();
      }

      // Robust matching logic
      Product? matchedProduct;
      if (products != null) {
        // 1. Try exact match with category + name (Most reliable)
        matchedProduct = products.where((p) {
          final pName = p.name.toLowerCase();
          final pCat = p.category.toLowerCase();
          final mType = transfer.meatType.toLowerCase();
          final cut = cutToMatch.toLowerCase();
          final animal = animalType.toLowerCase();

          // Handle "Beef" vs "Cow" aliases
          final bool catMatch = pCat == animal || 
                              (pCat == 'cow' && animal == 'beef') || 
                              (pCat == 'beef' && animal == 'cow');

          return (catMatch && pName == cut) || 
                 (catMatch && mType.contains(pName)) ||
                 (pName == mType);
        }).firstOrNull;

        // 2. Fallback to name-only match
        matchedProduct ??= products.where((p) {
          final pName = p.name.toLowerCase();
          final cut = cutToMatch.toLowerCase();
          final mType = transfer.meatType.toLowerCase();

          return pName == cut || pName == mType || mType.contains(pName);
        }).firstOrNull;
      }

      if (matchedProduct == null) {
        // Fallback: If not in current list, maybe try a manual refresh of products first
        debugPrint('Transfer Engine: Product "$cutToMatch" not found in memory. Triggering stock update by name...');
        if (products == null) throw Exception('Inventory not loaded. Please refresh the POS and try again.');
        throw Exception('Product "$cutToMatch" (${animalType.toUpperCase()}) not found in retail catalog. Ensure the product exists in Master Stock Control.');
      }

      await ref.read(productsFutureProvider.notifier).updateStock(
        matchedProduct.id,
        transfer.weight,
        reason: 'TRANSFER',
        referenceId: transfer.id,
      );

      // Check for pricing
      bool needsPricing = matchedProduct.retailPrice <= 0 || matchedProduct.wholesalePrice <= 0;

      // Notify System (Local)
      ref.read(notificationProvider.notifier).addNotification(
        needsPricing ? 'STOCK RECEIVED (PRICING REQ)' : 'STOCK RECEIVED',
        'Added ${transfer.weight}kg of ${matchedProduct.name} to inventory.${needsPricing ? ' ALERT: Product requires Admin pricing before it can be sold.' : ''}',
        type: needsPricing ? 'warning' : 'success',
      );

      state = [
        for (final t in state)
          if (t.id == id) updatedTransfer else t
      ];
    } catch (e) {
      debugPrint('Error marking transfer as received: $e');
      rethrow;
    }
  }
}

final transferServiceProvider = Provider<SupabaseTransferService>((ref) {
  return SupabaseTransferService();
});

final transferProvider = StateNotifierProvider<TransferNotifier, List<StockTransfer>>((ref) {
  return TransferNotifier(ref.watch(transferServiceProvider), ref);
});

/// A provider that filters for pending incoming transfers for the current user's branch
final pendingIncomingTransfersProvider = Provider<List<StockTransfer>>((ref) {
  final user = ref.watch(currentUserProvider);
  final transfers = ref.watch(transferProvider);
  
  if (user == null) return [];
  
  final String userBranch = (user.branchCode ?? '').trim().toLowerCase();
  final bool isSuperAdmin = user.activePrimaryRole == UserRole.superAdmin;

  // 1. Super Admins see ALL pending transfers across the entire company for global visibility
  if (isSuperAdmin) {
    return transfers.where((t) => t.status == TransferStatus.pending).toList();
  }
  
    // 2. Filter transfers where the destination matches the user's branch
  final branchPending = transfers.where((t) {
    final String destCode = (t.destination).trim().toLowerCase();
    final String sourceCode = (t.branchCode ?? '').trim().toLowerCase();
    
    // Check for exact match OR if the destination contains the branch code
    final bool isMatch = userBranch.isEmpty || 
                         destCode == userBranch || 
                         destCode.contains(userBranch) ||
                         userBranch.contains(destCode) ||
                         // Cashier should see dispatches originating FROM their branch destined for THIRDPARTY
                         (destCode == 'thirdparty' && sourceCode == userBranch) ||
                         // Support "PRIVATE_ORDER"
                         (t.destination == 'PRIVATE_ORDER' && isSuperAdmin);
                         
    final bool isPending = t.status == TransferStatus.pending || t.status == TransferStatus.awaitingPayment;
    return isMatch && isPending;
  }).toList();

  debugPrint('Transfer Provider: Found ${branchPending.length} pending items for branch [$userBranch] (out of ${transfers.length} total)');
  
  return branchPending;
});

/// A provider that calculates the pending incoming weight for a specific product name
final productPendingWeightProvider = Provider.family<double, String>((ref, productName) {
  final pending = ref.watch(pendingIncomingTransfersProvider);
  
  return pending.where((t) {
    final meatType = t.meatType.toLowerCase();
    final pName = productName.toLowerCase();
    
    // Logic: Product name matches or is part of meat type (e.g. "Beef Steak" matches "Beef - Beef Steak")
    return meatType.contains(pName) || pName.contains(meatType);
  }).fold(0.0, (sum, t) => sum + t.weight);
});
