import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_corazon/models/user_model.dart';
import 'package:mi_corazon/services/user_provider.dart';
import 'package:mi_corazon/core/constants.dart';
import 'package:mi_corazon/widgets/staff_switch_sheet.dart';
import 'package:mi_corazon/services/auth_provider.dart';

export 'package:mi_corazon/services/user_provider.dart' show passcodeUnlockedProvider;

class PasscodeGuard extends ConsumerStatefulWidget {
  final Widget child;
  const PasscodeGuard({super.key, required this.child});

  @override
  ConsumerState<PasscodeGuard> createState() => _PasscodeGuardState();
}

class _PasscodeGuardState extends ConsumerState<PasscodeGuard> {
  final TextEditingController _pinController = TextEditingController();
  String _error = '';
  bool _isVerifyingPassword = false;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    if (_pinController.text.length < 4) {
      setState(() {
        _pinController.text += number;
        _error = '';
      });
      
      if (_pinController.text.length == 4) {
        _verifyPasscode();
      }
    }
  }

  void _onDelete() {
    if (_pinController.text.isNotEmpty) {
      setState(() {
        _pinController.text = _pinController.text.substring(0, _pinController.text.length - 1);
        _error = '';
      });
    }
  }

  void _verifyPasscode() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    if (user.passcode == null) {
      setState(() {
        _pinController.clear();
        _error = 'Passcode not set. Please use password to unlock.';
      });
      return;
    }

    if (_pinController.text == user.passcode) {
      setState(() => _error = '');
      ref.read(passcodeUnlockedProvider.notifier).state = true;
    } else {
      setState(() {
        _pinController.clear();
        _error = 'Incorrect passcode. Access Denied.';
        HapticFeedback.heavyImpact();
      });
    }
  }

  Future<void> _showPasswordDialog() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final controller = TextEditingController();
    bool obscure = true;

    final success = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: const Text('Unlock with Password', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter your account password for ${user.email} to unlock.', style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
            ElevatedButton(
              onPressed: _isVerifyingPassword ? null : () async {
                setDialogState(() => _isVerifyingPassword = true);
                try {
                  final response = await ref.read(authServiceProvider).signIn(user.email, controller.text);
                  if (response.user != null) {
                    if (context.mounted) Navigator.pop(context, true);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Invalid password: ${e.toString()}'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  setDialogState(() => _isVerifyingPassword = false);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryMaroon, foregroundColor: Colors.white),
              child: const Text('UNLOCK'),
            ),
          ],
        ),
      ),
    );

    if (success == true) {
      ref.read(passcodeUnlockedProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // SECURITY: Clear PIN entries whenever the system is locked
    ref.listen<bool>(passcodeUnlockedProvider, (previous, next) {
      if (next == false) {
        _pinController.clear();
        if (mounted) setState(() => _error = '');
      }
    });

    final unlocked = ref.watch(passcodeUnlockedProvider);
    final user = ref.watch(currentUserProvider);
    final isLockedDown = ref.watch(systemLockdownProvider);

    // Only bypass if explicitly unlocked AND system is not in lockdown.
    if (unlocked && !isLockedDown) {
      return widget.child;
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Profile Section (Modified to match image aesthetic but with user info)
                _buildHeader(user),
                
                const SizedBox(height: 40),
                
                // Passcode Dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (index) {
                    final filled = _pinController.text.length > index;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled ? AppColors.primaryMaroon : (isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                        border: Border.all(color: filled ? AppColors.primaryMaroon : theme.dividerColor),
                      ),
                    );
                  }),
                ),
                
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text(_error, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
                  ),
                  
                const SizedBox(height: 40),
                
                // Keypad
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.6,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ...List.generate(9, (index) => _keypadButton('${index + 1}')),
                    _keypadButton('Cancel', isAction: true, color: Colors.grey.shade400, onTap: () => setState(() => _pinController.clear())),
                    _keypadButton('0'),
                    _keypadButton('Delete', isAction: true, color: const Color(0xFFFFF1EB), icon: Icons.backspace_outlined, iconColor: Colors.orange.shade800, onTap: _onDelete),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                // Password Fallback
                TextButton(
                  onPressed: _showPasswordDialog,
                  child: const Text('USE ACCOUNT PASSWORD', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                ),

                const SizedBox(height: 32),
                
                // Switch Account Option
                SafeArea(
                  top: false,
                  child: InkWell(
                    onTap: () => StaffSwitchSheet.show(context),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 20), // Added more bottom padding
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.switch_account_rounded, size: 20, color: AppColors.primaryMaroon),
                          const SizedBox(width: 8),
                          Text('SWITCH ACCOUNT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black.withValues(alpha: 0.8), letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(dynamic user) {
    return Column(
      children: [
        if (user != null && user is UserAccount && user.photoUrl != null && user.photoUrl!.isNotEmpty)
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryMaroon.withValues(alpha: 0.2), width: 4),
            ),
            child: ClipOval(
              child: Image.network(user.photoUrl!, fit: BoxFit.cover),
            ),
          )
        else
          const Icon(Icons.lock_person_rounded, size: 64, color: AppColors.primaryMaroon),
        
        const SizedBox(height: 24),
        Text(
          (user != null && user is UserAccount) ? '${user.firstName} ${user.surname}' : 'Security Check',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          (user != null && user is UserAccount) 
            ? 'Account Locked. Enter PIN to continue as ${user.activePrimaryRole.toString().split('.').last.toUpperCase()}.'
            : 'Enter your 4-digit security passcode to access this sensitive area.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 14),
        ),
      ],
    );
  }

  Widget _keypadButton(String label, {bool isAction = false, Color? color, IconData? icon, Color? iconColor, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => _onNumberPressed(label),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: color ?? (isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF5F5F5)),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: icon != null 
            ? Icon(icon, color: iconColor ?? (isDark ? Colors.white : Colors.black))
            : Text(
                label,
                style: TextStyle(
                  fontSize: isAction ? 11 : 22,
                  fontWeight: FontWeight.bold,
                  color: isAction ? Colors.black45 : (isDark ? Colors.white : Colors.black),
                ),
              ),
        ),
      ),
    );
  }
}
