import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/system_models.dart';

import '../core/supabase_config.dart';

class SupabaseSystemService {
  SupabaseClient get _client => SupabaseConfig.client;

  Future<List<AuditLog>> getAuditLogs(String branchCode) async {
    final response = await _client
        .from('audit_logs')
        .select()
        .eq('branch_code', branchCode)
        .order('timestamp', ascending: false)
        .limit(100);
    return (response as List).map((e) => AuditLog.fromJson(e)).toList();
  }

  Future<List<AuditLog>> getGlobalAuditLogs() async {
    final response = await _client
        .from('audit_logs')
        .select()
        .order('timestamp', ascending: false)
        .limit(100);
    return (response as List).map((e) => AuditLog.fromJson(e)).toList();
  }

  Future<List<SystemNotification>> getNotifications(String branchCode, String? userId) async {
    // Fetch notifications for the branch and specific user (or null)
    final query = _client
        .from('notifications')
        .select()
        .eq('branch_code', branchCode);
    
    // In a real app, you might want to filter by userId or for all in branch
    // .or('user_id.eq.$userId,user_id.is.null')

    final response = await query.order('created_at', ascending: false).limit(50);
    return (response as List).map((e) => SystemNotification.fromJson(e)).toList();
  }

  Future<List<CustomerPayment>> getCustomerPayments(String customerId) async {
    final response = await _client
        .from('customer_payments')
        .select()
        .eq('customer_id', customerId)
        .order('payment_date', ascending: false);
    return (response as List).map((e) => CustomerPayment.fromJson(e)).toList();
  }

  Future<List<StockHistory>> getStockHistory(String productId) async {
    final response = await _client
        .from('stock_history')
        .select()
        .eq('product_id', productId)
        .order('timestamp', ascending: false);
    return (response as List).map((e) => StockHistory.fromJson(e)).toList();
  }
}
