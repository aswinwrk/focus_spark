import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';

class CompanySplashScreen extends StatefulWidget {
  final GameTheme theme;
  final VoidCallback onComplete;

  const CompanySplashScreen({
    super.key,
    required this.theme,
    required this.onComplete,
  });

  @override
  State<CompanySplashScreen> createState() => _CompanySplashScreenState();
}

class _CompanySplashScreenState extends State<CompanySplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _particleController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2600),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _particleController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _fadeController.forward();
    Timer(const Duration(milliseconds: 2800), () {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030713),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Full-Screen ASTA Logo Artwork Background
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Image.asset(
                      'assets/images/asta_logo.png',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/company_logo.png',
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            // Ambient Neon Cyber Particle Grid Overlay
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _particleController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _AstaSplashBackgroundPainter(
                      progress: _particleController.value,
                    ),
                  );
                },
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// Background painter for subtle glowing pixel particles & grid lines
class _AstaSplashBackgroundPainter extends CustomPainter {
  final double progress;
  _AstaSplashBackgroundPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final cyanPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final bluePaint = Paint()
      ..color = const Color(0xFF2979FF).withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 35; i++) {
      final x = rand.nextDouble() * size.width;
      final startY = rand.nextDouble() * size.height;
      final speed = 15.0 + rand.nextDouble() * 35.0;
      final y = (startY - progress * speed) % size.height;
      final radius = 1.0 + rand.nextDouble() * 2.2;

      final paint = (i % 2 == 0) ? cyanPaint : bluePaint;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AstaSplashBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

