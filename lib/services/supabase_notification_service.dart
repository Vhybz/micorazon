import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/system_models.dart';
import '../core/supabase_config.dart';

class SupabaseNotificationService {
  SupabaseClient get _client => SupabaseConfig.client;

  Stream<List<SystemNotification>> watchNotifications(String? branchCode, String? userId, {bool isSuperAdmin = false}) {
    if (!isSuperAdmin && branchCode == null && userId == null) return Stream.value([]);

    final String? cleanBranch = branchCode?.trim();

    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((data) => data
            .map((json) => SystemNotification.fromJson(json))
            .where((n) {
              if (isSuperAdmin) return true;
              if (n.branchCode == null && n.userId == null) return true;
              if (cleanBranch != null && n.branchCode?.trim() == cleanBranch) return true;
              if (userId != null && n.userId == userId) return true;
              return false;
            })
            .toList()
            .reversed
            .toList());
  }

  Future<void> markAsRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllAsRead(String userId, String? branchCode, {bool isSuperAdmin = false}) async {
    try {
      final String cleanBranch = (branchCode ?? '').trim();
      
      if (isSuperAdmin) {
        await _client.from('notifications').update({'is_read': true}).eq('is_read', false);
      } else {
        // 1. Mark user-specific notifications
        await _client.from('notifications')
            .update({'is_read': true})
            .eq('user_id', userId)
            .eq('is_read', false);
            
        if (cleanBranch.isNotEmpty) {
          // 2. Mark branch-specific notifications
          await _client.from('notifications')
              .update({'is_read': true})
              .eq('branch_code', cleanBranch)
              .eq('is_read', false);
        }
        
        // 3. Mark global notifications (where both IDs are null)
        await _client.from('notifications')
            .update({'is_read': true})
            .filter('user_id', 'is', null)
            .filter('branch_code', 'is', null)
            .eq('is_read', false);
      }
    } catch (e) {
      debugPrint('Mark All Read Error: $e');
    }
  }
}
