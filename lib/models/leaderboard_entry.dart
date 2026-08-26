class LeaderboardEntry {
  final String playerName;
  final int level;
  final int streak;
  final DateTime date;

  LeaderboardEntry({
    required this.playerName,
    required this.level,
    required this.streak,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'playerName': playerName,
        'level': level,
        'streak': streak,
        'date': date.toIso8601String(),
      };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      playerName: json['playerName'] as String? ?? 'Mindful Player',
      level: json['level'] as int? ?? 1,
      streak: json['streak'] as int? ?? 0,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
