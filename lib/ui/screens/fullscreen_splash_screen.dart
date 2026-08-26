import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';
import '../components/animated_gradient_bg.dart';

class FullScreenSplashScreen extends StatefulWidget {
  final GameTheme theme;
  final VoidCallback onLoadingComplete;

  const FullScreenSplashScreen({
    super.key,
    required this.theme,
    required this.onLoadingComplete,
  });

  @override
  State<FullScreenSplashScreen> createState() => _FullScreenSplashScreenState();
}

class _FullScreenSplashScreenState extends State<FullScreenSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOutCubic),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.90, end: 1.10).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_pulseController);

    _progressController.forward();
    _progressController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onLoadingComplete();
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedGradientBackground(
      colors: widget.theme.bgGradient,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.theme.accentColor.withValues(alpha: 0.22),
                        widget.theme.accentColor.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: widget.theme.accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: widget.theme.accentColor.withValues(alpha: 0.4),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.theme.accentColor.withValues(alpha: 0.15),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: Text(
                          '✦ MINDFUL MATRIX STUDIOS ✦',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 3.5,
                            color: widget.theme.accentColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.theme.panelBg.withValues(alpha: 0.6),
                                border: Border.all(
                                  color: widget.theme.accentColor.withValues(alpha: 0.7),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.theme.accentColor.withValues(alpha: 0.5),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Transform.rotate(
                                    angle: _rotationAnimation.value * 6.28,
                                    child: Container(
                                      width: 92,
                                      height: 92,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: widget.theme.tileActiveGlow.withValues(alpha: 0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 48,
                                    color: widget.theme.accentColor,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            Colors.white,
                            widget.theme.accentColor,
                            widget.theme.tileActiveGlow,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: Text(
                          'FOCUS SPARK',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.orbitron(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6.0,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: widget.theme.accentColor.withValues(alpha: 0.8),
                                blurRadius: 28,
                              ),
                              Shadow(
                                color: widget.theme.accentColor.withValues(alpha: 0.4),
                                blurRadius: 52,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: widget.theme.tileDefault.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: widget.theme.panelBorder.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          'ELEVATE YOUR MEMORY & FOCUS',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.8,
                            color: widget.theme.textPrimary.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      AnimatedBuilder(
                        animation: _progressAnimation,
                        builder: (context, child) {
                          final progress = _progressAnimation.value;
                          final percent = (progress * 100).toInt();

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 240,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: widget.theme.tileDefault.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: widget.theme.panelBorder.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: progress,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              widget.theme.accentColor,
                                              widget.theme.tileActiveGlow,
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: widget.theme.accentColor.withValues(alpha: 0.85),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: widget.theme.panelBg.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: widget.theme.panelBorder.withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  'INITIALIZING MATRIX... $percent%',
                                  style: GoogleFonts.orbitron(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2.2,
                                    color: widget.theme.accentColor,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
