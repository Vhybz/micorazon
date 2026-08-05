import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/butcher_models.dart';
import 'supabase_butcher_service.dart';
import 'user_provider.dart';
import 'audit_service.dart';
import 'product_service.dart';
import '../models/product.dart';
import '../core/supabase_config.dart';

class SlaughterLogNotifier extends StateNotifier<AsyncValue<List<SlaughterLog>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  SlaughterLogNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user?.branchCode != null) {
      _subscription = _service.watchSlaughterLogs(user!.branchCode!).listen(
        (logs) => state = AsyncValue.data(logs),
        onError: (e, st) {
          debugPrint('Slaughter Logs Stream Error (Resuming?): $e');
          // Don't update state to error to avoid red screen, just log it.
        },
        cancelOnError: false,
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> loadLogs({bool silent = false}) async {
    _startSubscription();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addLog(SlaughterLog log) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned');
      final logWithBranch = log.copyWith(branchCode: branchCode);
      
      await _service.addSlaughterLog(logWithBranch);
      await AuditService.log(
        ref: ref, 
        action: 'INTAKE_CREATED', 
        entityType: 'SLAUGHTER_LOG', 
        entityId: logWithBranch.id,
        newData: logWithBranch.toJson(),
      );
    } catch (e) {
      debugPrint('Error adding slaughter log: $e');
    }
  }

  Future<void> updateStatus(String id, SlaughterStatus status) async {
    try {
      final user = ref.read(currentUserProvider);
      final time = (status == SlaughterStatus.slaughtering || status == SlaughterStatus.completed) 
          ? DateTime.now() 
          : null;
      
      String? slaughteredBy;
      if (status == SlaughterStatus.completed) {
        slaughteredBy = user?.name;
      }

      await _service.updateSlaughterStatus(id, status, time: time, slaughteredBy: slaughteredBy);

      await AuditService.log(
        ref: ref,
        action: 'SLAUGHTER_STATUS_UPDATED',
        entityType: 'SLAUGHTER_LOG',
        entityId: id,
        newData: {
          'new_status': status.name,
          'butcher': slaughteredBy,
        },
      );
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  Future<void> updateSlaughterRecord(SlaughterLog log) async {
    try {
      await _service.updateSlaughterLog(log);
    } catch (e) {
      debugPrint('Error updating slaughter record: $e');
    }
  }

  Future<void> queueAnimalRecord({
    required String animalUuid,
    required String tagNumber,
    String? manualFarmTag,
    required AnimalType type,
    int quantity = 1,
    required double weight,
    double? price,
    double? farmPrice,
    required String sourceFarm,
    required String branchCode,
  }) async {
    await _service.addAnimal(
      branchCode, 
      animalUuid, 
      tagNumber, 
      type, 
      weight, 
      sourceFarm, 
      quantity: quantity,
      price: price,
      manualFarmTag: manualFarmTag,
    );
  }

  Future<void> updateIntake({
    required SlaughterLog log,
    required String sourceFarm,
  }) async {
    try {
      await _service.updateSlaughterLog(log);
      await _service.updateAnimal(
        log.animalId,
        tagNumber: log.tagNumber,
        manualFarmTag: log.manualFarmTag,
        type: log.type,
        quantity: log.quantity,
        weight: log.liveWeight,
        price: log.price,
        sourceFarm: sourceFarm,
      );
      
      await AuditService.log(
        ref: ref,
        action: 'INTAKE_UPDATED',
        entityType: 'SLAUGHTER_LOG',
        entityId: log.id,
        newData: log.toJson(),
      );
    } catch (e) {
      debugPrint('Error updating intake: $e');
      rethrow;
    }
  }

  Future<void> deleteIntake(SlaughterLog log) async {
    try {
      await _service.deleteSlaughterIntake(log.id, log.animalId);
      
      await AuditService.log(
        ref: ref,
        action: 'INTAKE_DELETED',
        entityType: 'SLAUGHTER_LOG',
        entityId: log.id,
        oldData: log.toJson(),
      );
    } catch (e) {
      debugPrint('Error deleting intake: $e');
      rethrow;
    }
  }

  Future<void> finalizeChickenAsWhole(SlaughterLog log) async {
    try {
      final products = ref.read(productsFutureProvider).value ?? [];
      
      final type = log.type == AnimalType.softChicken ? 'Soft' : 'Hard';
      final range = log.chickenRangeLabel ?? '';

      if (range.isEmpty) {
        throw Exception('Weight range is missing for this chicken batch. Please Edit the intake record to select a range before finalizing.');
      }

      // Find the specific card that matches type (Soft/Hard), "Whole Chicken", and Range
      final product = products.where((p) => 
        p.name.contains(type) && 
        p.name.contains('Whole Chicken') && 
        p.name.contains(range)
      ).firstOrNull;

      if (product != null) {
        final user = ref.read(currentUserProvider);
        // ATOMIC Update: Use database function
        await SupabaseConfig.client.rpc('increment_stock', params: {
          'p_id': product.id,
          'p_amount': log.quantity.toDouble(),
        });
        
        // Mark log as processed
        final updatedLog = log.copyWith(
          status: SlaughterStatus.processed,
          slaughterTime: DateTime.now(),
          portionedBy: user?.name,
        );
        await updateSlaughterRecord(updatedLog);

        await AuditService.log(
          ref: ref,
          action: 'CHICKEN_FINALIZED_AS_WHOLE',
          entityType: 'SLAUGHTER_LOG',
          entityId: log.id,
          newData: {
            'added_quantity': log.quantity, 
            'product_id': product.id, 
            'range': range,
            'portioner': user?.name,
          },
        );
      } else {
        throw Exception('Matching Whole Chicken product not found for range $range');
      }
    } catch (e) {
      debugPrint('Error finalizing whole chicken: $e');
      rethrow;
    }
  }
}

final butcherServiceProvider = Provider<SupabaseButcherService>((ref) => SupabaseButcherService());

final slaughterLogsProvider = StateNotifierProvider<SlaughterLogNotifier, AsyncValue<List<SlaughterLog>>>((ref) {
  return SlaughterLogNotifier(ref.watch(butcherServiceProvider), ref);
});

class MeatBatchNotifier extends StateNotifier<AsyncValue<List<MeatBatch>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  MeatBatchNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user?.branchCode != null) {
      _subscription = _service.watchActiveBatches(user!.branchCode!).listen(
        (batches) => state = AsyncValue.data(batches),
        onError: (e, st) {
          debugPrint('Meat Batches Stream Error: $e');
        },
        cancelOnError: false,
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> loadBatches({bool silent = false}) async {
    _startSubscription();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addBatch(MeatBatch batch) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned');
      await _service.addMeatBatch(batch.copyWith(branchCode: branchCode));
    } catch (e) {
      debugPrint('Error adding meat batch: $e');
    }
  }

  Future<void> updateBatchProcessingStatus(String id, MeatBatchStatus status) async {
    try {
      await _service.updateBatchStatus(id, status.name);
    } catch (e) {
      debugPrint('Error updating batch status: $e');
    }
  }

  Future<void> closeBatch(String id) async {
    try {
      await _service.updateBatchStatus(id, 'completed');
    } catch (e) {
      debugPrint('Error closing batch: $e');
    }
  }

  Future<void> initiateBatchFromSlaughter({
    required SlaughterLog log,
    required double totalCarcassWeight,
    required List<MeatCut> cuts,
    required double waste,
  }) async {
    try {
      final user = ref.read(currentUserProvider);
      final branchCode = user?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned');

      final batch = MeatBatch(
        id: log.id,
        branchCode: branchCode,
        animalId: log.animalId,
        meatType: log.type.displayName,
        weight: totalCarcassWeight,
        costPrice: log.farmPrice ?? 0.0,
        createdAt: DateTime.now(),
        status: MeatBatchStatus.preparing.name,
        source: BatchSource(
          name: 'Direct Slaughter',
          location: branchCode,
          owner: 'Mi~Corazon',
        ),
        portionedBy: user?.name,
      );

      await _service.addMeatBatch(batch);

      // Inventory Integration: Update Shop Stock for each cut
      final products = ref.read(productsFutureProvider).value ?? [];
      final range = log.chickenRangeLabel ?? '';
      final isChicken = log.type == AnimalType.softChicken || log.type == AnimalType.hardChicken;

      for (final cut in cuts) {
        await ref.read(recentCutsProvider.notifier).addCut(cut);

        // Map cut back to Shop Product
        Product? targetProduct;
        if (isChicken) {
          if (range.isEmpty) {
            throw Exception('Weight range is missing for this chicken batch. Please Edit the intake record to select a range before portioning.');
          }
          final catMatch = log.type == AnimalType.softChicken ? 'SOFT CHICKEN (BROILER)' : 'HARD CHICKEN (LAYER)';
          targetProduct = products.where((p) => 
            p.category.toUpperCase().contains(catMatch) && 
            p.name.contains(cut.name) && 
            p.name.contains(range)
          ).firstOrNull;
        } else {
          // Standard Meat mapping (Cow/Goat/Pork etc)
          final bool isCow = log.type == AnimalType.cow || log.type == AnimalType.bull;
          
          targetProduct = products.where((p) {
            final pCat = p.category.toUpperCase();
            final cutName = cut.name.toUpperCase();
            
            if (isCow) {
              final bool isCowPart = cutName.contains('HEAD') || cutName.contains('FEET') || cutName.contains('OFFAL');
              final String targetCat = isCowPart ? 'COW' : 'BEEF';
              // Check for either the target category or legacy 'COW' (since we're transitioning)
              return (pCat == targetCat || pCat == 'COW' || pCat == 'BEEF') && p.name.contains(cut.name);
            }
            
            return pCat == log.type.name.toUpperCase() && p.name.contains(cut.name);
          }).firstOrNull;
        }

        if (targetProduct != null) {
          await SupabaseConfig.client.rpc('increment_stock', params: {
            'p_id': targetProduct.id,
            'p_amount': cut.weight,
          });
        }
      }

      if (waste > 0) {
        await ref.read(butcherWasteProvider.notifier).addWaste(log.id, 'Slaughter Waste/Bones', waste);
      }

      final updatedLog = log.copyWith(
        status: SlaughterStatus.processed,
        meatWeight: totalCarcassWeight,
        slaughterTime: DateTime.now(),
        portionedBy: user?.name,
      );
      
      await ref.read(slaughterLogsProvider.notifier).updateSlaughterRecord(updatedLog);

      await AuditService.log(
        ref: ref,
        action: 'SLAUGHTER_FINALIZED_PORTIONED',
        entityType: 'SLAUGHTER_LOG',
        entityId: log.id,
        newData: {
          'cuts_count': cuts.length, 
          'total_weight': totalCarcassWeight,
          'portioner': user?.name,
        },
      );
    } catch (e) {
      debugPrint('Error initiating batch: $e');
      rethrow;
    }
  }

  Future<void> receiveCarcass(SlaughterLog log, String receivedBy) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned');

      final batch = MeatBatch(
        id: log.id,
        branchCode: branchCode,
        animalId: log.animalId,
        meatType: log.type.displayName,
        weight: log.meatWeight,
        costPrice: log.farmPrice ?? 0.0,
        createdAt: DateTime.now(),
        status: MeatBatchStatus.preparing.name,
        source: BatchSource(name: 'Direct Slaughter', location: branchCode, owner: 'Mi~Corazon'),
        receivedBy: receivedBy,
      );

      final updatedLog = log.copyWith(status: SlaughterStatus.processed);
      await _service.updateSlaughterLog(updatedLog);
      await _service.addMeatBatch(batch);
    } catch (e) {
      debugPrint('Error receiving carcass: $e');
    }
  }
}

final activeBatchesProvider = StateNotifierProvider<MeatBatchNotifier, AsyncValue<List<MeatBatch>>>((ref) {
  return MeatBatchNotifier(ref.watch(butcherServiceProvider), ref);
});

final meatBatchesProvider = activeBatchesProvider;

class MeatCutNotifier extends StateNotifier<AsyncValue<List<MeatCut>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  MeatCutNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user?.branchCode != null) {
      _subscription = _service.watchRecentCuts(user!.branchCode!).listen(
        (cuts) => state = AsyncValue.data(cuts),
        onError: (e, st) {
          debugPrint('Recent Cuts Stream Error: $e');
        },
        cancelOnError: false,
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> loadCuts({bool silent = false}) async {
    _startSubscription();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addCut(MeatCut cut) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned');
      await _service.addMeatCut(cut.copyWith(branchCode: branchCode));
    } catch (e) {
      debugPrint('Error adding meat cut: $e');
    }
  }

  Future<void> addCuts(List<MeatCut> cuts) async {
    try {
      for (var cut in cuts) {
        await addCut(cut);
      }
    } catch (e) {
      debugPrint('Error adding multiple cuts: $e');
    }
  }

  Future<void> updateCutWeight(String id, double newWeight) async {
    try {
      final cuts = state.value ?? [];
      final cut = cuts.firstWhere((c) => c.id == id);
      await _service.addMeatCut(cut.copyWith(weight: newWeight));
    } catch (e) {
      debugPrint('Error updating cut weight: $e');
    }
  }

  Future<void> deleteCut(String id) async {
    try {
      // Need delete method in service
      debugPrint('Delete cut $id requested');
    } catch (e) {
      debugPrint('Error deleting cut: $e');
    }
  }
}

final recentCutsProvider = StateNotifierProvider<MeatCutNotifier, AsyncValue<List<MeatCut>>>((ref) {
  return MeatCutNotifier(ref.watch(butcherServiceProvider), ref);
});

class ButcherWasteNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  ButcherWasteNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user?.branchCode != null) {
      _subscription = _service.watchWaste(user!.branchCode!).listen(
        (waste) => state = AsyncValue.data(waste),
        onError: (e, st) {
          debugPrint('Waste Stream Error: $e');
        },
        cancelOnError: false,
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  Future<void> loadWaste({bool silent = false}) async {
    _startSubscription();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> addWaste(String batchId, String reason, double weight) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) return;
      await _service.addWaste(branchCode, batchId, reason, weight);
    } catch (e) {
      debugPrint('Error adding waste: $e');
    }
  }
}

final butcherWasteProvider = StateNotifierProvider<ButcherWasteNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return ButcherWasteNotifier(ref.watch(butcherServiceProvider), ref);
});

class ButcherOrderNotifier extends StateNotifier<AsyncValue<List<ButcherOrder>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  StreamSubscription? _subscription;

  ButcherOrderNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        _startSubscription();
      }
    });
    _startSubscription();
  }

  void _startSubscription() {
    _subscription?.cancel();
    final user = ref.read(currentUserProvider);
    if (user?.branchCode != null) {
      _subscription = _service.watchButcherOrders(user!.branchCode!).listen(
        (orders) => state = AsyncValue.data(orders),
        onError: (e, st) {
          debugPrint('Butcher Orders Stream Error: $e');
        },
        cancelOnError: false,
      );
    } else {
      state = const AsyncValue.data([]);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> updateStatus(String id, ButcherOrderStatus status) async {
    try {
      await _service.updateButcherOrderStatus(id, status);
    } catch (e) {
      debugPrint('Error updating order status: $e');
    }
  }

  Future<void> addOrder(ButcherOrder order) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      final orderWithBranch = order.copyWith(branchCode: branchCode);
      await _service.addButcherOrder(orderWithBranch);
    } catch (e) {
      debugPrint('Error adding butcher order: $e');
      rethrow;
    }
  }
}

final butcherOrdersProvider = StateNotifierProvider<ButcherOrderNotifier, AsyncValue<List<ButcherOrder>>>((ref) {
  return ButcherOrderNotifier(ref.watch(butcherServiceProvider), ref);
});
