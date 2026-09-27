import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/game_theme.dart';
import '../../models/leaderboard_entry.dart';

class LeaderboardModal extends StatelessWidget {
  final GameTheme theme;
  final List<LeaderboardEntry> leaderboard;
  final String activePlayerName;
  final VoidCallback onEditGamerTag;

  const LeaderboardModal({
    super.key,
    required this.theme,
    required this.leaderboard,
    required this.activePlayerName,
    required this.onEditGamerTag,
  });

  static void show(
    BuildContext context, {
    required GameTheme theme,
    required List<LeaderboardEntry> leaderboard,
    required String activePlayerName,
    required VoidCallback onEditGamerTag,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => LeaderboardModal(
        theme: theme,
        leaderboard: leaderboard,
        activePlayerName: activePlayerName,
        onEditGamerTag: onEditGamerTag,
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
        padding: const EdgeInsets.all(20),
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
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.emoji_events_outlined,
                        color: theme.accentColor, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'HALL OF FAME',
                      style: GoogleFonts.orbitron(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: theme.textPrimary,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onEditGamerTag();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.accentColor.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded,
                            size: 14, color: theme.accentColor),
                        const SizedBox(width: 4),
                        Text(
                          activePlayerName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (leaderboard.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'No high scores recorded yet.\nComplete sessions to claim your spot!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.textPrimary.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: leaderboard.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = leaderboard[index];
                    final rank = index + 1;
                    final isUser = entry.playerName.trim().toLowerCase() ==
                        activePlayerName.trim().toLowerCase();

                    Color rankColor;
                    String rankBadge;
                    if (rank == 1) {
                      rankColor = const Color(0xFFFFD700);
                      rankBadge = '🥇';
                    } else if (rank == 2) {
                      rankColor = const Color(0xFFC0C0C0);
                      rankBadge = '🥈';
                    } else if (rank == 3) {
                      rankColor = const Color(0xFFCD7F32);
                      rankBadge = '🥉';
                    } else {
                      rankColor = theme.textPrimary.withValues(alpha: 0.5);
                      rankBadge = '#$rank';
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isUser
                            ? theme.accentColor.withValues(alpha: 0.18)
                            : theme.tileDefault.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isUser
                              ? theme.accentColor
                              : theme.panelBorder.withValues(alpha: 0.3),
                          width: isUser ? 2.0 : 1.0,
                        ),
                        boxShadow: isUser
                            ? [
                                BoxShadow(
                                  color: theme.accentColor
                                      .withValues(alpha: 0.35),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              rankBadge,
                              style: TextStyle(
                                fontSize: rank <= 3 ? 16 : 11,
                                fontWeight: FontWeight.bold,
                                color: rankColor,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      entry.playerName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: isUser
                                            ? theme.accentColor
                                            : theme.textPrimary,
                                      ),
                                    ),
                                    if (isUser) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFD700),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'YOU',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Level ${entry.level}  •  Streak ${entry.streak}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.textPrimary
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${entry.date.month}/${entry.date.day}',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.textPrimary.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'CLOSE',
                style: TextStyle(
                  color: theme.accentColor,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
