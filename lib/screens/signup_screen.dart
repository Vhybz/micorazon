import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants.dart';
import '../models/user_model.dart';
import '../models/branch_model.dart';
import '../services/user_provider.dart';
import '../services/branch_provider.dart';
import '../services/auth_provider.dart';
import '../services/sms_service.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _branchNameController = TextEditingController();
  final _branchLocationController = TextEditingController();
  
  DateTime? _selectedDob;
  String? _selectedGender;
  UserRole _selectedRole = UserRole.cashier;
  String? _selectedBranchCode;
  bool _isCreatingBranch = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _phoneExists = false;
  Timer? _debounce;

  double _strength = 0;
  String _strengthLabel = 'None';
  Color _strengthColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_checkPasswordStrength);
    _phoneController.addListener(_onPhoneChanged);
    
    // Ensure we have current user data loaded if an admin is logged in
    // and using this screen to create a staff account.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(currentUserIdProvider) != null) {
        ref.read(userProvider.notifier).loadUsers(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _passwordController.removeListener(_checkPasswordStrength);
    _phoneController.removeListener(_onPhoneChanged);
    _debounce?.cancel();
    _firstNameController.dispose();
    _surnameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength() {
    final pass = _passwordController.text;
    double score = 0;

    if (pass.isEmpty) {
      setState(() {
        _strength = 0;
        _strengthLabel = 'None';
        _strengthColor = Colors.grey;
      });
      return;
    }

    if (pass.length >= 6) score += 0.25;
    if (pass.length >= 10) score += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(pass)) score += 0.25;
    if (RegExp(r'[0-9]').hasMatch(pass)) score += 0.15;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(pass)) score += 0.1;

    setState(() {
      _strength = score;
      if (score <= 0.25) {
        _strengthLabel = 'Weak';
        _strengthColor = Colors.red;
      } else if (score <= 0.6) {
        _strengthLabel = 'Fair';
        _strengthColor = Colors.orange;
      } else if (score <= 0.8) {
        _strengthLabel = 'Good';
        _strengthColor = Colors.blue;
      } else {
        _strengthLabel = 'Strong';
        _strengthColor = Colors.green;
      }
    });
  }

  void _onPhoneChanged() {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final phone = _phoneController.text.trim();
      if (phone.length == 10) {
        final exists = await ref.read(userProvider.notifier).checkPhoneExists(phone);
        if (mounted) {
          setState(() {
            _phoneExists = exists;
          });
        }
      } else {
        if (_phoneExists) {
          setState(() {
            _phoneExists = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final branchesAsync = ref.watch(branchesProvider);
    final branches = branchesAsync.value ?? [];
    final noBranchesExist = branches.isEmpty && !branchesAsync.isLoading;
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
              padding: EdgeInsets.symmetric(
                vertical: isMobile ? 20 : 40, 
                horizontal: isMobile ? 10 : 20
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 550),
                width: size.width * (isMobile ? 0.95 : 0.8),
                padding: EdgeInsets.all(isMobile ? AppSpacing.l : AppSpacing.xl),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(AppRadius.l),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.4), blurRadius: 20, offset: const Offset(0, 10)),
                  ],
                  border: isDark ? Border.all(color: theme.dividerColor) : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fixed Header Section
                    Container(
                      padding: EdgeInsets.all(isMobile ? AppSpacing.m : AppSpacing.xl),
                      child: Column(
                        children: [
                          Container(
                            width: isMobile ? 80 : 100,
                            height: isMobile ? 80 : 100,
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
                              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1), width: 4),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/logo/logo.jpg',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.m),
                          Text(
                            'Staff Registration',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isMobile ? 20 : 24, 
                              fontWeight: FontWeight.bold, 
                              color: theme.colorScheme.primary,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            'Apply for a Mi~Corazon team account',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: theme.dividerColor),
                    // Form Section
                    Padding(
                      padding: EdgeInsets.all(isMobile ? AppSpacing.m : AppSpacing.xl),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            if (isMobile) ...[
                              _buildTextField(context, _firstNameController, 'First Name', Icons.person_outline, isName: true),
                              const SizedBox(height: AppSpacing.m),
                              _buildTextField(context, _surnameController, 'Surname', Icons.person_outline, isName: true),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildTextField(context, _firstNameController, 'First Name', Icons.person_outline, isName: true),
                                  ),
                                  const SizedBox(width: AppSpacing.m),
                                  Expanded(
                                    child: _buildTextField(context, _surnameController, 'Surname', Icons.person_outline, isName: true),
                                  ),
                                ],
                              ),
                            const SizedBox(height: AppSpacing.m),
                            
                            _buildTextField(context, _emailController, 'Email Address', Icons.email_outlined, isEmail: true),
                            const SizedBox(height: AppSpacing.m),
                            
                            _buildTextField(context, _phoneController, 'Phone Number', Icons.phone_android_outlined, isPhone: true),
                            const SizedBox(height: AppSpacing.m),
                            
                            if (isMobile) ...[
                              DropdownButtonFormField<String>(
                                initialValue: _selectedGender,
                                decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc)),
                                items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                onChanged: (v) => setState(() => _selectedGender = v),
                                validator: (v) => v == null ? 'Required' : null,
                              ),
                              const SizedBox(height: AppSpacing.m),
                              _buildDatePickerTrigger(context, theme),
                            ] else
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _selectedGender,
                                      decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.wc)),
                                      items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                                      onChanged: (v) => setState(() => _selectedGender = v),
                                      validator: (v) => v == null ? 'Required' : null,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.m),
                                  Expanded(
                                    child: _buildDatePickerTrigger(context, theme),
                                  ),
                                ],
                              ),
                            const SizedBox(height: AppSpacing.m),
                            
                            DropdownButtonFormField<UserRole>(
                              initialValue: _selectedRole,
                              decoration: const InputDecoration(labelText: 'Applying For Role', prefixIcon: Icon(Icons.work_outline)),
                              items: [UserRole.cashier, UserRole.butcher, UserRole.admin].map((r) => DropdownMenuItem(value: r, child: Text(r.name.toUpperCase()))).toList(),
                              onChanged: (v) {
                                setState(() {
                                  _selectedRole = v!;
                                  if (v != UserRole.admin) _isCreatingBranch = false;
                                });
                              },
                            ),
                            const SizedBox(height: AppSpacing.m),
                            
                            if (_selectedRole == UserRole.admin) ...[
                              CheckboxListTile(
                                title: Text('Setup New Branch?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                                subtitle: Text(noBranchesExist ? 'Required: No branches found in system.' : 'Create a separate business unit', style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                                value: _isCreatingBranch || noBranchesExist,
                                onChanged: noBranchesExist ? null : (v) => setState(() => _isCreatingBranch = v!),
                                activeColor: theme.colorScheme.primary,
                                dense: true,
                              ),
                              const SizedBox(height: AppSpacing.m),
                            ] else if (noBranchesExist) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'No branches found. Please register as an Admin to setup the first shop location.',
                                        style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.m),
                            ],

                            if (_selectedRole == UserRole.admin && (_isCreatingBranch || noBranchesExist)) ...[
                              _buildTextField(context, _branchNameController, 'Shop/Branch Name', Icons.store_mall_directory_outlined),
                              const SizedBox(height: AppSpacing.m),
                              _buildTextField(context, _branchLocationController, 'Branch Location (City/Town)', Icons.location_on_outlined),
                              const SizedBox(height: AppSpacing.m),
                            ] else ...[
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _selectedBranchCode,
                                decoration: const InputDecoration(labelText: 'Select Working Branch', prefixIcon: Icon(Icons.map_outlined)),
                                items: branches.map((b) => DropdownMenuItem(value: b.code, child: Text('${b.name} (${b.location})', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (v) => setState(() => _selectedBranchCode = v),
                                validator: (v) => v == null ? 'Please select a branch' : null,
                              ),
                              const SizedBox(height: AppSpacing.m),
                            ],
                            
                            _buildTextField(context, _passwordController, 'Password', Icons.lock_outline, isPassword: true),
                            if (_passwordController.text.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('Strength: ', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                                      Text(_strengthLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _strengthColor)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: _strength,
                                    backgroundColor: isDark ? Colors.white10 : Colors.grey.shade200,
                                    valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: AppSpacing.m),
                            _buildTextField(context, _confirmPasswordController, 'Confirm Password', Icons.lock_reset_outlined, isPassword: true),
                            
                            const SizedBox(height: AppSpacing.xl),
                            
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleSignup,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.s)),
                                ),
                                child: _isLoading 
                                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                                    : const Text('Submit Application', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            
                            const SizedBox(height: AppSpacing.l),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Already have an account?', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                                TextButton(
                                  onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                                  child: Text('Login', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildTextField(BuildContext context, TextEditingController controller, String label, IconData icon, {bool isEmail = false, bool isPassword = false, bool isPhone = false, bool isName = false}) {
    bool obscure = false;
    if (isPassword) {
      if (controller == _passwordController) {
        obscure = _obscurePassword;
      } else if (controller == _confirmPasswordController) {
        obscure = _obscureConfirmPassword;
      }
    }

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: isEmail ? TextInputType.emailAddress : (isPhone ? TextInputType.phone : (isName ? TextInputType.name : TextInputType.text)),
      inputFormatters: [
        if (isEmail || isPassword || isPhone) FilteringTextInputFormatter.deny(RegExp(r'\s')), // No spaces in these
        if (isName) FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-]')), // Names: Letters, spaces, and hyphens
        if (isPhone) ...[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
      ],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                onPressed: () {
                  setState(() {
                    if (controller == _passwordController) {
                      _obscurePassword = !_obscurePassword;
                    } else {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    }
                  });
                },
              )
            : null,
        hintText: isPhone ? '10 digits' : null,
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (isEmail && !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) return 'Invalid email';
        if (isPassword) {
           if (v.length < 6) return 'Min 6 characters';
           if (controller == _confirmPasswordController && v != _passwordController.text) return 'Passwords do not match';
        }
        if (isPhone) {
          if (v.length != 10) return 'Exactly 10 digits required';
        }
        if (isName && v.length < 2) return 'Too short';
        return null;
      },
    );
  }

  Future<void> _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final userNotifier = ref.read(userProvider.notifier);
        final branchesAsync = ref.read(branchesProvider);
        final noBranchesExist = (branchesAsync.value ?? []).isEmpty;
        final String email = _emailController.text.trim();
        final String password = _passwordController.text;
        String? branchCode = _selectedBranchCode;

        // Ensure user list is up to date for checking existing profile
        await userNotifier.loadUsers(silent: true);
        final existingProfiles = ref.read(userProvider);
        final existingProfile = existingProfiles.where((u) => u.email.toLowerCase() == email.toLowerCase()).firstOrNull;

        if (_selectedRole == UserRole.admin && (_isCreatingBranch || noBranchesExist)) {
          final String bName = _branchNameController.text.trim();
          final String location = _branchLocationController.text.trim();
          final String random = (100 + (DateTime.now().millisecond % 900)).toString();
          
          branchCode = '${bName.replaceAll(' ', '').toUpperCase()}_${location.replaceAll(' ', '').toUpperCase()}_$random';
          
          final newBranch = Branch(
            code: branchCode,
            name: bName,
            location: location,
          );
          
          await ref.read(branchesProvider.notifier).addBranch(newBranch);
        }

        final authResponse = await ref.read(authServiceProvider).signUp(email, password);
        
        if (authResponse.user != null) {
          final adminExists = await userNotifier.checkIfAnyAdminExists();
          final isFirstAdmin = !adminExists && _selectedRole == UserRole.admin;
          
          debugPrint('Signup Trace: AdminExists=$adminExists, SelectedRole=$_selectedRole, IsFirstAdmin=$isFirstAdmin');
          
          final newUser = UserAccount(
            id: authResponse.user!.id,
            firstName: _firstNameController.text.trim(),
            surname: _surnameController.text.trim(),
            email: email,
            phone: _phoneController.text.trim(),
            gender: _selectedGender,
            dob: _selectedDob,
            role: existingProfile?.role ?? _selectedRole,
            branchCode: existingProfile?.branchCode ?? branchCode,
            status: existingProfile != null ? AccountStatus.approved : (isFirstAdmin ? AccountStatus.approved : AccountStatus.pending),
            enabledPermissions: existingProfile?.enabledPermissions ?? (isFirstAdmin 
              ? {
                  '/admin',
                  '/admin/sales', 
                  '/admin/expenses', 
                  '/admin/customers', 
                  '/admin/debts', 
                  '/admin/stock', 
                  '/admin/staff',
                  '/admin/salaries',
                  '/cashier', 
                  '/butcher', 
                  '/settings'
                } 
              : {'/settings'}),
          );

          try {
            await userNotifier.addAccount(newUser);
            if (_selectedRole == UserRole.admin && (_isCreatingBranch || noBranchesExist)) {
              await ref.read(branchesProvider.notifier).setBranchAdmin(branchCode!, newUser.id);
            }
            
            // SMS Notifications (Best effort)
            try {
              if (existingProfile != null) {
                await SmsService.sendStaffOnboardingSms(newUser);
              } else {
                await SmsService.sendSignupConfirmationSms(newUser, isFirstAdmin);
              }
              if (!isFirstAdmin && existingProfile == null) {
                final allUsers = ref.read(userProvider);
                await SmsService.sendApprovalRequestSms(newUser, allUsers);
              }
            } catch (smsErr) {
              debugPrint('Signup SMS Error: $smsErr');
            }

            if (mounted) {
              _showApprovalDialog(isAutoApproved: isFirstAdmin || existingProfile != null);
            }
          } catch (dbError) {
            debugPrint('Signup Database Error: $dbError');
            if (mounted) {
              _showErrorDialog('Profile Creation Failed', 'Account was created but we couldn\'t save your profile details. Please contact support. Error: $dbError');
            }
          }
        } else {
           if (mounted) _showErrorDialog('Auth Failed', 'Account creation returned no user. Please try again.');
        }
      } catch (e) {
        debugPrint('Signup Catch Error: $e');
        if (mounted) {
          String errorMsg = e.toString();
          if (errorMsg.contains('User already registered')) {
            errorMsg = 'This email address is already in use. Please log in instead.';
          } else if (errorMsg.contains('weak_password')) {
            errorMsg = 'Your password is too weak. Please use a stronger password.';
          }
          _showErrorDialog('Registration Error', errorMsg);
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildDatePickerTrigger(BuildContext context, ThemeData theme) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(2000),
          firstDate: DateTime(1950),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
        );
        if (picked != null) setState(() => _selectedDob = picked);
      },
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor), 
          borderRadius: BorderRadius.circular(AppRadius.s),
          color: theme.inputDecorationTheme.fillColor,
        ),
        child: Row(
          children: [
            Icon(Icons.cake_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedDob == null ? 'Date of Birth' : DateFormat('yyyy-MM-dd').format(_selectedDob!), 
                style: TextStyle(
                  fontSize: 12, 
                  color: _selectedDob == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title, 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Text(message, style: const TextStyle(fontSize: 13)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showApprovalDialog({bool isAutoApproved = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.l)),
        title: Text(isAutoApproved ? 'Registration Successful' : 'Application Submitted'),
        content: Text(isAutoApproved 
          ? 'Your account has been created and approved. You can now log in to access the system.' 
          : 'Your registration is pending administrator approval. You will be notified via SMS once approved.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }
}
