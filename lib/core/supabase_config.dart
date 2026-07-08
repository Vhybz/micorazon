import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static late SupabaseClient _adminClient;
  static SupabaseClient get adminClient => _adminClient;

  static Future<void> initialize() async {
    String url = '';
    String anonKey = '';
    try {
      debugPrint('Supabase: Initializing with .env configuration...');
      
      // Priority 1: Environment Variables (--dart-define)
      url = const String.fromEnvironment('SUPABASE_URL');
      anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

      // Priority 2: .env file
      if (url.isEmpty) url = dotenv.env['SUPABASE_URL'] ?? '';
      if (anonKey.isEmpty) anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

      // Priority 3: Hardcoded Fallback (Sync with your current project)
      if (url.isEmpty) {
        url = 'https://rdlwqnnzbtxwyasdebkj.supabase.co'; 
        debugPrint('Supabase: Warning! Fallback URL used.');
      }
      
      if (anonKey.isEmpty) {
        anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJkbHdxbm56YnR4d3lhc2RlYmtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExMDkwMzMsImV4cCI6MjA5NjY4NTAzM30.IJwhUmZ1xiGMCCHUGDbD5M1zcKbqXOtuPg-xGISluOQ';
      }

      final cleanUrl = url.trim();
      final cleanKey = anonKey.trim();

      debugPrint('--- CONNECTION AUDIT ---');
      debugPrint('PROJECT URL: $cleanUrl');
      if (cleanUrl.contains('rdlwqnnzbtxwyasdebkj')) {
        debugPrint('STATUS: Using CORRECT Supabase Project (rdlwqnnzbtxwyasdebkj)');
      } else {
        debugPrint('STATUS: !!! WARNING: UNKNOWN PROJECT URL !!!');
      }
      debugPrint('SOURCE: ${dotenv.env.containsKey("SUPABASE_URL") ? ".env file" : "Hardcoded Fallback/Override"}');
      debugPrint('-----------------------');

      if (cleanUrl.isEmpty || !cleanUrl.startsWith('http')) {
        throw Exception('Supabase URL is empty or invalid. Check your .env file.');
      }

      await Supabase.initialize(
        url: cleanUrl,
        publishableKey: cleanKey,
        debug: kDebugMode,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
        ),
      );
      
      // The null check here is causing the error if the key is missing in .env
      final serviceKey = dotenv.env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';
      _adminClient = SupabaseClient(cleanUrl, serviceKey);

      
      debugPrint('Supabase initialized successfully.');
    } catch (e) {
      if (e.toString().contains('already been initialized')) {
        debugPrint('Supabase was already initialized.');
        return;
      }
      debugPrint('Supabase Initialization Error Details: $e');
      throw Exception('Supabase Init Failed: $e. URL used: $url');
    }
  }

  static SupabaseClient get client {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('CRITICAL: Supabase.instance accessed before initialization.');
      rethrow;
    }
  }
}
