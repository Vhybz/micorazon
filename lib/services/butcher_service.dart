import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/butcher_models.dart';
import 'supabase_butcher_service.dart';
import 'user_provider.dart';
import 'audit_service.dart';

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
      final time = (status == SlaughterStatus.slaughtering || status == SlaughterStatus.completed) 
          ? DateTime.now() 
          : null;
      await _service.updateSlaughterStatus(id, status, time: time);
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
    await _service.addAnimal(branchCode, animalUuid, tagNumber, type, weight, sourceFarm, quantity: quantity);
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
      final branchCode = ref.read(currentUserProvider)?.branchCode;
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
      );

      await _service.addMeatBatch(batch);

      for (final cut in cuts) {
        await ref.read(recentCutsProvider.notifier).addCut(cut);
      }

      if (waste > 0) {
        await ref.read(butcherWasteProvider.notifier).addWaste(log.id, 'Slaughter Waste/Bones', waste);
      }

      final updatedLog = log.copyWith(
        status: SlaughterStatus.processed,
        meatWeight: totalCarcassWeight,
        slaughterTime: DateTime.now(),
      );
      
      await ref.read(slaughterLogsProvider.notifier).updateSlaughterRecord(updatedLog);
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
