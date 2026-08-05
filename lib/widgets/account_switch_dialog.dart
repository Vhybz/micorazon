import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mi_corazon/models/user_model.dart';
import 'package:mi_corazon/services/user_provider.dart';
import 'package:mi_corazon/core/constants.dart';
import 'package:mi_corazon/services/auth_provider.dart';

class AccountSwitchDialog extends ConsumerStatefulWidget {
  final UserAccount targetUser;
  const AccountSwitchDialog({super.key, required this.targetUser});

  @override
  ConsumerState<AccountSwitchDialog> createState() => _AccountSwitchDialogState();

  static Future<bool?> show(BuildContext context, UserAccount user) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AccountSwitchDialog(targetUser: user),
    );
  }
}

class _AccountSwitchDialogState extends ConsumerState<AccountSwitchDialog> {
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
    if (widget.targetUser.passcode == null) {
      setState(() {
        _pinController.clear();
        _error = 'Passcode not set for this account. Use password to switch.';
      });
      return;
    }

    if (_pinController.text == widget.targetUser.passcode) {
      _switchAccount();
    } else {
      setState(() {
        _pinController.clear();
        _error = 'Incorrect passcode. Access Denied.';
        HapticFeedback.heavyImpact();
      });
    }
  }

  Future<void> _showPasswordFallback() async {
    final controller = TextEditingController();
    bool obscure = true;

    final success = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
          title: const Text('Switch with Password', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Enter password for ${widget.targetUser.email} to switch accounts.', style: const TextStyle(fontSize: 12)),
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
                  // Verify password by attempting to sign in
                  final response = await ref.read(authServiceProvider).signIn(widget.targetUser.email, controller.text);
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
              child: const Text('SWITCH'),
            ),
          ],
        ),
      ),
    );

    if (success == true) {
      _switchAccount();
    }
  }

  void _switchAccount() {
    // 1. Update the active user ID
    ref.read(currentUserIdProvider.notifier).state = widget.targetUser.id;
    ref.read(sessionUserProfileProvider.notifier).state = widget.targetUser;
    
    // 2. Clear existing lock state (assume switching to account means you have permission now)
    ref.read(passcodeUnlockedProvider.notifier).state = true;
    
    // 3. Clear navigation and return success
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
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
                _buildUserHeader(theme),
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
                    _keypadButton('Cancel', isAction: true, color: Colors.grey.shade400, onTap: () => Navigator.pop(context)),
                    _keypadButton('0'),
                    _keypadButton('Delete', isAction: true, color: const Color(0xFFFFF1EB), icon: Icons.backspace_outlined, iconColor: Colors.orange.shade800, onTap: _onDelete),
                  ],
                ),

                const SizedBox(height: 24),
                
                // Password Fallback
                TextButton(
                  onPressed: _showPasswordFallback,
                  child: const Text('USE ACCOUNT PASSWORD', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader(ThemeData theme) {
    final roleColor = _getRoleColor(widget.targetUser.role);
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: roleColor.withValues(alpha: 0.3), width: 4),
          ),
          child: ClipOval(
            child: widget.targetUser.photoUrl != null && widget.targetUser.photoUrl!.isNotEmpty
                ? Image.network(widget.targetUser.photoUrl!, fit: BoxFit.cover)
                : Container(
                    color: roleColor.withValues(alpha: 0.1),
                    child: Icon(_getRoleIcon(widget.targetUser.role), color: roleColor, size: 40),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.targetUser.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          'SWITCH TO ${widget.targetUser.role.toString().split('.').last.toUpperCase()}',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: roleColor, letterSpacing: 1.2),
        ),
        const SizedBox(height: 12),
        const Text(
          'Confirm security to continue',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _keypadButton(String label, {bool isAction = false, Color? color, IconData? icon, Color? iconColor, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.superAdmin: return Colors.black;
      case UserRole.admin: return Colors.purple;
      case UserRole.butcher: return AppColors.primaryMaroon;
      case UserRole.cashier: return Colors.blue;
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.superAdmin: return Icons.security;
      case UserRole.admin: return Icons.admin_panel_settings;
      case UserRole.butcher: return Icons.restaurant;
      case UserRole.cashier: return Icons.point_of_sale;
    }
  }
}
