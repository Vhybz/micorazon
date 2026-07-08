import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../core/app_strings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/user_provider.dart';
import '../services/auth_provider.dart';
import 'auth/password_recovery_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage(AppStrings.entryRequiredTitle, AppStrings.entryRequiredMessage);
      return;
    }

    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showMessage(AppStrings.invalidEmailTitle, AppStrings.invalidEmailMessage);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ref.read(authServiceProvider).signIn(email, password);
      
      if (response.user != null) {
        final notifier = ref.read(userProvider.notifier);
        
        // 1. Try local state first
        UserAccount? userAccount;
        try {
          userAccount = ref.read(userProvider).firstWhere((u) => u.id == response.user!.id);
        } catch (_) {
          // 2. Fallback: Fetch directly from Supabase if not in local state yet
          userAccount = await notifier.fetchUserById(response.user!.id);
        }

        if (userAccount == null) {
          await GlobalLogout.perform(ref);
          if (mounted) {
            _showMessage(AppStrings.profileMissingTitle, AppStrings.profileMissingMessage);
          }
          return;
        }

        if (userAccount.status == AccountStatus.pending) {
          await GlobalLogout.perform(ref);
          if (mounted) {
            _showMessage(
              AppStrings.approvalPendingTitle, 
              AppStrings.approvalPendingMessage,
              isWarning: true
            );
          }
          return;
        }

        if (userAccount.status == AccountStatus.suspended) {
          await GlobalLogout.perform(ref);
          if (mounted) {
             _showMessage(AppStrings.accountSuspendedTitle, AppStrings.accountSuspendedMessage, isError: true);
          }
          return;
        }

        // Successful login
        ref.read(currentUserIdProvider.notifier).state = userAccount.id;

        if (mounted) {
          switch (userAccount.activePrimaryRole) {
            case UserRole.admin:
              Navigator.pushReplacementNamed(context, '/admin');
              break;
            case UserRole.superAdmin:
              Navigator.pushReplacementNamed(context, '/admin/super');
              break;
            case UserRole.butcher:
              Navigator.pushReplacementNamed(context, '/butcher');
              break;
            case UserRole.cashier:
              Navigator.pushReplacementNamed(context, '/cashier');
              break;
          }
        }
      }
    } catch (e) {
      if (mounted) {
        String title = AppStrings.loginFailedTitle;
        String errorMessage = e.toString();
        
        // Handle common Supabase Auth errors gracefully
        if (errorMessage.contains('Invalid login credentials')) {
          errorMessage = AppStrings.invalidCredentialsError;
        } else if (errorMessage.contains('Email not confirmed')) {
          errorMessage = AppStrings.emailNotConfirmedError;
        } else if (errorMessage.contains('User not found')) {
          errorMessage = AppStrings.userNotFoundError;
        } else if (errorMessage.contains('network')) {
          errorMessage = AppStrings.networkError;
        }

        _showMessage(title, errorMessage, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String title, String message, {bool isError = false, bool isWarning = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : (isWarning ? Icons.warning_amber_rounded : Icons.info_outline),
              color: isError ? Colors.red : (isWarning ? Colors.orange : AppColors.primaryMaroon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title, 
                style: const TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.ok, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;
    final bool isMobile = size.width < 600;

    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark 
                ? [const Color(0xFF121212), const Color(0xFF000000)]
                : [theme.colorScheme.primary, HSLColor.fromColor(theme.colorScheme.primary).withLightness(0.15).toColor()],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? AppSpacing.m : AppSpacing.l),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                width: size.width * (isMobile ? 0.9 : 0.8),
                padding: EdgeInsets.all(isMobile ? AppSpacing.l : AppSpacing.xl),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(AppRadius.l),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.3), 
                      blurRadius: 20, 
                      offset: const Offset(0, 10)
                    ),
                  ],
                  border: isDark ? Border.all(color: theme.dividerColor) : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: isMobile ? 100 : 120,
                      height: isMobile ? 100 : 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1), width: 6),
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo/logo.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    Text(
                      AppStrings.loginTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isMobile ? 24 : 28, 
                        fontWeight: FontWeight.bold, 
                        color: theme.colorScheme.primary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      AppStrings.loginSubtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.w600, 
                        color: theme.colorScheme.primary.withValues(alpha: 0.8), 
                      letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 2,
                      width: 40,
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.signInHeader, 
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                      decoration: const InputDecoration(
                        labelText: AppStrings.emailLabel,
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.m),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                      decoration: InputDecoration(
                        labelText: AppStrings.passwordLabel,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                        ),
                        child: _isLoading 
                            ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                            : const Text(AppStrings.loginButton, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.l),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => PasswordRecoveryScreen()),
                            );
                          },
                          child: const Text('Forgot Password?', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 10),
                        Text(AppStrings.noAccountText, style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/signup'),
                          child: Text(
                            AppStrings.registerLink,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                            )
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
