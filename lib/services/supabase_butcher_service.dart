import '../models/butcher_models.dart';
import '../core/supabase_config.dart';

class SupabaseButcherService {
  final _client = SupabaseConfig.client;

  Future<List<SlaughterLog>> getSlaughterLogs(String branchCode) async {
    final response = await _client
        .from('slaughter_logs')
        .select('*, animals(tag_number)')
        .eq('branch_code', branchCode)
        .order('slaughter_time', ascending: false, nullsFirst: true);
    
    return (response as List).map((json) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(json);
      if (data['animals'] != null) {
        data['tag_number'] = data['animals']['tag_number'];
      }
      return SlaughterLog.fromJson(data);
    }).toList();
  }

  Stream<List<SlaughterLog>> watchSlaughterLogs(String branchCode) {
    return _client
        .from('slaughter_logs')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('slaughter_time', ascending: false)
        .map((data) => data.map((json) => SlaughterLog.fromJson(json)).toList());
  }

  Future<void> addAnimal(String branchCode, String animalUuid, String tagNumber, AnimalType type, double weight, String sourceFarm, {int quantity = 1}) async {
    await _client.from('animals').insert({
      'id': animalUuid,
      'tag_number': tagNumber,
      'branch_code': branchCode,
      'type': type.name,
      'quantity': quantity,
      'weight': weight,
      'source_farm': sourceFarm,
      'status': 'waiting',
      'arrival_time': DateTime.now().toIso8601String(),
    });
  }

  Future<void> addSlaughterLog(SlaughterLog log) async {
    await _client.from('slaughter_logs').insert(log.toJson());
  }

  Future<void> updateSlaughterLog(SlaughterLog log) async {
    await _client
        .from('slaughter_logs')
        .update(log.toJson())
        .eq('id', log.id);
  }

  Future<void> updateSlaughterStatus(String id, SlaughterStatus status, {DateTime? time}) async {
    final Map<String, dynamic> updateData = {
      'status': status.name,
    };
    if (time != null) {
      updateData['slaughter_time'] = time.toIso8601String();
    }
    await _client
        .from('slaughter_logs')
        .update(updateData)
        .eq('id', id);
  }

  Future<List<MeatBatch>> getActiveBatches(String branchCode) async {
    final response = await _client
        .from('meat_batches')
        .select()
        .eq('branch_code', branchCode)
        .neq('status', 'completed')
        .order('created_at', ascending: false);
    
    return (response as List).map((json) => MeatBatch.fromJson(json)).toList();
  }

  Stream<List<MeatBatch>> watchActiveBatches(String branchCode) {
    return _client
        .from('meat_batches')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('created_at', ascending: false)
        .map((data) => data
            .map((json) => MeatBatch.fromJson(json))
            .where((b) => b.status != 'completed')
            .toList());
  }

  Future<void> addMeatBatch(MeatBatch batch) async {
    await _client.from('meat_batches').insert({
      'id': batch.id,
      'branch_code': batch.branchCode,
      'meat_type': batch.meatType,
      'initial_weight': batch.weight,
      'current_weight': batch.weight,
      'status': batch.status,
      'source_name': batch.source.name,
      'source_location': batch.source.location,
      'owner_name': batch.source.owner,
      'created_at': batch.createdAt.toIso8601String(),
    });
  }

  Future<void> updateBatchStatus(String id, String status) async {
    await _client
        .from('meat_batches')
        .update({'status': status})
        .eq('id', id);
  }

  Future<List<MeatCut>> getRecentCuts(String branchCode) async {
    final response = await _client
        .from('meat_cuts')
        .select()
        .eq('branch_code', branchCode)
        .order('processed_at', ascending: false)
        .limit(100);
    
    return (response as List).map((json) => MeatCut.fromJson(json)).toList();
  }

  Stream<List<MeatCut>> watchRecentCuts(String branchCode) {
    return _client
        .from('meat_cuts')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('processed_at', ascending: false)
        .map((data) => data.map((json) => MeatCut.fromJson(json)).toList());
  }

  Future<void> addMeatCut(MeatCut cut) async {
    await _client.from('meat_cuts').insert({
      'id': cut.id,
      'branch_code': cut.branchCode,
      'batch_id': cut.batchId,
      'name': cut.name,
      'weight': cut.weight,
      'unit': cut.unit,
      'processed_at': cut.processedAt.toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getWaste(String branchCode) async {
    final response = await _client
        .from('butcher_waste')
        .select()
        .eq('branch_code', branchCode)
        .order('recorded_at', ascending: false);
    
    return List<Map<String, dynamic>>.from(response);
  }

  Stream<List<Map<String, dynamic>>> watchWaste(String branchCode) {
    return _client
        .from('butcher_waste')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('recorded_at', ascending: false);
  }

  Future<void> addWaste(String branchCode, String batchId, String reason, double weight) async {
    await _client.from('butcher_waste').insert({
      'branch_code': branchCode,
      'batch_id': batchId,
      'reason': reason,
      'weight': weight,
      'recorded_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<ButcherOrder>> getButcherOrders(String branchCode) async {
    final response = await _client
        .from('butcher_orders')
        .select()
        .eq('branch_code', branchCode)
        .order('due_date', ascending: true);
    
    return (response as List).map((json) => ButcherOrder.fromJson(json)).toList();
  }

  Stream<List<ButcherOrder>> watchButcherOrders(String branchCode) {
    return _client
        .from('butcher_orders')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('due_date', ascending: true)
        .map((data) => data.map((json) => ButcherOrder.fromJson(json)).toList());
  }

  Future<void> updateButcherOrderStatus(String id, ButcherOrderStatus status) async {
    await _client
        .from('butcher_orders')
        .update({'status': status.name})
        .eq('id', id);
  }

  Future<void> addButcherOrder(ButcherOrder order) async {
    await _client.from('butcher_orders').insert(order.toJson());
  }
}
