import '../models/transfer_models.dart';
import '../core/supabase_config.dart';

class SupabaseTransferService {
  final _client = SupabaseConfig.client;

  Future<List<StockTransfer>> getTransfers() async {
    final response = await _client
        .from('stock_transfers')
        .select()
        .order('transfer_time', ascending: false);
    
    return (response as List).map((json) => StockTransfer.fromJson(json)).toList();
  }

  Future<void> addTransfer(StockTransfer transfer) async {
    await _client.from('stock_transfers').insert(transfer.toJson());
  }

  Future<void> updateTransferStatus(String id, TransferStatus status) async {
    await _client
        .from('stock_transfers')
        .update({'status': status.name})
        .eq('id', id);
  }

  Stream<List<StockTransfer>> watchTransfers() {
    return _client
        .from('stock_transfers')
        .stream(primaryKey: ['id'])
        .order('transfer_time', ascending: false)
        .map((data) => data.map((json) => StockTransfer.fromJson(json)).toList());
  }
}
