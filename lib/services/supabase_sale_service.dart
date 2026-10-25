import '../models/sale_model.dart';
import '../core/supabase_config.dart';

class SupabaseSaleService {
  final _client = SupabaseConfig.client;

  Future<List<SaleRecord>> getSales(String branchCode, {int limit = 500}) async {
    final response = await _client
        .from('sales')
        .select()
        .eq('branch_code', branchCode)
        .order('timestamp', ascending: false)
        .limit(limit);
    
    return (response as List).map((json) => SaleRecord.fromJson(json)).toList();
  }

  Future<void> saveSale(SaleRecord sale) async {
    await _client.from('sales').insert(sale.toJson());
  }

  Future<void> updateSale(SaleRecord sale) async {
    await _client
        .from('sales')
        .update(sale.toJson())
        .eq('id', sale.id);
  }

  Future<void> deleteSales(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client.from('sales').delete().filter('id', 'in', '(${ids.join(',')})');
  }

  Stream<List<SaleRecord>> getSalesStream(String branchCode, {int limit = 500}) {
    return _client
        .from('sales')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('timestamp', ascending: false)
        .limit(limit)
        .map((data) => data.map((json) => SaleRecord.fromJson(json)).toList());
  }
}
