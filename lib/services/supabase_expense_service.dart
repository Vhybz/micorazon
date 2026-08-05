import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/expense_model.dart';
import '../core/supabase_config.dart';

class SupabaseExpenseService {
  final _client = SupabaseConfig.client;

  Future<List<ExpenseRecord>> getExpenses(String branchCode) async {
    final response = await _client
        .from('expenses')
        .select()
        .eq('branch_code', branchCode)
        .order('date', ascending: false);
    
    return (response as List).map((json) => ExpenseRecord.fromJson(json)).toList();
  }

  Future<void> addExpense(ExpenseRecord expense) async {
    await _client.from('expenses').insert(expense.toJson());
  }

  Future<void> updateExpense(ExpenseRecord expense) async {
    await _client.from('expenses').update(expense.toJson()).eq('id', expense.id);
  }

  Future<void> deleteExpense(String id) async {
    await _client.from('expenses').delete().eq('id', id);
  }

  Stream<List<ExpenseRecord>> watchExpenses(String branchCode) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('branch_code', branchCode)
        .order('date', ascending: false)
        .map((data) => data.map((json) => ExpenseRecord.fromJson(json)).toList());
  }

  Future<String?> uploadReceipt(Uint8List bytes, String fileName) async {
    try {
      final storage = _client.storage.from('receipts');
      await storage.uploadBinary(
        fileName, 
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      return storage.getPublicUrl(fileName);
    } catch (e) {
      return null;
    }
  }
}
