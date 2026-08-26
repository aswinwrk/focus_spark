import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';
import '../components/animated_gradient_bg.dart';

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
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2400),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_pulseController);

    _fadeController.forward();
    Timer(const Duration(milliseconds: 2200), () {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedGradientBackground(
      colors: widget.theme.bgGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          widget.theme.accentColor.withValues(alpha: 0.25),
                          widget.theme.accentColor.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(32),
                                color: widget.theme.panelBg.withValues(alpha: 0.6),
                                border: Border.all(
                                  color: widget.theme.accentColor.withValues(alpha: 0.8),
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.theme.accentColor.withValues(alpha: 0.5),
                                    blurRadius: 36,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Transform.rotate(
                                    angle: _rotationAnimation.value * 6.28,
                                    child: Container(
                                      width: 98,
                                      height: 98,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: widget.theme.tileActiveGlow.withValues(alpha: 0.45),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.auto_awesome_mosaic_rounded,
                                    size: 52,
                                    color: widget.theme.accentColor,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'MINDFUL MATRIX',
                        style: GoogleFonts.orbitron(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 5.0,
                          color: widget.theme.textPrimary,
                          shadows: [
                            Shadow(
                              color: widget.theme.accentColor.withValues(alpha: 0.7),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'INTERACTIVE STUDIOS',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 4.0,
                          color: widget.theme.accentColor.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 60),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.theme.tileDefault.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.theme.panelBorder.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'P R E S E N T S',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4.5,
                            color: widget.theme.textPrimary.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
