import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../services/auth_provider.dart';
import '../services/user_provider.dart';
import '../models/user_model.dart';
import '../widgets/butcher_loading.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    
    _fadeAnimation = CurvedAnimation(
      parent: _controller, 
      curve: const Interval(0.0, 0.2, curve: Curves.easeIn),
    );
    
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.95, curve: Curves.easeInOut),
      ),
    );

    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    _controller.forward();
    
    // Fail-safe: Force navigation after 8 seconds no matter what
    final forceTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        debugPrint('Splash: FAIL-SAFE TRIGGERED. Forcing navigation to onboarding.');
        Navigator.pushReplacementNamed(context, '/onboarding');
      }
    });

    // Minimum 4 seconds of splash animation
    await Future.delayed(const Duration(seconds: 4));
    
    if (!mounted) {
      forceTimer.cancel();
      return;
    }

    try {
      final currentUser = ref.read(authServiceProvider).currentUser;
      
      if (currentUser != null) {
        ref.read(currentUserIdProvider.notifier).state = currentUser.id;
        
        try {
          // Add a timeout to prevent hanging on Splash if network is slow/blocked
          final users = await ref.read(userProvider.notifier).service.getUsers()
              .timeout(const Duration(seconds: 3));
              
          UserAccount? userAccount;
          try {
            userAccount = users.firstWhere((u) => u.id == currentUser.id);
          } catch (_) {
            userAccount = null;
          }

          if (userAccount != null && userAccount.status == AccountStatus.approved) {
            forceTimer.cancel();
            if (mounted) {
              switch (userAccount.activePrimaryRole) {
                case UserRole.admin:
                  Navigator.pushReplacementNamed(context, '/admin');
                  break;
                case UserRole.butcher:
                  Navigator.pushReplacementNamed(context, '/butcher');
                  break;
                case UserRole.cashier:
                  Navigator.pushReplacementNamed(context, '/cashier');
                  break;
                case UserRole.superAdmin:
                  Navigator.pushReplacementNamed(context, '/admin/super');
                  break;
              }
            }
            return;
          }
        } catch (e) {
          debugPrint('Splash Auth Error (Likely Timeout): $e');
        }
      }
    } catch (e) {
      debugPrint('Splash: Unexpected auth access error: $e');
    }

    forceTimer.cancel();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primary,
              HSLColor.fromColor(theme.colorScheme.primary).withLightness(0.15).toColor(),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildDecor(top: -100, left: -100, size: 300),
            _buildDecor(bottom: -50, right: -50, size: 200),
            
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 6),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/logo/logo.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: const Column(
                        children: [
                          Text(
                            'Mi~CORAZON',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                            ),
                          ),
                          Text(
                            'FRESHMEAT BUTCHERY',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 50),
                    
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: const ButcherLoading(size: 160),
                    ),

                    const SizedBox(height: 20),
                    
                    SizedBox(
                      width: 200,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: _progressAnimation.value,
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Preparing Fresh Cuts... ${(_progressAnimation.value * 100).toInt()}%',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecor({double? top, double? left, double? right, double? bottom, required double size}) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.03),
        ),
      ),
    );
  }
}
