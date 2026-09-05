import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'sale_provider.dart';
import 'till_provider.dart';
import 'user_provider.dart';
import 'sms_service.dart';
import '../models/user_model.dart';
import '../models/sale_model.dart';

final dailyReminderServiceProvider = Provider((ref) => DailyReminderService(ref));

class DailyReminderService {
  final Ref ref;
  static const String _boxName = 'daily_reminders';
  static const String _lastKey = 'last_sent_date';

  DailyReminderService(this.ref);

  Future<void> checkAndSendDailySummary() async {
    try {
      final now = DateTime.now();
      
      // 1. Only send after 9:30 PM (21:30)
      if (now.hour < 21 || (now.hour == 21 && now.minute < 30)) return;

      // 2. Check if already sent today
      final box = await Hive.openBox(_boxName);
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final lastSent = box.get(_lastKey);

      if (lastSent == todayStr) {
        debugPrint('Daily Reminder: Already sent for today ($todayStr).');
        return;
      }

      // 3. Check if there were any sales today
      final allSales = ref.read(saleHistoryProvider);
      final todaySalesTotal = allSales
          .where((s) => 
            s.timestamp.year == now.year && 
            s.timestamp.month == now.month && 
            s.timestamp.day == now.day &&
            s.status != SaleStatus.cancelled &&
            s.status != SaleStatus.reversed)
          .fold(0.0, (sum, s) => sum + s.totalAmount);

      if (todaySalesTotal <= 0) {
        debugPrint('Daily Reminder: No sales today. Skipping SMS.');
        return;
      }

      // 4. Get Data for SMS
      final tillBalance = ref.read(tillProvider).currentBalance;
      final users = ref.read(userProvider);
      final adminPhones = users
          .where((u) => 
            (u.role == UserRole.admin || u.role == UserRole.superAdmin) && 
            u.phone != null && 
            u.phone!.isNotEmpty)
          .map((u) => u.phone!)
          .toSet()
          .toList();

      if (adminPhones.isEmpty) {
        debugPrint('Daily Reminder: No admin phone numbers found.');
        return;
      }

      // 5. Send SMS
      debugPrint('Daily Reminder: Sending summary to ${adminPhones.length} admins...');
      final success = await SmsService.sendDailySummarySms(
        dailySales: todaySalesTotal,
        tillBalance: tillBalance,
        adminPhones: adminPhones,
      );

      if (success) {
        await box.put(_lastKey, todayStr);
        debugPrint('Daily Reminder: Summary sent and recorded.');
      }
    } catch (e) {
      debugPrint('Daily Reminder Error: $e');
    }
  }
}
