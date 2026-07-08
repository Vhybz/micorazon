import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/customer_model.dart';
import 'supabase_customer_service.dart';
import 'user_provider.dart';
import 'branch_provider.dart';
import 'sms_service.dart';
import 'offline_sync_service.dart';

class CustomerNotifier extends StateNotifier<List<Customer>> {
  final SupabaseCustomerService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  CustomerNotifier(this._service, this.ref) : super([]) {
    _init();
  }

  void _init() {
    _loadFromCache();
    
    // Watch current user and restart subscription if branch changes
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });

    _startSubscription();
  }

  void _loadFromCache() {
    try {
      final box = Hive.box(OfflineSyncService.customersBoxName);
      if (box.isNotEmpty) {
        final List<Customer> cached = box.values
            .map((json) => Customer.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        state = cached;
        debugPrint('Customer Engine: ${cached.length} customers loaded from local cache.');
      }
    } catch (e) {
      debugPrint('Customer Engine Cache Error: $e');
    }
  }

  void _saveToCache(List<Customer> customers) {
    try {
      final box = Hive.box(OfflineSyncService.customersBoxName);
      box.clear();
      for (var c in customers) {
        box.put(c.id, c.toJson());
      }
    } catch (e) {
      debugPrint('Customer Engine Save Error: $e');
    }
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    final branchCode = user?.branchCode ?? '';

    _subscription = _service.watchCustomers(branchCode).listen((customers) {
      state = customers;
      _saveToCache(customers);
    }, onError: (e) {
      debugPrint('Customer Stream Error: $e');
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> loadCustomers() async {
    _startSubscription();
  }

  Future<Customer?> addCustomer(Customer customer) async {
    final user = ref.read(currentUserProvider);
    final customerWithBranch = customer.copyWith(branchCode: user?.branchCode);

    // 1. Optimistic Update: Add to local state immediately for instant UI response
    state = [...state, customerWithBranch];
    _saveToCache(state);

    // 2. Perform background tasks (Supabase sync & SMS) without blocking the caller
    _syncCustomerAndNotify(customerWithBranch);
    
    return customerWithBranch;
  }

  /// Internal helper to handle network tasks in the background
  Future<void> _syncCustomerAndNotify(Customer customer) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        // Try Supabase
        await _service.addCustomer(customer);
      } else {
        // Queue for later if offline
        await OfflineSyncService.addToQueue(
          actionType: 'CUSTOMER', 
          data: customer.toJson(),
        );
      }
    } catch (e) {
      debugPrint('Customer Sync Background Error: $e');
      // If Supabase fails for other reasons, ensure it's in the offline queue to try again
      await OfflineSyncService.addToQueue(
        actionType: 'CUSTOMER', 
        data: customer.toJson(),
      );
    }
    
    // Welcome SMS (Fire and forget, don't await)
    try {
      final currentBranch = ref.read(currentBranchProvider);
      SmsService.sendCustomerWelcomeSms(
        customer.name, 
        customer.phone, 
        currentBranch?.name
      );
    } catch (_) {}
  }

  Future<void> toggleFavorite(String id) async {
    final customer = state.firstWhere((c) => c.id == id);
    final updatedCustomer = customer.copyWith(isFavorite: !customer.isFavorite);
    
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateCustomer(updatedCustomer);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      await OfflineSyncService.addToQueue(
        actionType: 'CUSTOMER',
        data: updatedCustomer.toJson(),
      );
      state = [for (final c in state) if (c.id == id) updatedCustomer else c];
    }
  }

  Future<void> updateCustomer(Customer customer) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateCustomer(customer);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      await OfflineSyncService.addToQueue(
        actionType: 'CUSTOMER',
        data: customer.toJson(),
      );
      state = [for (final c in state) if (c.id == customer.id) customer else c];
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.deleteCustomer(id);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      await OfflineSyncService.addToQueue(
        actionType: 'DELETE_CUSTOMER',
        data: {'id': id},
      );
      state = state.where((c) => c.id != id).toList();
    }
  }

  Future<void> awardLoyaltyPoints(String customerId, double amount) async {
    try {
      final customer = state.firstWhere((c) => c.id == customerId);
      final pointsEarned = amount / 10.0;
      final updatedCustomer = customer.copyWith(
        loyaltyPoints: customer.loyaltyPoints + pointsEarned,
        visitCount: customer.visitCount + 1,
      );
      
      final connectivity = await Connectivity().checkConnectivity();
      if (!connectivity.contains(ConnectivityResult.none)) {
        await _service.updateCustomer(updatedCustomer);
      } else {
        throw Exception('Offline');
      }
    } catch (e) {
      final customer = state.firstWhere((c) => c.id == customerId);
      final updatedCustomer = customer.copyWith(
        loyaltyPoints: customer.loyaltyPoints + (amount / 10.0),
        visitCount: customer.visitCount + 1,
      );
      await OfflineSyncService.addToQueue(
        actionType: 'CUSTOMER',
        data: updatedCustomer.toJson(),
      );
      state = [for (final c in state) if (c.id == customerId) updatedCustomer else c];
    }
  }
}

final customerServiceProvider = Provider<SupabaseCustomerService>((ref) {
  return SupabaseCustomerService();
});

final customerProvider = StateNotifierProvider<CustomerNotifier, List<Customer>>((ref) {
  return CustomerNotifier(ref.watch(customerServiceProvider), ref);
});
