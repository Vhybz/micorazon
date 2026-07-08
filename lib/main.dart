import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/admin/admin_dashboard.dart';
import 'screens/admin/sales_reports_screen.dart';
import 'screens/admin/debt_management_screen.dart';
import 'screens/admin/inventory_control_screen.dart';
import 'screens/admin/expense_management_screen.dart';
import 'screens/admin/customer_management_screen.dart';
import 'screens/admin/staff_management_screen.dart';
import 'screens/admin/system_settings_screen.dart';
import 'screens/admin/butcher_analytics_screen.dart';
import 'screens/admin/recents_screen.dart';
import 'screens/admin/system_maintenance_screen.dart';
import 'screens/admin/tax_compliance_screen.dart';
import 'screens/admin/salary_management_screen.dart';
import 'screens/butcher/documents_screen.dart';
import 'screens/cashier/cashier_pos.dart';
import 'screens/cashier/stock_verification_screen.dart';
import 'screens/butcher/butcher_shell.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/about_screen.dart';
import 'services/theme_provider.dart';
import 'services/sync_provider.dart';
import 'core/supabase_config.dart';
import 'services/push_notification_service.dart';
import 'services/offline_sync_service.dart';
import 'screens/admin/super_admin_screen.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 1. Load Environment Variables
    try {
      await dotenv.load(fileName: ".env");
    } catch (_) {
      try {
        await dotenv.load(fileName: "assets/.env");
      } catch (e) {
        debugPrint('CRITICAL: .env could not be loaded. AI and Cloud features may fail: $e');
      }
    }

    if (kIsWeb) {
      usePathUrlStrategy();
    }

    // 2. Unified Supabase Initialization
    try {
      await SupabaseConfig.initialize();
      if (kDebugMode) {
        debugPrint('SYSTEM STATUS: Cloud Backend Connected.');
      }
    } catch (e) {
      debugPrint('SUPABASE BOOT FAILURE: $e');
      // On web, if this fails, we want to show the initialization error screen
      rethrow;
    }

    // 3. Initialize Offline Sync Engine (Hive)
    await OfflineSyncService.initialize();

    // 4. Initialize System Tray Notifications (Graceful failure)
    try {
      await PushNotificationService.initialize();
    } catch (e) {
      debugPrint('Push Notification initialization failed: $e');
    }

    // Enable edge-to-edge support
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    
    runApp(
      const ProviderScope(
        child: MeatShopApp(),
      ),
    );
  } catch (e, stack) {
    debugPrint('CRITICAL INITIALIZATION FAILURE: $e');
    debugPrint('STACK TRACE: $stack');
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: InitializationErrorScreen(
          errorMessage: e.toString(),
          stackTrace: stack.toString(),
        ),
      ),
    );
  }
}

class InitializationErrorScreen extends StatelessWidget {
  final String? errorMessage;
  final String? stackTrace;
  const InitializationErrorScreen({super.key, this.errorMessage, this.stackTrace});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: const Color(0xFF6B1111), // App Maroon
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 80),
                const SizedBox(height: 32),
                const Text(
                  'Configuration Missing',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: 800,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          errorMessage!.contains('minified') 
                            ? 'Technical Error (Minified): $errorMessage\n\nThis usually means Supabase failed to initialize on Web. Check your browser console (F12) for the exact error.'
                            : 'Technical Error: $errorMessage',
                          style: const TextStyle(color: Colors.yellowAccent, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        if (stackTrace != null) ...[
                          const Divider(color: Colors.white24),
                          Text(
                            stackTrace!,
                            style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                            maxLines: 15,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  'The application cannot connect to the database. Please ensure your configuration is correct.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16),
                ),
                const SizedBox(height: 40),
                _buildErrorBox(
                  'LOCAL DEVELOPMENT (VS Code/Android Studio)',
                  'Ensure you have a .env file in the root folder with:\nSUPABASE_URL=your_url\nSUPABASE_ANON_KEY=your_key',
                ),
                const SizedBox(height: 16),
                _buildErrorBox(
                  'PRODUCTION/WEB DEPLOYMENT',
                  'Provide these as environment variables during build using --dart-define or --dart-define-from-file.',
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => _showManualConfigDialog(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF6B1111),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('ENTER CONFIG MANUALLY', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),
                const Text(
                  'After updating configuration, please restart the app or refresh your browser.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBox(String title, String content) {
    return Container(
      width: 600,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
          ),
        ],
      ),
    );
  }
}

void _showManualConfigDialog(BuildContext context) {
  final urlController = TextEditingController();
  final keyController = TextEditingController();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Manual Supabase Config'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: urlController,
            decoration: const InputDecoration(labelText: 'Supabase URL', hintText: 'https://xxx.supabase.co'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: keyController,
            decoration: const InputDecoration(labelText: 'Anon Key'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        ElevatedButton(
          onPressed: () async {
            if (urlController.text.isNotEmpty && keyController.text.isNotEmpty) {
              try {
                await Supabase.initialize(
                  url: urlController.text.trim(),
                  publishableKey: keyController.text.trim(),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  // Since we are in a minimal MaterialApp, just showing success
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Config saved! Please refresh the page.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Initialization failed: $e')),
                  );
                }
              }
            }
          },
          child: const Text('INITIALIZE'),
        ),
      ],
    ),
  );
}

class MeatShopApp extends ConsumerWidget {
  const MeatShopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    // Initialize background sync
    ref.watch(syncProvider);

    return MaterialApp(
      title: 'Mi~Corazon Freshmeat Butchery',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getLightTheme(themeState.primaryColor),
      darkTheme: AppTheme.getDarkTheme(themeState.primaryColor),
      themeMode: themeState.mode,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/admin': (context) => const AdminDashboard(),
        '/admin/super': (context) => const SuperAdminScreen(),
        '/admin/sales': (context) => const SalesReportsScreen(),
        '/admin/expenses': (context) => const ExpenseManagementScreen(),
        '/admin/customers': (context) => const CustomerManagementScreen(),
        '/admin/documents': (context) => const DocumentsScreen(),
        '/admin/debts': (context) => const DebtManagementScreen(),
        '/admin/stock': (context) => const InventoryControlScreen(),
        '/admin/tax': (context) => const TaxComplianceScreen(),
        '/admin/staff': (context) => const StaffManagementScreen(),
        '/admin/salaries': (context) => const SalaryManagementScreen(),
        '/admin/butcher': (context) => const ButcherAnalyticsScreen(),
        '/admin/recents': (context) => const RecentsScreen(),
        '/admin/maintenance': (context) => const SystemMaintenanceScreen(),
        '/admin/settings': (context) => const SystemSettingsScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/about': (context) => const AboutScreen(),
        '/cashier': (context) => const CashierPOS(),
        '/cashier/verify-stock': (context) => const StockVerificationScreen(),
        '/butcher': (context) => const ButcherShell(),
      },
    );
  }
}
