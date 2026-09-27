import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';

class TutorialModal extends StatelessWidget {
  final GameTheme theme;

  const TutorialModal({
    super.key,
    required this.theme,
  });

  static void show(
    BuildContext context, {
    required GameTheme theme,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => TutorialModal(
        theme: theme,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: theme.panelBg.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.accentColor.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.accentColor.withValues(alpha: 0.25),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.help_outline_rounded,
                        color: theme.accentColor, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'HOW TO PLAY',
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
            const SizedBox(height: 16),
            _buildInstructionItem(
              '1',
              'Observe the Flashing Pattern',
              'Watch the matrix tiles light up and listen to their pentatonic sound sequence carefully.',
              theme,
            ),
            _buildInstructionItem(
              '2',
              'Repeat the Exact Sequence',
              'Tap the tiles in the exact order shown before the timer bar runs out.',
              theme,
            ),
            _buildInstructionItem(
              '3',
              'Milestone Reverse Rounds 🔄',
              'From Level 5 onwards, surprise Reverse Rounds flip the rule: tap the pattern in reverse order!',
              theme,
            ),
            _buildInstructionItem(
              '4',
              'Earn 3 Stars & Level Up',
              'Complete levels quickly for 3 Stars ⭐⭐⭐ and track your best peak run on the Leaderboard.',
              theme,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'GOT IT!',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionItem(
      String step, String title, String description, GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.accentColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(
                  color: theme.accentColor.withValues(alpha: 0.5), width: 1),
            ),
            child: Center(
              child: Text(
                step,
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: theme.textPrimary.withValues(alpha: 0.65),
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
