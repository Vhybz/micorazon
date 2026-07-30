import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static late SupabaseClient _adminClient;
  static late SupabaseClient _publicClient;
  static bool _isInitialized = false;

  static SupabaseClient get adminClient {
    if (!_isInitialized) throw Exception('SupabaseConfig not initialized.');
    return _adminClient;
  }

  static SupabaseClient get client {
    // ALWAYS return the standard instance client to ensure 
    // Auth storage and PKCE flow work correctly.
    return Supabase.instance.client;
  }

  static Future<void> initialize() async {
    String url = '';
    String anonKey = '';
    try {
      debugPrint('Supabase: Initializing with .env configuration...');
      
      // Priority 1: Environment Variables (--dart-define)
      url = const String.fromEnvironment('SUPABASE_URL');
      anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
      String serviceKey = const String.fromEnvironment('SUPABASE_SERVICE_ROLE_KEY');

      // Priority 2: .env file
      if (url.isEmpty) url = dotenv.env['SUPABASE_URL'] ?? '';
      if (anonKey.isEmpty) anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
      if (serviceKey.isEmpty) serviceKey = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

      // Priority 3: Hardcoded Fallback
      if (url.isEmpty) {
        url = 'https://rdlwqnnzbtxwyasdebkj.supabase.co'; 
      }
      
      if (anonKey.isEmpty) {
        anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkbHdxbm56YnR4d3lhc2RlYmtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMDkwMzMsImV4cCI6MjA5NjY4NTAzM30.IJwhUmZ1xiGMCCHUGDbD5M1zcKbqXOtuPg-xGISluOQ';
      }
      
      final cleanUrl = url.trim();
      final cleanKey = anonKey.trim();

      if (serviceKey.isEmpty && cleanUrl.contains('rdlwqnnzbtxwyasdebkj')) {
        serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkbHdxbm56YnR4d3lhc2RlYmtqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MTEwOTAzMywiZXhwIjoyMDk2Njg1MDMzfQ.werb0ZSuepQ6-MPf6Z5ahXexw61KsRZdV3iMQQ2dLVU';
      }

      final cleanServiceKey = serviceKey.trim();

      if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) {
        throw Exception('Supabase URL is invalid.');
      }

      // 1. Initialize standard Supabase instance
      // This automatically sets up SharedPreferences for Auth
      await Supabase.initialize(
        url: cleanUrl,
        publishableKey: cleanKey, 
        debug: kDebugMode,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      
      // 2. Initialize our managed admin client separately if needed
      // Note: We avoid creating a manual public client because it breaks PKCE storage
      _publicClient = Supabase.instance.client;

      if (cleanServiceKey.isNotEmpty) {
        _adminClient = SupabaseClient(
          cleanUrl, 
          cleanServiceKey,
          headers: {
            'apikey': cleanServiceKey,
            'Authorization': 'Bearer $cleanServiceKey',
          },
        );
      } else {
        _adminClient = _publicClient;
      }

      _isInitialized = true;
      debugPrint('Supabase initialized successfully via standard instance.');
    } catch (e) {
      if (e.toString().contains('already been initialized')) {
        _isInitialized = true;
        return;
      }
      rethrow;
    }
  }
}
