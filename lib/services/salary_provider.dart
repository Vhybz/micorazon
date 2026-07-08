import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/salary_model.dart';
import 'supabase_salary_service.dart';

class SalaryNotifier extends StateNotifier<List<SalaryRecord>> {
  final SupabaseSalaryService _service;

  SalaryNotifier(this._service) : super([]) {
    loadAll();
  }

  Future<void> loadAll() async {
    try {
      final payments = await _service.getAllSalaryPayments();
      debugPrint('Salary Engine: Loaded ${payments.length} payment records from cloud.');
      state = payments;
    } catch (e) {
      debugPrint('Salary Engine Error: $e');
    }
  }

  Future<void> addPayment(SalaryRecord record) async {
    // 1. Force optimistic local update (Instant UI feedback)
    state = [record, ...state];
    
    try {
      debugPrint('Salary Engine: Saving record ${record.id} for ${record.userId}...');
      await _service.addSalaryPayment(record);
      debugPrint('Salary Engine: Save confirmed by database.');
    } catch (e) {
      debugPrint('Salary Engine DB ERROR: $e');
      // Rollback local state only if it definitely failed
      state = state.where((r) => r.id != record.id).toList();
      rethrow;
    }
  }

  List<SalaryRecord> getPaymentsForUser(String userId) {
    return state.where((p) => p.userId == userId).toList();
  }
}

final salaryServiceProvider = Provider<SupabaseSalaryService>((ref) {
  return SupabaseSalaryService();
});

final salaryHistoryProvider = StateNotifierProvider<SalaryNotifier, List<SalaryRecord>>((ref) {
  return SalaryNotifier(ref.watch(salaryServiceProvider));
});
