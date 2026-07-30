import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/salary_model.dart';

class SupabaseSalaryService {
  final _client = Supabase.instance.client;

  Future<List<SalaryRecord>> getSalaryPayments(String userId) async {
    final response = await _client
        .from('staff_payments_audit')
        .select()
        .eq('user_id', userId)
        .order('date', ascending: false);
    
    return (response as List).map((json) => SalaryRecord.fromJson(json)).toList();
  }

  Future<List<SalaryRecord>> getAllSalaryPayments() async {
    final response = await _client
        .from('staff_payments_audit')
        .select()
        .order('date', ascending: false);
    
    return (response as List).map((json) => SalaryRecord.fromJson(json)).toList();
  }

  Future<void> addSalaryPayment(SalaryRecord record) async {
    await _client.from('staff_payments_audit').insert(record.toJson());
  }

  Future<void> updateSalaryPayment(SalaryRecord record) async {
    await _client.from('staff_payments_audit').update(record.toJson()).eq('id', record.id);
  }

  Future<void> deleteSalaryPayment(String id) async {
    await _client.from('staff_payments_audit').delete().eq('id', id);
  }

  Stream<List<SalaryRecord>> watchSalaryPayments() {
    return _client
        .from('staff_payments_audit')
        .stream(primaryKey: ['id'])
        .order('date', ascending: false)
        .map((data) => data.map((json) => SalaryRecord.fromJson(json)).toList());
  }
}
