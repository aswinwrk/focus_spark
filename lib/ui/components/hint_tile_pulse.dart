import 'package:flutter/material.dart';

class HintTilePulse extends StatefulWidget {
  final Widget child;
  final bool isHinted;
  final Color pulseColor;

  const HintTilePulse({
    super.key,
    required this.child,
    required this.isHinted,
    required this.pulseColor,
  });

  @override
  State<HintTilePulse> createState() => _HintTilePulseState();
}

class _HintTilePulseState extends State<HintTilePulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _glowAnim = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    if (widget.isHinted) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant HintTilePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHinted && !oldWidget.isHinted) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isHinted && oldWidget.isHinted) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isHinted && _ctrl.isDismissed) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isHinted ? _scaleAnim.value : 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.isHinted
                  ? [
                      BoxShadow(
                        color: widget.pulseColor.withValues(alpha: 0.85 * _glowAnim.value),
                        blurRadius: 26 * _glowAnim.value,
                        spreadRadius: 4 * _glowAnim.value,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
