import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/user_model.dart';
import 'user_provider.dart';

class AiService {
  final UserAccount? user;

  AiService(this.user);

  String get _provider => const String.fromEnvironment('AI_PROVIDER', defaultValue: '').isEmpty 
      ? (dotenv.env['AI_PROVIDER'] ?? 'openai').toLowerCase() 
      : const String.fromEnvironment('AI_PROVIDER').toLowerCase();

  String get _apiKey => const String.fromEnvironment('AI_API_KEY', defaultValue: '').isEmpty 
      ? (dotenv.env['AI_API_KEY'] ?? '').trim() 
      : const String.fromEnvironment('AI_API_KEY').trim();

  Future<String> getResponse(String message, List<Map<String, String>> history) async {
    if (_apiKey.isEmpty) {
      return "AI Error: API Key is missing. Please add AI_API_KEY to your .env file.";
    }

    try {
      final String baseUrl = _provider == 'groq'
          ? 'https://api.groq.com/openai/v1/chat/completions'
          : 'https://api.openai.com/v1/chat/completions';

      final String model = _provider == 'groq'
          ? 'llama-3.1-8b-instant'
          : 'gpt-4o-mini';

      final url = Uri.parse(baseUrl);

      final List<Map<String, String>> messages = [
        {"role": "system", "content": _buildSystemPrompt()},
        ...history,
        {"role": "user", "content": message},
      ];

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          "model": model,
          "messages": messages,
          "temperature": 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        final error = jsonDecode(response.body);
        String errorMsg = error['error']?['message'] ?? 'Unknown API Error';
        return "AI Error ($_provider): $errorMsg";
      }
    } catch (e) {
      debugPrint('AI Error: $e');
      return "I'm having trouble connecting to my brain. Please check your internet or key.";
    }
  }

  String _buildSystemPrompt() {
    final role = user?.activePrimaryRole;
    final roleName = role?.name.toUpperCase() ?? 'STAFF';
    final name = user?.firstName ?? 'there';

    String roleSpecificInstructions = "";
    if (role == UserRole.butcher) {
      roleSpecificInstructions = "SOP: Record Farm Price, weigh parts accurately (90-100% yield), and attach barcodes.";
    } else if (role == UserRole.cashier) {
      roleSpecificInstructions = "SOP: Scan barcodes to verify stock, manage debts via customer profiles, and process Bank Deposits carefully.";
    } else if (role == UserRole.admin || role == UserRole.superAdmin) {
      roleSpecificInstructions = "SOP: Monitor net profit, verify bank transfers, and manage staff permissions.";
    }

    return """
    You are the Mi~Corazon AI Assistant for a modern butchery in Sunyani, Ghana.
    User: $name ($roleName).
    
    RULES:
    1. Be a professional partner for this butchery.
    2. $roleSpecificInstructions
    3. Use local context (MoMo, GHS, Sunyani).
    4. Keep answers short and practical.
    """;
  }
}

final aiServiceProvider = Provider<AiService>((ref) {
  final user = ref.watch(currentUserProvider);
  return AiService(user);
});
