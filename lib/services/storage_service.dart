import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String keyHighScore = 'brain_reboot_high_score';
  static const String keyZenMode = 'brain_reboot_zen_mode';
  static const String keyMusicMuted = 'brain_reboot_is_music_muted';
  static const String keySfxMuted = 'brain_reboot_is_sfx_muted';
  static const String keyHapticsMuted = 'brain_reboot_is_haptics_muted';
  static const String keyPlayerName = 'brain_reboot_player_name';
  static const String keyThemeIndex = 'brain_reboot_theme_index';
  static const String keySeenTutorial = 'brain_reboot_has_seen_tutorial';
  static const String keyHallOfFame = 'brain_reboot_hall_of_fame';
  static const String keyHasActiveGame = 'brain_reboot_has_active_game';
  static const String keyCurrentLevel = 'brain_reboot_current_level';
  static const String keyCurrentStreak = 'brain_reboot_current_streak';
  static const String keyCurrentSequence = 'brain_reboot_current_sequence';

  // Legacy Fallback Keys
  static const String legacyHighScore = 'focus_spark_high_score';
  static const String legacyPlayerName = 'focus_spark_player_name';
  static const String legacyHallOfFame = 'focus_spark_hall_of_fame';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  int getHighScore() {
    return _prefs.getInt(keyHighScore) ?? _prefs.getInt(legacyHighScore) ?? 0;
  }

  Future<bool> setHighScore(int score) {
    return _prefs.setInt(keyHighScore, score);
  }

  bool getZenMode() {
    return _prefs.getBool(keyZenMode) ?? false;
  }

  Future<bool> setZenMode(bool value) {
    return _prefs.setBool(keyZenMode, value);
  }

  bool isMusicMuted() {
    return _prefs.getBool(keyMusicMuted) ?? false;
  }

  Future<bool> setMusicMuted(bool value) {
    return _prefs.setBool(keyMusicMuted, value);
  }

  bool isSfxMuted() {
    return _prefs.getBool(keySfxMuted) ?? false;
  }

  Future<bool> setSfxMuted(bool value) {
    return _prefs.setBool(keySfxMuted, value);
  }

  bool isHapticsMuted() {
    return _prefs.getBool(keyHapticsMuted) ?? false;
  }

  Future<bool> setHapticsMuted(bool value) {
    return _prefs.setBool(keyHapticsMuted, value);
  }

  String getPlayerName() {
    return _prefs.getString(keyPlayerName) ??
        _prefs.getString(legacyPlayerName) ??
        'You';
  }

  Future<bool> setPlayerName(String name) {
    return _prefs.setString(keyPlayerName, name);
  }

  int getThemeIndex() {
    return _prefs.getInt(keyThemeIndex) ?? 0;
  }

  Future<bool> setThemeIndex(int index) {
    return _prefs.setInt(keyThemeIndex, index);
  }

  bool hasSeenTutorial() {
    return _prefs.getBool(keySeenTutorial) ?? false;
  }

  Future<bool> setSeenTutorial(bool value) {
    return _prefs.setBool(keySeenTutorial, value);
  }

  String getHallOfFameJson() {
    return _prefs.getString(keyHallOfFame) ??
        _prefs.getString(legacyHallOfFame) ??
        '';
  }

  Future<bool> setHallOfFameJson(String jsonStr) {
    return _prefs.setString(keyHallOfFame, jsonStr);
  }

  bool hasActiveGame() {
    return _prefs.getBool(keyHasActiveGame) ?? false;
  }

  int getCurrentLevel() {
    return _prefs.getInt(keyCurrentLevel) ?? 1;
  }

  int getCurrentStreak() {
    return _prefs.getInt(keyCurrentStreak) ?? 0;
  }

  String getCurrentSequenceStr() {
    return _prefs.getString(keyCurrentSequence) ?? '';
  }

  Future<void> saveActiveGame({
    required int level,
    required int streak,
    required List<int> sequence,
  }) async {
    await _prefs.setBool(keyHasActiveGame, true);
    await _prefs.setInt(keyCurrentLevel, level);
    await _prefs.setInt(keyCurrentStreak, streak);
    await _prefs.setString(keyCurrentSequence, sequence.join(','));
  }

  Future<void> clearActiveGame() async {
    await _prefs.setBool(keyHasActiveGame, false);
    await _prefs.remove(keyCurrentSequence);
  }
}
