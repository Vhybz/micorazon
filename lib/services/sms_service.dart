import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import '../models/sale_model.dart';
import '../models/user_model.dart';

class SmsService {
  // Use const for better Web support with --dart-define
  static const String _defineApiKey = String.fromEnvironment('ARKESEL_API_KEY');
  static const String _defineSenderId = String.fromEnvironment('ARKESEL_SENDER_ID');
  static const String _defineAdminPhone = String.fromEnvironment('ADMIN_PHONE');

  static String get _apiKey {
    if (_defineApiKey.isNotEmpty) return _defineApiKey;
    return dotenv.env['ARKESEL_API_KEY'] ?? 'akhlSEFORkpBSHBNR1JQTk1Lbm4';
  }
  
  static String get _senderId {
    if (_defineSenderId.isNotEmpty) return _defineSenderId;
    return dotenv.env['ARKESEL_SENDER_ID'] ?? 'MiCorazon';
  }

  static String get _adminPhone {
    if (_defineAdminPhone.isNotEmpty) return _defineAdminPhone;
    return dotenv.env['ADMIN_PHONE'] ?? '0209276200';
  }

  static Future<bool> _sendSms(String to, String message) async {
    final apiKey = _apiKey.trim();
    final senderId = _senderId.trim();

    if (apiKey.isEmpty) {
      debugPrint('SMS Error: API Key is missing');
      return false;
    }

    // Format phone number to 233 format (remove non-digits, adjust leading zero)
    String formattedPhone = to.trim().replaceAll(RegExp(r'[^\d]'), '');
    if (formattedPhone.startsWith('0') && formattedPhone.length == 10) {
      formattedPhone = '233${formattedPhone.substring(1)}';
    } else if (formattedPhone.length == 9 && !formattedPhone.startsWith('233')) {
      formattedPhone = '233$formattedPhone';
    }

    if (formattedPhone.isEmpty) {
      debugPrint('SMS Error: Formatted recipient phone number is empty.');
      return false;
    }

    // Try Arkesel V2 first (JSON POST with jsonEncode)
    try {
      debugPrint('Attempting to send SMS to $formattedPhone via Arkesel V2...');
      final v2Url = Uri.parse('https://sms.arkesel.com/api/v2/sms/send');
      final payload = {
        'sender': senderId,
        'recipients': [formattedPhone],
        'message': message,
      };

      final response = await http.post(
        v2Url,
        headers: {
          'api-key': apiKey,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('SMS sent successfully via V2: ${response.body}');
        return true;
      } else {
        debugPrint('Arkesel V2 failed (Status ${response.statusCode}): ${response.body}. Falling back to V1...');
      }
    } catch (e) {
      debugPrint('Arkesel V2 Exception: $e. Trying V1...');
    }

    // Fallback to Arkesel V1 (Query Params)
    final url = Uri.parse(
      'https://sms.arkesel.com/sms/api?action=send-sms'
      '&api_key=$apiKey'
      '&to=$formattedPhone'
      '&from=$senderId'
      '&sms=${Uri.encodeComponent(message)}'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final bodyLower = response.body.toLowerCase();
        if (bodyLower.contains('"code":"1000"') || 
            bodyLower.contains('1000') || 
            bodyLower.contains('success') ||
            bodyLower.contains('ok')) {
          debugPrint('SMS sent successfully via V1: ${response.body}');
          return true;
        }
      }
      debugPrint('Arkesel V1 Failed (Status ${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('SMS V1 Exception: $e');
      return false;
    }
  }

  static Future<bool> sendReceiptSms(
    SaleRecord sale, {
    double? discountAmount,
    String? branchName,
    String? customPhone,
  }) async {
    final String? targetPhone = (customPhone != null && customPhone.trim().isNotEmpty)
        ? customPhone.trim()
        : sale.customerPhone;

    if (targetPhone == null || targetPhone.trim().isEmpty) {
      debugPrint('sendReceiptSms: No target phone number provided.');
      return false;
    }

    final bool isDebt = sale.balance > 0.01;
    final String typeHeader = isDebt ? 'DEBT INVOICE' : 'RECEIPT';
    final String shopName = branchName ?? 'Mi~Corazon Butchery';

    // Format clean receipt ID
    final String receiptId = sale.id.startsWith('INV-')
        ? sale.id
        : (sale.id.length > 8 ? sale.id.substring(sale.id.length - 8).toUpperCase() : sale.id.toUpperCase());

    // Format Item Breakdown
    final String itemsSummary = sale.items.map((i) {
      final qty = i.quantity % 1 == 0 ? i.quantity.toInt().toString() : i.quantity.toStringAsFixed(1);
      return '$qty${i.product.unit} ${i.product.name}';
    }).join(', ');

    String message = '$typeHeader #$receiptId - $shopName\n';
    if (sale.customerName != null && sale.customerName!.isNotEmpty && sale.customerName != 'Walk-in Customer') {
      message += 'Customer: ${sale.customerName}\n';
    }
    if (itemsSummary.isNotEmpty) {
      message += 'Items: $itemsSummary\n';
    }
    message += 'Total: GHS ${sale.totalAmount.toStringAsFixed(2)}';

    if (isDebt) {
      message += '\nPaid: GHS ${sale.amountPaid.toStringAsFixed(2)}\nBalance Due: GHS ${sale.balance.toStringAsFixed(2)}';
    } else {
      message += '\nStatus: Paid';
    }

    if (discountAmount != null && discountAmount > 0) {
      message += '\nSaved: GHS ${discountAmount.toStringAsFixed(2)}';
    }

    message += '\nThank you for shopping with us!';

    return await _sendSms(targetPhone, message);
  }

  static Future<void> sendApprovalRequestSms(UserAccount applicant, List<UserAccount> admins) async {
    final message = 'New user registration needs approval. Name: ${applicant.firstName} ${applicant.surname}, Role: ${applicant.role.name.toUpperCase()}. Please log in to approve.';
    
    final adminPhones = admins
        .where((u) => (u.role == UserRole.admin || u.role == UserRole.superAdmin) && u.phone != null && u.phone!.isNotEmpty)
        .map((u) => u.phone!)
        .toSet()
        .toList();

    if (_adminPhone.isNotEmpty && !adminPhones.contains(_adminPhone)) {
      adminPhones.add(_adminPhone);
    }

    for (final phone in adminPhones) {
      await _sendSms(phone, message);
    }
  }

  static Future<void> sendSignupConfirmationSms(UserAccount user, bool isAutoApproved) async {
    if (user.phone == null || user.phone!.isEmpty) return;

    final statusMessage = isAutoApproved 
        ? 'Your account has been approved. You can now log in.' 
        : 'Your application is pending administrator approval. You will be notified once approved.';

    String message = 'Hello ${user.firstName}, thank you for registering with Mi~Corazon Freshmeat Butchery. $statusMessage';
    
    if (user.role == UserRole.admin && user.branchCode != null) {
      message += ' Your Shop Registration Code is: ${user.branchCode}. Please share this with your staff to link them to your branch.';
    }
    
    await _sendSms(user.phone!, message);
  }

  static Future<void> sendStaffOnboardingSms(UserAccount user) async {
    if (user.phone == null || user.phone!.isEmpty) return;
    final String message = 'Welcome to the team, ${user.firstName}! Your account has been linked to your staff profile as a ${user.role.name.toUpperCase()} at Mi~Corazon. You can now log in and start working.';
    await _sendSms(user.phone!, message);
  }

  static Future<void> sendApprovalSms(UserAccount user) async {
    if (user.phone == null || user.phone!.isEmpty) return;
    final String message = 'Congratulations ${user.firstName}! Your Mi~Corazon account has been approved. You can now log in instantly.';
    await _sendSms(user.phone!, message);
  }

  static Future<void> sendCustomerWelcomeSms(String name, String phone, String? branchName) async {
    if (phone.isEmpty) return;
    final String branchText = branchName != null ? '($branchName Branch)' : '';
    final String message = 'Hello $name, thank you for being part of our favorite customers at Mi~Corazon Freshmeat Butchery $branchText.';
    await _sendSms(phone, message);
  }

  static Future<void> sendDebtReminderSms(SaleRecord sale, {String? branchName}) async {
    if (sale.customerPhone == null || sale.customerPhone!.isEmpty) return;
    final String shopName = branchName ?? 'Mi~Corazon Butchery';
    final String message = 'DEBT REMINDER: Hello ${sale.customerName}, this is a reminder regarding your outstanding balance of GHC${sale.balance.toStringAsFixed(2)} for invoice ${sale.id} at $shopName. Please settle as soon as possible.';
    await _sendSms(sale.customerPhone!, message);
  }

  static Future<bool> sendDebtPaymentSms({
    required String phone,
    required String name,
    required String invoiceId,
    required double amountPaid,
    required double remainingBalance,
    String? branchName,
  }) async {
    if (phone.isEmpty) return false;
    final String shopName = branchName ?? 'Mi~Corazon Butchery';
    String message = 'Hello $name, we have received your payment of GHS ${amountPaid.toStringAsFixed(2)} for invoice $invoiceId at $shopName.';
    if (remainingBalance > 0.01) {
      message += ' Your remaining balance is GHS ${remainingBalance.toStringAsFixed(2)}.';
    } else {
      message += ' Your balance has been fully cleared. Thank you!';
    }
    return await _sendSms(phone, message);
  }

  static Future<void> sendDispatchSms({
    required String name,
    required String phone,
    required String item,
    required double weight,
    String? location,
  }) async {
    if (phone.isEmpty) return;
    final String locText = location != null && location.isNotEmpty ? ' to be delivered to $location' : '';
    final String message = 'Hello $name, your order for ${weight.toStringAsFixed(1)}kg of $item is ready for dispatch from Mi~Corazon Butchery$locText.';
    await _sendSms(phone, message);
  }

  static Future<void> sendTransferNotificationSms({
    required String branchName,
    required String branchCode,
    required String itemDetails,
    required List<UserAccount> branchUsers,
  }) async {
    // SMS Stock alert disabled per user request
  }

  static Future<void> notifyAdmin({required String title, required String message}) async {
    await _sendSms(_adminPhone, '$title: $message');
  }

  static Future<bool> sendSalarySms({
    required String phone,
    required String firstName,
    required double amount,
    required bool isAdvance,
    String? note,
    DateTime? targetMonth,
    bool isUpdate = false,
  }) async {
    if (phone.isEmpty) return false;
    
    final String typeHeader = isUpdate 
        ? 'PAYMENT UPDATE: ' 
        : (isAdvance ? 'ADVANCE PAYMENT ALERT: ' : 'SALARY PAYMENT CONFIRMATION: ');
    
    final String type = isAdvance ? 'an advance' : 'your salary payment';
    final String monthText = targetMonth != null ? ' for ${DateFormat('MMMM yyyy').format(targetMonth)}' : '';
    
    String message = '${typeHeader}Hello $firstName, you have received $type of GHS ${amount.toStringAsFixed(2)}$monthText.';
    
    if (note != null && note.isNotEmpty) {
      message += ' Note: $note';
    }
    message += ' - Mi~Corazon Management';
    return await _sendSms(phone, message);
  }

  static Future<bool> sendWithdrawalSms({
    required String name,
    required double amount,
    required double remaining,
    required String? phone,
    double? totalRemaining,
    String action = 'recorded',
  }) async {
    String message = 'SECURITY ALERT: CEO Withdrawal $action. Amount: GHS ${amount.toStringAsFixed(2)} by $name. Remaining for day: GHS ${remaining.toStringAsFixed(2)}.';
    if (totalRemaining != null) {
      message += ' Total Cash at Shop: GHS ${totalRemaining.toStringAsFixed(2)}.';
    }
    
    // Send to the provided phone number if available, otherwise fallback to admin
    final targetPhone = (phone != null && phone.isNotEmpty) ? phone : _adminPhone;
    return await _sendSms(targetPhone, message);
  }

  static Future<bool> sendDailySummarySms({
    required double dailySales,
    required double tillBalance,
    required List<String> adminPhones,
  }) async {
    final String date = DateFormat('EEE, MMM dd').format(DateTime.now());
    final String message = 'DAILY SUMMARY ($date):\n'
        '• Today\'s Sales: GHS ${dailySales.toStringAsFixed(2)}\n'
        '• Cash at Shop: GHS ${tillBalance.toStringAsFixed(2)}\n\n'
        'Please log in to Close Sales now or tomorrow morning. - Mi~Corazon System';

    bool allSent = true;
    for (final phone in adminPhones) {
      final success = await _sendSms(phone, message);
      if (!success) allSent = false;
    }
    return allSent;
  }

  static Future<bool> sendCustomSms(String phone, String message) async {
    if (phone.isEmpty) return false;
    return await _sendSms(phone, message);
  }

  static Future<bool> sendVerificationCodeSms(String phone, String code) async {
    if (phone.isEmpty) return false;
    final String message = 'Your Mi~Corazon password reset code is: $code. Valid for 5 minutes.';
    return await _sendSms(phone, message);
  }

  static Future<bool> sendPasscodeSms(String phone, String name, String passcode) async {
    if (phone.isEmpty) return false;
    final String message = 'Hello $name, your new Mi~Corazon security passcode is: $passcode. Use this to access sensitive system areas.';
    return await _sendSms(phone, message);
  }
}
