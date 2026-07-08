import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/sale_model.dart';
import '../models/user_model.dart';

class SmsService {
  static String get _apiKey => const String.fromEnvironment('ARKESEL_API_KEY', defaultValue: '')
      .isEmpty ? (dotenv.env['ARKESEL_API_KEY'] ?? 'akhlSEFORkpBSHBNR1JQTk1Lbm4') : const String.fromEnvironment('ARKESEL_API_KEY');
  
  static String get _senderId => const String.fromEnvironment('ARKESEL_SENDER_ID', defaultValue: '')
      .isEmpty ? (dotenv.env['ARKESEL_SENDER_ID'] ?? 'MiCorazon') : const String.fromEnvironment('ARKESEL_SENDER_ID');

  static String get _adminPhone => const String.fromEnvironment('ADMIN_PHONE', defaultValue: '')
      .isEmpty ? (dotenv.env['ADMIN_PHONE'] ?? '0209276200') : const String.fromEnvironment('ADMIN_PHONE');

  static Future<bool> _sendSms(String to, String message) async {
    if (_apiKey.isEmpty) {
      debugPrint('SMS Error: API Key is missing');
      return false;
    }

    // Format phone number to 233 format (remove leading zero, add 233)
    String formattedPhone = to.trim().replaceAll(RegExp(r'\s+'), '');
    if (formattedPhone.startsWith('0') && formattedPhone.length == 10) {
      formattedPhone = '233${formattedPhone.substring(1)}';
    } else if (formattedPhone.length == 9 && !formattedPhone.startsWith('233')) {
      formattedPhone = '233$formattedPhone';
    } else if (formattedPhone.startsWith('+')) {
      formattedPhone = formattedPhone.substring(1);
    }

    // Try Arkesel V2 first (JSON POST), then fallback to V1
    try {
      debugPrint('Attempting to send SMS to $formattedPhone via Arkesel V2...');
      final v2Url = Uri.parse('https://sms.arkesel.com/api/v2/sms/send');
      final response = await http.post(
        v2Url,
        headers: {
          'api-key': _apiKey,
          'Content-Type': 'application/json',
        },
        body: '{"sender":"$_senderId","recipients":["$formattedPhone"],"message":"${message.replaceAll('"', '\\"')}"}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('SMS sent successfully via V2: ${response.body}');
        return true;
      } else {
        debugPrint('Arkesel V2 failed (Status ${response.statusCode}). Falling back to V1...');
      }
    } catch (e) {
      debugPrint('Arkesel V2 Exception: $e. Trying V1...');
    }

    // Fallback to Arkesel V1 (Query Params)
    final url = Uri.parse(
      'https://sms.arkesel.com/sms/api?action=send-sms'
      '&api_key=$_apiKey'
      '&to=$formattedPhone'
      '&from=$_senderId'
      '&sms=${Uri.encodeComponent(message)}'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        if (response.body.contains('"code":"1000"') || response.body.contains('1000')) {
          debugPrint('SMS sent successfully via V1');
          return true;
        }
      }
      debugPrint('Arkesel V1 Failed: ${response.body}');
      return false;
    } catch (e) {
      debugPrint('SMS V1 Exception: $e');
      return false;
    }
  }

  static Future<bool> sendReceiptSms(SaleRecord sale, {double? discountAmount, String? branchName}) async {
    if (sale.customerPhone == null || sale.customerPhone!.isEmpty) return false;
    
    final bool isDebt = sale.balance > 0.01;
    final String typeHeader = isDebt ? 'DEBT INVOICE: ' : 'ORDER CONFIRMATION: ';
    final String shopName = branchName ?? 'Mi~Corazon Butchery';
    
    String message = '$typeHeader Hello ${sale.customerName ?? 'Customer'}, your total for order ${sale.id} at $shopName is GHC${sale.totalAmount.toStringAsFixed(2)}.';
    
    if (isDebt) {
      message += ' Amount Paid: GHC${sale.amountPaid.toStringAsFixed(2)}. Outstanding Balance (DEBT): GHC${sale.balance.toStringAsFixed(2)}. Please settle as soon as possible.';
    }

    if (discountAmount != null && discountAmount > 0) {
      message += ' You saved GHC${discountAmount.toStringAsFixed(2)}! Thank you for being a valued customer.';
    } else {
      if (!isDebt) {
        message += ' Thank you for shopping with us!';
      }
    }

    return await _sendSms(sale.customerPhone!, message);
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
    final String message = 'STOCK ALERT: New stock ($itemDetails) has been transfered to $branchName branch. Please log in to confirm receipt.';
    final targets = branchUsers
        .where((u) => u.branchCode == branchCode && u.status == AccountStatus.approved && u.phone != null && u.phone!.isNotEmpty)
        .toList();
    for (final user in targets) {
      await _sendSms(user.phone!, message);
    }
  }

  static Future<void> notifyAdmin({required String title, required String message}) async {
    await _sendSms(_adminPhone, '$title: $message');
  }

  static Future<bool> sendSalarySms({
    required String phone,
    required String firstName,
    required double amount,
    required bool isAdvance,
  }) async {
    if (phone.isEmpty) return false;
    final String type = isAdvance ? 'an advance' : 'your salary payment';
    return await _sendSms(phone, 'Hello $firstName, you have received $type of GHS ${amount.toStringAsFixed(2)}. - Mi~Corazon Management');
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
}
