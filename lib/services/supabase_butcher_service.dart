import '../models/butcher_models.dart';
import '../core/supabase_config.dart';

class SupabaseButcherService {
  final _client = SupabaseConfig.client;

  Future<List<SlaughterLog>> getSlaughterLogs(String branchCode) async {
    final response = await _client
        .from('slaughter_logs')
        .select('*, animals(tag_number, source_farm)')
        .eq('branch_code', branchCode)
        .order('slaughter_time', ascending: false, nullsFirst: true);
    
    return (response as List).map((json) {
      final Map<String, dynamic> data = Map<String, dynamic>.from(json);
      if (data['animals'] != null) {
        data['tag_number'] = data['animals']['tag_number'];
        data['source_farm'] = data['animals']['source_farm'];
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

  Future<void> addAnimal(String branchCode, String animalUuid, String tagNumber, AnimalType type, double weight, String sourceFarm, {int quantity = 1, double? price, double? farmPrice, String? manualFarmTag}) async {
    await _client.from('animals').insert({
      'id': animalUuid,
      'tag_number': tagNumber,
      'manual_farm_tag': manualFarmTag,
      'branch_code': branchCode,
      'type': type.name,
      'quantity': quantity,
      'weight': weight,
      'purchase_price': price ?? 0,
      'source_farm': sourceFarm,
      'status': 'waiting',
      'arrival_time': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateAnimal(String id, {String? tagNumber, String? manualFarmTag, AnimalType? type, int? quantity, double? weight, double? price, String? sourceFarm}) async {
    final Map<String, dynamic> updateData = {};
    if (tagNumber != null) updateData['tag_number'] = tagNumber;
    if (manualFarmTag != null) updateData['manual_farm_tag'] = manualFarmTag;
    if (type != null) updateData['type'] = type.name;
    if (quantity != null) updateData['quantity'] = quantity;
    if (weight != null) updateData['weight'] = weight;
    if (price != null) updateData['purchase_price'] = price;
    if (sourceFarm != null) updateData['source_farm'] = sourceFarm;

    if (updateData.isNotEmpty) {
      await _client.from('animals').update(updateData).eq('id', id);
    }
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

  Future<void> updateSlaughterStatus(String id, SlaughterStatus status, {DateTime? time, String? slaughteredBy, String? portionedBy}) async {
    final Map<String, dynamic> updateData = {
      'status': status.name,
    };
    if (time != null) {
      updateData['slaughter_time'] = time.toIso8601String();
    }
    if (slaughteredBy != null) {
      updateData['slaughtered_by'] = slaughteredBy;
    }
    if (portionedBy != null) {
      updateData['portioned_by'] = portionedBy;
    }
    await _client
        .from('slaughter_logs')
        .update(updateData)
        .eq('id', id);
  }

  Future<void> deleteSlaughterIntake(String logId, String animalId) async {
    // Delete log first due to foreign key (actually animal is referenced by log, so log first)
    await _client.from('slaughter_logs').delete().eq('id', logId);
    await _client.from('animals').delete().eq('id', animalId);
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
      'animal_id': batch.animalId,
      'meat_type': batch.meatType,
      'initial_weight': batch.weight,
      'current_weight': batch.weight,
      'status': batch.status,
      'source_name': batch.source.name,
      'source_location': batch.source.location,
      'owner_name': batch.source.owner,
      'inspected_by': batch.inspectedBy,
      'received_by': batch.receivedBy,
      'portioned_by': batch.portionedBy,
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
