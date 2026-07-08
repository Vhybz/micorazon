import 'package:flutter/foundation.dart';
import '../models/customer_model.dart';
import '../core/supabase_config.dart';

class SupabaseCustomerService {
  final _client = SupabaseConfig.client;

  Future<List<Customer>> getCustomers(String branchCode) async {
    var query = _client.from('customers').select();
    
    if (branchCode.isNotEmpty) {
      query = query.eq('branch_code', branchCode);
    }
    
    final response = await query.order('name', ascending: true);
    
    return (response as List).map((json) => Customer.fromJson(json)).toList();
  }

  Future<Customer> addCustomer(Customer customer) async {
    final Map<String, dynamic> data = customer.toJson();
    
    // If it's a temporary ID, let Supabase generate a real one
    if (customer.id.startsWith('00000000-0000-0000-0000-')) {
      data.remove('id');
    }

    // Ensure branch_code is null if it's empty to avoid foreign key errors
    if (data['branch_code'] == null || (data['branch_code'] is String && data['branch_code'].toString().isEmpty)) {
      data.remove('branch_code');
    }
    
    try {
      final response = await _client
          .from('customers')
          .insert(data)
          .select()
          .single();
      
      return Customer.fromJson(response);
    } catch (e) {
      debugPrint('SUPABASE CUSTOMER INSERT ERROR: $e');
      rethrow;
    }
  }

  Future<void> updateCustomer(Customer customer) async {
    await _client
        .from('customers')
        .update(customer.toJson())
        .eq('id', customer.id);
  }

  Future<void> deleteCustomer(String id) async {
    await _client.from('customers').delete().eq('id', id);
  }

  Stream<List<Customer>> watchCustomers(String branchCode) {
    if (branchCode.isNotEmpty) {
      return _client
          .from('customers')
          .stream(primaryKey: ['id'])
          .eq('branch_code', branchCode)
          .order('name', ascending: true)
          .map((data) => data.map((json) => Customer.fromJson(json)).where((c) => !c.isDeleted).toList());
    }

    return _client
        .from('customers')
        .stream(primaryKey: ['id'])
        .order('name', ascending: true)
        .map((data) => data.map((json) => Customer.fromJson(json)).where((c) => !c.isDeleted).toList());
  }
}
