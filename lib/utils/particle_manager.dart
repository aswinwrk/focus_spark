import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/particle.dart';

class ParticleManager extends ChangeNotifier {
  final List<SparkParticle> particles = [];
  late Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  ParticleManager(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  void spawnSparks(double cx, double cy, Color color, int count) {
    final rng = math.Random();
    for (int i = 0; i < count; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 75.0 + rng.nextDouble() * 145.0;
      particles.add(SparkParticle(
        x: cx,
        y: cy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 35.0,
        size: 2.0 + rng.nextDouble() * 4.5,
        color: color,
        maxLifetime: 0.38 + rng.nextDouble() * 0.52,
      ));
    }
    notifyListeners();
  }

  void spawnConfettiBurst(double cx, double cy, int count) {
    final rng = math.Random();
    final List<Color> confettiColors = const [
      Color(0xFFEC4899), // Neon Pink
      Color(0xFF06B6D4), // Cyan
      Color(0xFFF59E0B), // Gold
      Color(0xFF8B5CF6), // Purple
      Color(0xFF10B981), // Emerald
      Color(0xFFF97316), // Orange
      Color(0xFFEF4444), // Crimson
    ];

    for (int i = 0; i < count; i++) {
      final angle = rng.nextDouble() * 2 * math.pi;
      final speed = 130.0 + rng.nextDouble() * 250.0;
      final color = confettiColors[rng.nextInt(confettiColors.length)];

      particles.add(SparkParticle(
        x: cx,
        y: cy,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 160.0,
        size: 4.5 + rng.nextDouble() * 4.5,
        color: color,
        maxLifetime: 1.1 + rng.nextDouble() * 0.8,
        isConfetti: true,
        rotation: rng.nextDouble() * 2 * math.pi,
        rotationSpeed: (rng.nextDouble() - 0.5) * 12.0,
        width: 9.0 + rng.nextDouble() * 9.0,
      ));
    }
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    if (particles.isEmpty) {
      _lastElapsed = elapsed;
      return;
    }
    double dt =
        (elapsed.inMicroseconds - _lastElapsed.inMicroseconds) / 1_000_000.0;
    _lastElapsed = elapsed;
    if (dt <= 0 || dt > 0.1) dt = 0.016;

    for (int i = particles.length - 1; i >= 0; i--) {
      particles[i].update(dt);
      if (particles[i].isDead) particles.removeAt(i);
    }
    notifyListeners();
  }

  void clear() {
    particles.clear();
    notifyListeners();
  }

  void disposeTicker() => _ticker.dispose();
}

class ParticlePainter extends CustomPainter {
  final List<SparkParticle> particles;
  ParticlePainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      paint.color = p.color.withValues(alpha: p.alpha);
      if (p.isConfetti) {
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.rotation);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.width,
            height: p.size,
          ),
          paint,
        );
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}
