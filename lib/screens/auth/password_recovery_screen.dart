import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../core/supabase_config.dart';
import '../../../services/sms_service.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  ConsumerState<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends ConsumerState<PasswordRecoveryScreen> {
  int _step = 0; // 0: Email/Phone, 1: Code, 2: New Password
  final _controller = TextEditingController();
  String? _userId;
  String? _userPhone;
  String? _generatedCode;
  bool _isLoading = false;
  // Timer state
  Timer? _timer;
  int _secondsRemaining = 420; // 7 minutes

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _secondsRemaining = 420;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        timer.cancel();
      }
    });
  }

  String get _timerText {
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showMessage(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // Step 1: Request SMS from Supabase
  Future<void> _handleStep1() async {
    setState(() => _isLoading = true);
    try {
      // Use adminClient to bypass RLS and ensure explicit headers on Web
      final data = await SupabaseConfig.adminClient
          .from('users')
          .select('id, phone')
          .or('email.eq.${_controller.text.trim()},phone.eq.${_controller.text.trim()}')
          .maybeSingle();

      if (data == null) {
        _showMessage('User not found.');
        return;
      }
      _userId = data['id'];
      _userPhone = data['phone'] as String?;

      if (_userPhone == null || _userPhone!.isEmpty) {
        _showMessage('No phone number associated with this account.');
        return;
      }

      // Generate 6-digit code
      _generatedCode = List.generate(6, (_) => Random().nextInt(10).toString()).join();
      
      // Use Arkesel via SmsService
      final success = await SmsService.sendVerificationCodeSms(_userPhone!, _generatedCode!);

      if (success) {
        _startTimer();
        _showMessage('Verification code sent to $_userPhone');
        setState(() {
          _step = 1;
          _controller.clear();
        });
      } else {
        _showMessage('Failed to send verification code. Please check your connection or try again later.');
      }
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStep2() async {
    if (_controller.text.trim() == _generatedCode) {
      setState(() {
        _step = 2;
        _controller.clear();
      });
    } else {
      _showMessage('Invalid verification code. Please try again.');
    }
  }

  // Step 3: Verify and Update
  Future<void> _handleStep3(String password) async {
    setState(() => _isLoading = true);
    try {
      // Use SupabaseConfig.adminClient to perform admin operations
      // This requires the SUPABASE_SERVICE_ROLE_KEY to be correctly set in environment variables
      final admin = SupabaseConfig.adminClient.auth.admin;
      
      await admin.updateUserById(
        _userId!,
        attributes: AdminUserAttributes(password: password),
      );

      if (!mounted) return;
      _timer?.cancel();
      _showMessage('Password updated successfully!');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Failed to update password: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Password Recovery'), centerTitle: true),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_reset, size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: AppSpacing.l),
                    if (_step == 0) ...[
                      const Text('Enter your registered email or phone to receive a reset code.', textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.m),
                      TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Email or Phone', prefixIcon: Icon(Icons.person_outline))),
                      const SizedBox(height: AppSpacing.l),
                      SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _isLoading ? null : _handleStep1, child: const Text('Send Reset Code'))),
                    ] else if (_step == 1) ...[
                      Text('Enter the 6-digit code sent to your phone. It expires in: $_timerText', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.m),
                      TextField(controller: _controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '6-digit Code', prefixIcon: Icon(Icons.password_outlined))),
                      const SizedBox(height: AppSpacing.l),
                      SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _secondsRemaining > 0 ? _handleStep2 : null, child: const Text('Verify Code'))),
                    ] else ...[
                      _NewPasswordForm(onSave: _handleStep3, isLoading: _isLoading),
                    ]
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

class _NewPasswordForm extends StatefulWidget {
  final Function(String) onSave;
  final bool isLoading;
  const _NewPasswordForm({required this.onSave, required this.isLoading});

  @override
  State<_NewPasswordForm> createState() => _NewPasswordFormState();
}

class _NewPasswordFormState extends State<_NewPasswordForm> {
  final p1 = TextEditingController();
  final p2 = TextEditingController();
  bool _obscure = true;

  String get _strength {
    if (p1.text.isEmpty) return '';
    if (p1.text.length < 6) return 'Weak';
    if (RegExp(r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$').hasMatch(p1.text)) return 'Strong';
    return 'Medium';
  }

  Color get _strengthColor {
    switch (_strength) {
      case 'Weak': return Colors.red;
      case 'Medium': return Colors.orange;
      case 'Strong': return Colors.green;
      default: return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: p1,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'New Password',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (p1.text.isNotEmpty)
          Align(alignment: Alignment.centerLeft, child: Text('Strength: $_strength', style: TextStyle(color: _strengthColor, fontWeight: FontWeight.bold))),
        const SizedBox(height: 8),
        TextField(controller: p2, obscureText: _obscure, decoration: const InputDecoration(labelText: 'Confirm Password')),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: widget.isLoading ? null : () {
            if (p1.text == p2.text && p1.text.length >= 6) {
              widget.onSave(p1.text);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords must match and be at least 6 characters')));
            }
          },
          child: const Text('Update Password'),
        ),
      ],
    );
  }
}
