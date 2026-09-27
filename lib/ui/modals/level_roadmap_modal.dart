import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';

class LevelRoadmapModal extends StatefulWidget {
  final GameTheme theme;
  final int currentLevel;
  final int highScoreLevel;

  const LevelRoadmapModal({
    super.key,
    required this.theme,
    required this.currentLevel,
    required this.highScoreLevel,
  });

  static Future<void> show(
    BuildContext context, {
    required GameTheme theme,
    required int currentLevel,
    required int highScoreLevel,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => LevelRoadmapModal(
        theme: theme,
        currentLevel: currentLevel,
        highScoreLevel: highScoreLevel,
      ),
    );
  }

  @override
  State<LevelRoadmapModal> createState() => _LevelRoadmapModalState();
}

class _LevelRoadmapModalState extends State<LevelRoadmapModal> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Auto-scroll to center current level after frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final targetOffset = (widget.currentLevel - 1) * 70.0;
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final effectiveBest = math.max(widget.currentLevel, widget.highScoreLevel);
    final maxTargetLevel = math.max(effectiveBest + 8, 25);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: theme.panelBorder, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.map_rounded,
                              color: theme.accentColor, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'LEVEL ROADMAP',
                            style: GoogleFonts.orbitron(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              color: theme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded,
                            color: theme.textPrimary.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Subheader Telemetry
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.accentColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          'CURRENT: LVL ${widget.currentLevel}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.accentColor,
                          ),
                        ),
                        Text('•', style: TextStyle(color: theme.textPrimary.withValues(alpha: 0.3))),
                        Text(
                          'BEST: LVL $effectiveBest',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: theme.textPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Colors.white12),
                  const SizedBox(height: 14),

                  // Winding S-Curve Level Path
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: maxTargetLevel,
                      itemBuilder: (context, index) {
                        final lvl = index + 1;
                        final isCurrent = lvl == widget.currentLevel;
                        final isBestPeak = lvl == widget.highScoreLevel && widget.highScoreLevel > 0;
                        final isPassed = (lvl < widget.currentLevel) ||
                            (lvl <= widget.highScoreLevel && !isCurrent && !isBestPeak);

                        // Winding S-curve normalized alignment ratio (-0.50 to +0.50)
                        final double alignX = math.sin(lvl * 0.65) * 0.50;
                        final double nextAlignX = math.sin((lvl + 1) * 0.65) * 0.50;

                        // Milestone titles at level 5, 10, 15, 20, 25, 30
                        String? milestoneTitle;
                        if (lvl == 5) milestoneTitle = '🌟 Spark Initiate';
                        if (lvl == 10) milestoneTitle = '⚡ Focus Adept';
                        if (lvl == 15) milestoneTitle = '🧘 Mindful Master';
                        if (lvl == 20) milestoneTitle = '🔮 Zen Transcendent';
                        if (lvl == 25) milestoneTitle = '🌌 Cosmic Sage';
                        if (lvl == 30) milestoneTitle = '👑 Memory Legend';

                        Widget nodeWidget = AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: isCurrent ? 50 : 42,
                          height: isCurrent ? 50 : 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCurrent
                                ? theme.accentColor
                                : isPassed || isBestPeak
                                    ? theme.accentColor.withValues(alpha: 0.25)
                                    : theme.tileDefault.withValues(alpha: 0.35),
                            border: Border.all(
                              color: isCurrent
                                  ? Colors.white
                                  : isPassed || isBestPeak
                                      ? theme.accentColor.withValues(alpha: 0.75)
                                      : theme.panelBorder.withValues(alpha: 0.4),
                              width: isCurrent ? 2.5 : 1.5,
                            ),
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: theme.accentColor.withValues(alpha: 0.65),
                                      blurRadius: 18,
                                      spreadRadius: 3,
                                    ),
                                  ]
                                : isPassed || isBestPeak
                                    ? [
                                        BoxShadow(
                                          color: theme.accentColor.withValues(alpha: 0.25),
                                          blurRadius: 8,
                                        ),
                                      ]
                                    : null,
                          ),
                          child: Center(
                            child: isCurrent
                                ? const Icon(
                                    Icons.local_fire_department_rounded,
                                    color: Colors.black87,
                                    size: 24,
                                  )
                                : isPassed || isBestPeak
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: theme.accentColor,
                                        size: 18,
                                      )
                                    : Text(
                                        '$lvl',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: theme.textPrimary
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                          ),
                        );

                        if (isBestPeak && !isCurrent) {
                          nodeWidget = _PulsingBestPeakNode(child: nodeWidget);
                        }

                        return Column(
                          children: [
                            if (milestoneTitle != null) ...[
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isPassed || isCurrent || isBestPeak
                                      ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                                      : theme.tileDefault.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isPassed || isCurrent || isBestPeak
                                        ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                                        : theme.panelBorder.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Text(
                                  milestoneTitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    color: isPassed || isCurrent || isBestPeak
                                        ? const Color(0xFFFFD700)
                                        : theme.textPrimary.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ],

                            // Node container aligned on the S-curve
                            Align(
                              alignment: Alignment(alignX, 0),
                              child: nodeWidget,
                            ),

                            // Curved connecting line to next node
                            if (lvl < maxTargetLevel)
                              SizedBox(
                                height: 35,
                                child: CustomPaint(
                                  size: const Size(double.infinity, 35),
                                  painter: _RoadmapSegmentPainter(
                                    startAlignX: alignX,
                                    endAlignX: nextAlignX,
                                    lineColor: (lvl < widget.currentLevel || lvl < widget.highScoreLevel)
                                        ? theme.accentColor.withValues(alpha: 0.65)
                                        : theme.panelBorder.withValues(alpha: 0.25),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Curved Connecting Line Painter for Level Roadmap
// ---------------------------------------------------------------------------
class _RoadmapSegmentPainter extends CustomPainter {
  final double startAlignX;
  final double endAlignX;
  final Color lineColor;

  _RoadmapSegmentPainter({
    required this.startAlignX,
    required this.endAlignX,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final startX = (size.width / 2) + (startAlignX * (size.width / 2));
    final endX = (size.width / 2) + (endAlignX * (size.width / 2));

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(startX, 0);
    path.cubicTo(startX, 17, endX, 18, endX, 35);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RoadmapSegmentPainter oldDelegate) {
    return oldDelegate.startAlignX != startAlignX ||
        oldDelegate.endAlignX != endAlignX ||
        oldDelegate.lineColor != lineColor;
  }
}

// ---------------------------------------------------------------------------
// Smooth breathing scale node widget for Personal Best Peak level
// ---------------------------------------------------------------------------
class _PulsingBestPeakNode extends StatefulWidget {
  final Widget child;
  const _PulsingBestPeakNode({required this.child});

  @override
  State<_PulsingBestPeakNode> createState() => _PulsingBestPeakNodeState();
}

class _PulsingBestPeakNodeState extends State<_PulsingBestPeakNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
