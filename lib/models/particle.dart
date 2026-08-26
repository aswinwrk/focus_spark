import 'package:flutter/material.dart';

class SparkParticle {
  double x, y, vx, vy, size, alpha, lifetime;
  final Color color;
  final double maxLifetime;
  final bool isConfetti;
  double rotation;
  double rotationSpeed;
  double width;

  SparkParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.maxLifetime,
    this.isConfetti = false,
    this.rotation = 0.0,
    this.rotationSpeed = 0.0,
    this.width = 0.0,
  })  : alpha = 1.0,
        lifetime = 0.0;

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    if (isConfetti) {
      vy += 120.0 * dt;
      vx *= 0.98;
      rotation += rotationSpeed * dt;
    } else {
      vy += 90.0 * dt;
    }
    lifetime += dt;
    alpha = (1.0 - (lifetime / maxLifetime)).clamp(0.0, 1.0);
  }

  bool get isDead => lifetime >= maxLifetime;
}
