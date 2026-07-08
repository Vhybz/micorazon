import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/butcher_models.dart';
import 'supabase_butcher_service.dart';
import 'user_provider.dart';
import 'offline_sync_service.dart';
import 'audit_service.dart';

class SlaughterLogNotifier extends StateNotifier<AsyncValue<List<SlaughterLog>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  Timer? _heartbeat;
  
  final Set<String> _pendingSyncIds = {};
  final List<SlaughterLog> _localItems = [];
  final Map<String, SlaughterStatus> _statusOverrides = {};

  SlaughterLogNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) loadLogs(silent: true);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        loadLogs();
      }
    });
    loadLogs();
  }

  Future<void> loadLogs({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final branchCode = user?.branchCode;
    
    if (branchCode == null) {
      if (user == null && !silent) {
        state = const AsyncValue.loading();
      } else {
        if (!silent) state = const AsyncValue.data([]);
      }
      return;
    }
    
    try {
      if (!silent && !state.hasValue) state = const AsyncValue.loading();
      
      final remoteLogs = await _service.getSlaughterLogs(branchCode);
      
      final pendingIntakes = OfflineSyncService.getPendingItems('INTAKE')
          .map((json) {
            try { return SlaughterLog.fromJson(json); } catch (e) { return null; }
          })
          .whereType<SlaughterLog>()
          .where((l) => l.branchCode == branchCode);
          
      final pendingUpdates = OfflineSyncService.getPendingItems('UPDATE_SLAUGHTER')
          .map((json) {
            try { return SlaughterLog.fromJson(json); } catch (e) { return null; }
          })
          .whereType<SlaughterLog>()
          .where((l) => l.branchCode == branchCode);
      
      final remoteIds = remoteLogs.map((l) => l.id).toSet();
      final remoteTags = remoteLogs.map((l) => l.tagNumber).whereType<String>().toSet();
      
      _pendingSyncIds.removeWhere((id) => remoteIds.contains(id));
      _localItems.removeWhere((l) => remoteIds.contains(l.id) || (l.tagNumber != null && remoteTags.contains(l.tagNumber)));
      
      final Map<String, SlaughterLog> allLogs = {};
      for (var log in remoteLogs) {
        allLogs[log.id] = log;
      }
      for (var log in pendingIntakes) {
        if (!allLogs.containsKey(log.id)) allLogs[log.id] = log;
      }
      for (var log in pendingUpdates) {
        allLogs[log.id] = log;
      }

      final mergedLogs = allLogs.values.map((log) {
        if (_statusOverrides.containsKey(log.id)) {
          final localStatus = _statusOverrides[log.id]!;
          if (log.status.index >= localStatus.index) {
            _statusOverrides.remove(log.id);
            return log;
          }
          return log.copyWith(status: localStatus);
        }
        return log;
      }).toList();

      mergedLogs.sort((a, b) {
        if (a.status != b.status) return a.status.index.compareTo(b.status.index);
        return (b.slaughterTime ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.slaughterTime ?? DateTime.fromMillisecondsSinceEpoch(0));
      });

      state = AsyncValue.data(mergedLogs);
    } catch (e) {
      if (!silent) state = AsyncValue.error(e, StackTrace.current);
      debugPrint('Load Logs Error: $e');
    }
  }

  Future<void> addLog(SlaughterLog log) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned to user');
      final logWithBranch = log.copyWith(branchCode: branchCode);
      
      await OfflineSyncService.addToQueue(
        actionType: 'INTAKE', 
        data: logWithBranch.toJson(),
      );

      await AuditService.log(
        ref: ref, 
        action: 'INTAKE_CREATED', 
        entityType: 'SLAUGHTER_LOG', 
        entityId: logWithBranch.id,
        newData: logWithBranch.toJson(),
      );

      _pendingSyncIds.add(logWithBranch.id);
      _localItems.insert(0, logWithBranch);

      final currentData = state.value ?? [];
      state = AsyncValue.data([..._localItems, ...currentData.where((l) => !_pendingSyncIds.contains(l.id))]);
    } catch (e) {
      debugPrint('Error adding slaughter log (Queue): $e');
    }
  }

  Future<void> queueAnimalRecord({
    required String animalUuid,
    required String tagNumber,
    String? manualFarmTag,
    required AnimalType type,
    required double weight,
    double? price,
    double? farmPrice,
    required String sourceFarm,
    required String branchCode,
  }) async {
    final Map<String, dynamic> animalData = {
      'id': animalUuid,
      'tag_number': tagNumber,
      'manual_farm_tag': manualFarmTag,
      'branch_code': branchCode,
      'type': type.name,
      'weight': weight,
      'purchase_price': farmPrice ?? price, 
      'source_farm': sourceFarm,
      'status': 'waiting',
      'arrival_time': DateTime.now().toIso8601String(),
    };

    await OfflineSyncService.addToQueue(
      actionType: 'ANIMAL',
      data: animalData,
    );
  }

  Future<void> updateStatus(String id, SlaughterStatus status) async {
    try {
      final logs = state.value ?? [];
      final logIndex = logs.indexWhere((l) => l.id == id);
      if (logIndex == -1) return;
      
      final log = logs[logIndex];
      final time = (status == SlaughterStatus.slaughtering || status == SlaughterStatus.completed) 
          ? DateTime.now() 
          : log.slaughterTime;
      
      final updatedLog = log.copyWith(
        status: status,
        slaughterTime: time,
      );

      _statusOverrides[id] = status;
      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_SLAUGHTER',
        data: updatedLog.toJson(),
      );

      state = AsyncValue.data([
        for (final l in (state.value ?? []))
          if (l.id == id) updatedLog else l
      ]);
      
      Future.delayed(const Duration(seconds: 2), () => loadLogs(silent: true));

      if (status == SlaughterStatus.completed) {
        ref.read(meatBatchesProvider.notifier).loadBatches(silent: true);
      }
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  Future<void> updateSlaughterRecord(SlaughterLog log) async {
    try {
      _statusOverrides[log.id] = log.status;
      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_SLAUGHTER', 
        data: log.toJson(),
      );

      final currentLogs = state.value ?? [];
      state = AsyncValue.data([
        for (final l in currentLogs)
          if (l.id == log.id) log else l
      ]);
      
      final localIdx = _localItems.indexWhere((l) => l.id == log.id);
      if (localIdx != -1) _localItems[localIdx] = log;

    } catch (e) {
      debugPrint('Error updating slaughter record: $e');
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
  Timer? _heartbeat;

  final Set<String> _pendingSyncIds = {};
  final List<MeatBatch> _localItems = [];

  MeatBatchNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) loadBatches(silent: true);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        loadBatches();
      }
    });
    loadBatches();
  }

  Future<void> loadBatches({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final branchCode = user?.branchCode;
    
    if (branchCode == null) {
      if (user == null && !silent) {
        state = const AsyncValue.loading();
      } else {
        if (!silent) state = const AsyncValue.data([]);
      }
      return;
    }
    
    try {
      if (!silent && !state.hasValue) state = const AsyncValue.loading();
      
      final remoteBatches = await _service.getActiveBatches(branchCode);
      
      final pendingCreates = OfflineSyncService.getPendingItems('CREATE_BATCH')
          .map((json) {
            try { return MeatBatch.fromJson(json); } catch (e) { return null; }
          })
          .whereType<MeatBatch>()
          .where((b) => b.branchCode == branchCode);
          
      final pendingUpdates = OfflineSyncService.getPendingItems('UPDATE_BATCH')
          .map((json) {
            try { return MeatBatch.fromJson(json); } catch (e) { return null; }
          })
          .whereType<MeatBatch>()
          .where((b) => b.branchCode == branchCode);

      final Map<String, MeatBatch> allBatches = {};
      for (var b in remoteBatches) {
        allBatches[b.id] = b;
      }
      for (var b in pendingCreates) {
        if (!allBatches.containsKey(b.id)) allBatches[b.id] = b;
      }
      for (var b in pendingUpdates) {
        allBatches[b.id] = b;
      }

      final merged = allBatches.values.where((b) => b.status != 'completed').toList();
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      state = AsyncValue.data(merged);
    } catch (e) {
      if (!silent) state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> addBatch(MeatBatch batch) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned to user');
      final batchWithBranch = batch.copyWith(branchCode: branchCode);
      
      await OfflineSyncService.addToQueue(
        actionType: 'CREATE_BATCH', 
        data: batchWithBranch.toJson(),
      );

      await AuditService.log(
        ref: ref,
        action: 'BATCH_CREATED',
        entityType: 'MEAT_BATCH',
        entityId: batchWithBranch.id,
        newData: batchWithBranch.toJson(),
      );

      _pendingSyncIds.add(batchWithBranch.id);
      _localItems.insert(0, batchWithBranch);

      final currentData = state.value ?? [];
      state = AsyncValue.data([..._localItems, ...currentData.where((b) => !_pendingSyncIds.contains(b.id))]);
    } catch (e) {
      debugPrint('Error adding meat batch: $e');
    }
  }

  Future<void> receiveCarcass(SlaughterLog log, String receivedBy) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned');

      final updatedBatch = MeatBatch(
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
      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_SLAUGHTER', 
        data: updatedLog.toJson(),
      );

      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_BATCH', 
        data: updatedBatch.toJson(),
      );

      _pendingSyncIds.add(updatedBatch.id);
      _localItems.removeWhere((b) => b.id == updatedBatch.id);
      _localItems.insert(0, updatedBatch);

      final currentData = state.value ?? [];
      state = AsyncValue.data([..._localItems, ...currentData.where((b) => !_pendingSyncIds.contains(b.id))]);

      ref.read(slaughterLogsProvider.notifier).updateSlaughterRecord(updatedLog);
    } catch (e) {
      debugPrint('Error receiving carcass: $e');
    }
  }

  Future<void> updateBatchProcessingStatus(String id, MeatBatchStatus status) async {
    try {
      final batches = state.value ?? [];
      final batchIndex = batches.indexWhere((b) => b.id == id);
      if (batchIndex == -1) return;
      
      final updatedBatch = batches[batchIndex].copyWith(status: status.name);

      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_BATCH',
        data: updatedBatch.toJson(),
      );

      final existingLocalIndex = _localItems.indexWhere((b) => b.id == id);
      if (existingLocalIndex != -1) {
        _localItems[existingLocalIndex] = updatedBatch;
      } else {
        _localItems.add(updatedBatch);
      }

      state = AsyncValue.data([
        for (final b in (state.value ?? []))
          if (b.id == id) updatedBatch else b
      ]);
    } catch (e) {
      debugPrint('Error updating batch status: $e');
    }
  }

  Future<void> closeBatch(String id) async {
    try {
      final batches = state.value ?? [];
      final batchIndex = batches.indexWhere((b) => b.id == id);
      if (batchIndex == -1) return;
      
      final updatedBatch = batches[batchIndex].copyWith(status: 'completed');

      await OfflineSyncService.addToQueue(
        actionType: 'UPDATE_BATCH',
        data: updatedBatch.toJson(),
      );

      _localItems.removeWhere((b) => b.id == id);
      _pendingSyncIds.remove(id);

      state = AsyncValue.data((state.value ?? []).where((b) => b.id != id).toList());
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

      _pendingSyncIds.add(batch.id);
      _localItems.removeWhere((b) => b.id == batch.id);
      _localItems.insert(0, batch);
      
      state = AsyncValue.data([..._localItems, ...(state.value ?? []).where((b) => !_pendingSyncIds.contains(b.id))]);

      await OfflineSyncService.addToQueue(
        actionType: 'CREATE_BATCH',
        data: batch.toJson(),
      );

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
}

final activeBatchesProvider = StateNotifierProvider<MeatBatchNotifier, AsyncValue<List<MeatBatch>>>((ref) {
  return MeatBatchNotifier(ref.watch(butcherServiceProvider), ref);
});

final meatBatchesProvider = activeBatchesProvider;

class MeatCutNotifier extends StateNotifier<AsyncValue<List<MeatCut>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  Timer? _heartbeat;

  final Set<String> _pendingSyncIds = {};
  final List<MeatCut> _localItems = [];

  MeatCutNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) loadCuts(silent: true);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        loadCuts();
      }
    });
    loadCuts();
  }

  Future<void> loadCuts({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final branchCode = user?.branchCode;
    
    if (branchCode == null) {
      if (user == null && !silent) {
        state = const AsyncValue.loading();
      } else {
        if (!silent) state = const AsyncValue.data([]);
      }
      return;
    }
    
    try {
      if (!silent && !state.hasValue) state = const AsyncValue.loading();
      
      final remoteCuts = await _service.getRecentCuts(branchCode);
      
      final pendingCuts = OfflineSyncService.getPendingItems('CUT')
          .map((json) {
            try { return MeatCut.fromJson(json); } catch (e) { return null; }
          })
          .whereType<MeatCut>()
          .where((c) => c.branchCode == branchCode);

      final Map<String, MeatCut> allCuts = {};
      for (var c in remoteCuts) {
        allCuts[c.id] = c;
      }
      for (var c in pendingCuts) {
        if (!allCuts.containsKey(c.id)) allCuts[c.id] = c;
      }

      final merged = allCuts.values.toList();
      merged.sort((a, b) => b.processedAt.compareTo(a.processedAt));

      state = AsyncValue.data(merged);
    } catch (e) {
      if (!silent) state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> addCut(MeatCut cut) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned to user');
      final cutWithBranch = cut.copyWith(branchCode: branchCode);
      
      await OfflineSyncService.addToQueue(
        actionType: 'CUT', 
        data: cutWithBranch.toJson(),
      );

      _pendingSyncIds.add(cutWithBranch.id);
      _localItems.insert(0, cutWithBranch);

      final currentData = state.value ?? [];
      state = AsyncValue.data([..._localItems, ...currentData.where((c) => !_pendingSyncIds.contains(c.id))]);
    } catch (e) {
      debugPrint('Error adding meat cut: $e');
    }
  }

  Future<void> addCuts(List<MeatCut> cuts) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      if (branchCode == null) throw Exception('No branch code assigned to user');
      
      final cutsWithBranch = cuts.map((c) => c.copyWith(branchCode: branchCode)).toList();
      for (var cut in cutsWithBranch) {
        await OfflineSyncService.addToQueue(
          actionType: 'CUT', 
          data: cut.toJson(),
        );
        _pendingSyncIds.add(cut.id);
        _localItems.insert(0, cut);
      }
      
      final currentData = state.value ?? [];
      state = AsyncValue.data([..._localItems, ...currentData.where((c) => !_pendingSyncIds.contains(c.id))]);
    } catch (e) {
      debugPrint('Error adding multiple cuts: $e');
    }
  }

  Future<void> updateCutWeight(String id, double newWeight) async {
    try {
      final cuts = state.value ?? [];
      final index = cuts.indexWhere((c) => c.id == id);
      if (index == -1) return;

      final updatedCut = cuts[index].copyWith(weight: newWeight);

      await OfflineSyncService.addToQueue(
        actionType: 'CUT', 
        data: updatedCut.toJson(),
      );

      state = AsyncValue.data([
        for (final c in cuts)
          if (c.id == id) updatedCut else c
      ]);
    } catch (e) {
      debugPrint('Error updating cut weight: $e');
    }
  }

  Future<void> deleteCut(String id) async {
    try {
      await OfflineSyncService.addToQueue(
        actionType: 'DELETE_CUT',
        data: {'id': id},
      );
      state.whenData((cuts) {
        state = AsyncValue.data(cuts.where((c) => c.id != id).toList());
      });
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
  Timer? _heartbeat;

  ButcherWasteNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) loadWaste(silent: true);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        loadWaste();
      }
    });
    loadWaste();
  }

  Future<void> loadWaste({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final branchCode = user?.branchCode;
    
    if (branchCode == null) {
      if (user == null && !silent) {
        state = const AsyncValue.loading();
      } else {
        if (!silent) state = const AsyncValue.data([]);
      }
      return;
    }

    try {
      if (!silent) state = const AsyncValue.loading();
      final waste = await _service.getWaste(branchCode);
      state = AsyncValue.data(waste);
    } catch (e) {
      if (!silent) state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> addWaste(String batchId, String reason, double weight) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      final code = branchCode ?? 'GLOBAL';
      
      final Map<String, dynamic> wasteData = {
        'branch_code': code,
        'batch_id': batchId,
        'reason': reason,
        'weight': weight,
        'recorded_at': DateTime.now().toIso8601String(),
      };

      await OfflineSyncService.addToQueue(
        actionType: 'WASTE', 
        data: wasteData,
      );

      await AuditService.log(
        ref: ref,
        action: 'WASTE_RECORDED',
        entityType: 'BUTCHER_WASTE',
        newData: wasteData,
      );

      loadWaste(silent: true); 
    } catch (e) {
      debugPrint('Error adding waste (Queue): $e');
    }
  }
}

final butcherWasteProvider = StateNotifierProvider<ButcherWasteNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  return ButcherWasteNotifier(ref.watch(butcherServiceProvider), ref);
});

class ButcherOrderNotifier extends StateNotifier<AsyncValue<List<ButcherOrder>>> {
  final SupabaseButcherService _service;
  final Ref ref;
  Timer? _heartbeat;

  ButcherOrderNotifier(this._service, this.ref) : super(const AsyncValue.loading()) {
    _init();
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) loadOrders(silent: true);
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }

  void _init() {
    ref.listen(currentUserProvider, (previous, next) {
      if (next?.branchCode != previous?.branchCode) {
        loadOrders();
      }
    });
    loadOrders();
  }

  Future<void> loadOrders({bool silent = false}) async {
    final user = ref.read(currentUserProvider);
    final branchCode = user?.branchCode;
    
    if (branchCode == null) {
      if (user == null && !silent) {
        state = const AsyncValue.loading();
      } else {
        if (!silent) state = const AsyncValue.data([]);
      }
      return;
    }

    try {
      if (!silent) state = const AsyncValue.loading();
      final orders = await _service.getButcherOrders(branchCode);
      state = AsyncValue.data(orders);
    } catch (e) {
      if (!silent) state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> updateStatus(String id, ButcherOrderStatus status) async {
    try {
      await _service.updateButcherOrderStatus(id, status);
      state.whenData((orders) {
        state = AsyncValue.data([
          for (final order in orders)
            if (order.id == id) order.copyWith(status: status) else order
        ]);
      });
    } catch (e) {
      debugPrint('Error updating order status: $e');
    }
  }

  Future<void> addOrder(ButcherOrder order) async {
    try {
      final branchCode = ref.read(currentUserProvider)?.branchCode;
      final orderWithBranch = order.copyWith(branchCode: branchCode);
      await _service.addButcherOrder(orderWithBranch);
      state.whenData((orders) {
        state = AsyncValue.data([orderWithBranch, ...orders]);
      });
    } catch (e) {
      debugPrint('Error adding butcher order: $e');
      rethrow;
    }
  }
}

final butcherOrdersProvider = StateNotifierProvider<ButcherOrderNotifier, AsyncValue<List<ButcherOrder>>>((ref) {
  return ButcherOrderNotifier(ref.watch(butcherServiceProvider), ref);
});
