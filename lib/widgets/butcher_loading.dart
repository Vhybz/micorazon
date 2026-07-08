import 'package:flutter/material.dart';
import 'dart:math' as math;

class ButcherLoading extends StatefulWidget {
  final double size;
  const ButcherLoading({super.key, this.size = 150});

  @override
  State<ButcherLoading> createState() => _ButcherLoadingState();
}

class _ButcherLoadingState extends State<ButcherLoading> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _knifeAnimation;
  late Animation<double> _meatVibration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _knifeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.3, end: 0.45).chain(CurveTween(curve: Curves.easeInQuint)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.45, end: 0.45),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.45, end: -0.3).chain(CurveTween(curve: Curves.easeOutCirc)),
        weight: 50,
      ),
    ]).animate(_controller);

    _meatVibration = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 45),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 6).chain(CurveTween(curve: Curves.elasticIn)),
        weight: 5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 6, end: 0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 50,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double currentSize = math.min(widget.size, constraints.maxHeight);
        return SizedBox(
          width: currentSize,
          height: currentSize,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Meat piece
                  Transform.translate(
                    offset: Offset(0, currentSize * 0.15 + _meatVibration.value),
                    child: _buildMeat(currentSize),
                  ),
                  
                  // Larger Cleaver
                  Positioned(
                    top: 0,
                    child: Transform.translate(
                      offset: Offset(0, _knifeAnimation.value * currentSize * 0.5),
                      child: Transform.rotate(
                        angle: _knifeAnimation.value * 0.15,
                        child: _buildRealisticCleaver(currentSize),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    );
  }

  Widget _buildMeat(double currentSize) {
    return Container(
      width: currentSize * 0.7,
      height: currentSize * 0.4,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB71C1C), Color(0xFFD32F2F), Color(0xFFC62828)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(currentSize * 0.1),
          topRight: Radius.circular(currentSize * 0.25),
          bottomLeft: Radius.circular(currentSize * 0.1),
          bottomRight: Radius.circular(currentSize * 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: CustomPaint(
        painter: MeatTexturePainter(),
      ),
    );
  }

  Widget _buildRealisticCleaver(double currentSize) {
    final knifeSize = currentSize * 0.75; // 25% bigger
    return SizedBox(
      width: knifeSize,
      height: knifeSize * 0.6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Blade
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: knifeSize * 0.55,
              height: knifeSize * 0.45,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFE0E0E0), // Top shine
                    Color(0xFF9E9E9E), // Mid steel
                    Color(0xFF757575), // Bottom dark
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(2),
                  bottomLeft: Radius.circular(2),
                  bottomRight: Radius.circular(12),
                  topRight: Radius.circular(4),
                ),
                border: const Border(
                  bottom: BorderSide(color: Colors.white, width: 2), // Sharpened edge
                ),
              ),
              child: Stack(
                children: [
                  // Hanging hole
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                    ),
                  ),
                  // Blade highlights
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      width: knifeSize * 0.5,
                      height: 1,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Handle
          Positioned(
            left: knifeSize * 0.05,
            top: knifeSize * 0.15,
            child: Transform.rotate(
              angle: -math.pi / 20,
              child: Container(
                width: knifeSize * 0.35,
                height: knifeSize * 0.12,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4E342E), Color(0xFF3E2723)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(2, 2)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(3, (i) => Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(color: Color(0xFFBDBDBD), shape: BoxShape.circle),
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MeatTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path();
    path.moveTo(size.width * 0.2, size.height * 0.2);
    path.quadraticBezierTo(size.width * 0.4, size.height * 0.5, size.width * 0.1, size.height * 0.8);
    
    path.moveTo(size.width * 0.5, size.height * 0.1);
    path.quadraticBezierTo(size.width * 0.7, size.height * 0.4, size.width * 0.6, size.height * 0.9);
    
    path.moveTo(size.width * 0.8, size.height * 0.3);
    path.quadraticBezierTo(size.width * 0.9, size.height * 0.6, size.width * 0.75, size.height * 0.8);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
