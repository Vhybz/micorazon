import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/uuid_utils.dart';
import '../models/system_models.dart';
import 'offline_sync_service.dart';
import 'user_provider.dart';

class AuditService {
  static Future<void> log({
    required Ref ref,
    required String action,
    required String entityType,
    String? entityId,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    final user = ref.read(currentUserProvider);
    final log = AuditLog(
      id: UuidUtils.generate(),
      branchCode: user?.branchCode,
      userId: user?.id,
      userName: user?.name,
      action: action,
      entityType: entityType,
      entityId: entityId,
      oldData: oldData,
      newData: newData,
      timestamp: DateTime.now(),
    );

    await OfflineSyncService.addToQueue(
      actionType: 'AUDIT',
      data: log.toJson(),
    );
  }
}
