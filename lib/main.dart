import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'services/audio_service.dart';
import 'services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Immersive Mobile Experience: Portrait orientation lock & Fullscreen sticky mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
  await AdService.instance.initialize();

  runApp(const FocusSparkApp());
}

class FocusSparkApp extends StatelessWidget {
  const FocusSparkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Spark',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const FocusSparkScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Game State Enum
// ---------------------------------------------------------------------------
enum GameState {
  startScreen,
  playback,
  playerInput,
  paused,
  successTransition,
  errorTransition,
}

// ---------------------------------------------------------------------------
// Theme Model
// ---------------------------------------------------------------------------
class GameTheme {
  final String name;
  final List<Color> bgGradient;
  final Color panelBg;
  final Color panelBorder;
  final Color tileActiveGlow;
  final Color tileDefault;
  final Color textPrimary;
  final Color accentColor;
  final Color successColor;

  const GameTheme({
    required this.name,
    required this.bgGradient,
    required this.panelBg,
    required this.panelBorder,
    required this.tileActiveGlow,
    required this.tileDefault,
    required this.textPrimary,
    required this.accentColor,
    required this.successColor,
  });
}

// ---------------------------------------------------------------------------
// Main Screen
// ---------------------------------------------------------------------------
class FocusSparkScreen extends StatefulWidget {
  const FocusSparkScreen({super.key});

  @override
  State<FocusSparkScreen> createState() => _FocusSparkScreenState();
}

class _FocusSparkScreenState extends State<FocusSparkScreen>
    with SingleTickerProviderStateMixin {
  // ── Theme Presets ───────────────────────────────────────────────────────
  final List<GameTheme> _themes = const [
    GameTheme(
      name: 'Cosmic Indigo',
      bgGradient: [Color(0xFF0C0A1A), Color(0xFF181135), Color(0xFF06050D)],
      panelBg: Color(0x1F221B35),
      panelBorder: Color(0x388B5CF6),
      tileActiveGlow: Color(0xFFC084FC),
      tileDefault: Color(0x14FFFFFF),
      textPrimary: Colors.white,
      accentColor: Color(0xFFA78BFA),
      successColor: Color(0xFF10B981),
    ),
    GameTheme(
      name: 'Sage Calm',
      bgGradient: [Color(0xFF161E1A), Color(0xFF243329), Color(0xFF0F1411)],
      panelBg: Color(0x1F2A382F),
      panelBorder: Color(0x3B86EFAC),
      tileActiveGlow: Color(0xFF4ADE80),
      tileDefault: Color(0x10FFFFFF),
      textPrimary: Color(0xFFF1FDF7),
      accentColor: Color(0xFF86EFAC),
      successColor: Color(0xFF34D399),
    ),
    GameTheme(
      name: 'Midnight Cyber',
      bgGradient: [Color(0xFF030006), Color(0xFF070B18), Color(0xFF010003)],
      panelBg: Color(0x240A1021),
      panelBorder: Color(0x4706B6D4),
      tileActiveGlow: Color(0xFF22D3EE),
      tileDefault: Color(0x16FFFFFF),
      textPrimary: Color(0xFFF8FAFC),
      accentColor: Color(0xFF06B6D4),
      successColor: Color(0xFF06B6D4),
    ),
  ];

  int _selectedThemeIndex = 0;

  // ── Pentatonic frequencies (C4–D5) ──────────────────────────────────────
  static const List<double> _frequencies = [
    261.63, // C4
    293.66, // D4
    329.63, // E4
    349.23, // F4
    392.00, // G4
    440.00, // A4
    493.88, // B4
    523.25, // C5
    587.33, // D5
  ];

  // ── Game State ──────────────────────────────────────────────────────────
  GameState _gameState = GameState.startScreen;
  final List<int> _sequence = [];
  final List<int> _playerInput = [];
  int _level = 1;
  int _currentStreak = 0;
  int _highScore = 0;

  // Session summary (shown briefly on reset)
  bool _showSessionSummary = false;
  int _sessionMaxLevel = 1;
  int _sessionMaxStreak = 0;

  // Track the current playback session ID to cancel outdated async loops
  int _playbackSessionId = 0;

  // Level & Session Persistence
  bool _hasSavedSession = false;

  // Hall of Fame Leaderboard State
  List<LeaderboardEntry> _leaderboard = [];

  // Hint & Ad System State
  int _freeHintsRemainingInLevel = 1;
  bool _isAdActive = false;
  int? _hintedTile;

  // Tutorial display preferences
  bool _hasSeenTutorial = false;
  bool _showTutorialCard = true;

  bool _isZenMode = false;
  bool _isMusicMuted = false;
  bool _isSfxMuted = false;

  // ── Tile Interaction State ───────────────────────────────────────────────
  int? _activePlaybackTile;
  int? _correctErrorTile;
  int? _activeTapTile;
  final List<bool> _hoverStates = List.filled(9, false);
  List<double> _tileEntryScales = List.filled(9, 1.0);

  // ── Grid sizing (tracked via LayoutBuilder) ──────────────────────────────
  double _gridWidth = 300.0;
  double _gridHeight = 300.0;

  // ── Input Timer ──────────────────────────────────────────────────────────
  Timer? _inputTimer;
  double _inputTimerPercentage = 1.0;
  double _totalInputTime = 8.0;
  double _elapsedInputTime = 0.0;

  // ── Particle & Ad Engine ──────────────────────────────────────────────────
  late ParticleManager _particleManager;
  int _splashStage = 0;
  late SharedPreferences _prefs;
  final math.Random _random = math.Random();
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  String _activeAdType = 'REWARDED VIDEO TEST AD';

  @override
  void initState() {
    super.initState();
    _particleManager = ParticleManager(this);
    _loadSettings();
    _initAdMobBanner();

    AdService.instance.onAdOpened = () {
      if (!mounted) return;
      AudioService.instance.stopAmbientMusic();
      _cancelInputTimer();
      if (_gameState == GameState.playerInput) {
        setState(() {
          _gameState = GameState.paused;
        });
      }
    };

    AdService.instance.onAdClosed = () {
      if (!mounted) return;
      if (!_isMusicMuted) {
        AudioService.instance.startAmbientMusic();
      }
    };
  }

  void _initAdMobBanner() async {
    _bannerAd = await AdService.instance.createBannerAd(
      onAdLoaded: (ad) {
        if (mounted) setState(() => _isBannerAdLoaded = true);
      },
      onAdFailedToLoad: (ad, error) {
        ad.dispose();
        if (mounted) {
          setState(() => _isBannerAdLoaded = false);
          // Retry loading banner ad after 4 seconds
          Timer(const Duration(seconds: 4), () {
            if (mounted && !_isBannerAdLoaded) {
              _initAdMobBanner();
            }
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _particleManager.disposeTicker();
    _particleManager.dispose();
    _cancelInputTimer();
    super.dispose();
  }

  // ── Persistence ─────────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    final bool hasSavedGame = _prefs.getBool('focus_spark_has_active_game') ?? false;
    final int savedLevel = _prefs.getInt('focus_spark_current_level') ?? 1;
    final int savedStreak = _prefs.getInt('focus_spark_current_streak') ?? 0;
    final String seqStr = _prefs.getString('focus_spark_current_sequence') ?? '';

    List<int> loadedSequence = [];
    if (hasSavedGame && seqStr.isNotEmpty) {
      try {
        loadedSequence = seqStr
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .map((e) => int.parse(e.trim()))
            .toList();
      } catch (_) {
        loadedSequence = [];
      }
    }

    setState(() {
      _highScore = _prefs.getInt('focus_spark_high_score') ?? 0;
      _isZenMode = _prefs.getBool('focus_spark_zen_mode') ?? false;
      _isMusicMuted = _prefs.getBool('focus_spark_is_music_muted') ?? false;
      _isSfxMuted = _prefs.getBool('focus_spark_is_sfx_muted') ?? false;
      _selectedThemeIndex = _prefs.getInt('focus_spark_theme_index') ?? 0;
      _hasSeenTutorial = _prefs.getBool('focus_spark_has_seen_tutorial') ?? false;
      _showTutorialCard = !_hasSeenTutorial;

      if (hasSavedGame && loadedSequence.isNotEmpty) {
        _hasSavedSession = true;
        _level = savedLevel > 0 ? savedLevel : 1;
        _currentStreak = savedStreak;
        _sequence.clear();
        _sequence.addAll(loadedSequence);
      } else {
        _hasSavedSession = false;
        _level = 1;
        _currentStreak = 0;
        _sequence.clear();
      }

      final clearedLevel = _level > 1 ? _level - 1 : 0;
      // Self-heal mobile SharedPreferences cache if high score was previously saved as upcoming _level
      if (_highScore > clearedLevel && _highScore == _level && hasSavedGame) {
        _highScore = clearedLevel;
        _prefs.setInt('focus_spark_high_score', _highScore);
      } else if (clearedLevel > _highScore) {
        _highScore = clearedLevel;
        _prefs.setInt('focus_spark_high_score', _highScore);
      }

      if (!_isMusicMuted) {
        AudioService.instance.startAmbientMusic();
      } else {
        AudioService.instance.stopAmbientMusic();
      }

      // Load Hall of Fame Leaderboard
      final String leaderboardStr = _prefs.getString('focus_spark_hall_of_fame') ?? '';
      List<LeaderboardEntry> loadedLeaderboard = [];
      if (leaderboardStr.isNotEmpty) {
        try {
          final List<dynamic> jsonList = jsonDecode(leaderboardStr) as List<dynamic>;
          loadedLeaderboard = jsonList
              .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (_) {
          loadedLeaderboard = [];
        }
      }

      if (loadedLeaderboard.isEmpty) {
        // Initial seed entries
        final now = DateTime.now();
        loadedLeaderboard = [
          LeaderboardEntry(playerName: 'Zen Master', level: 12, streak: 12, date: now.subtract(const Duration(days: 1))),
          LeaderboardEntry(playerName: 'Mindful Seeker', level: 9, streak: 9, date: now.subtract(const Duration(days: 3))),
          LeaderboardEntry(playerName: 'Focus Sparker', level: 7, streak: 7, date: now.subtract(const Duration(days: 5))),
          LeaderboardEntry(playerName: 'Memory Runner', level: 5, streak: 5, date: now.subtract(const Duration(days: 7))),
          LeaderboardEntry(playerName: 'Calm Thinker', level: 3, streak: 3, date: now.subtract(const Duration(days: 9))),
        ];
      }
      _leaderboard = loadedLeaderboard;
    });
  }

  Future<void> _saveGameProgress() async {
    if (!mounted) return;
    await _prefs.setBool('focus_spark_has_active_game', true);
    await _prefs.setInt('focus_spark_current_level', _level);
    await _prefs.setInt('focus_spark_current_streak', _currentStreak);
    await _prefs.setString('focus_spark_current_sequence', _sequence.join(','));
    if (!_hasSavedSession) {
      setState(() {
        _hasSavedSession = true;
      });
    }
  }

  Future<void> _updateHighScore(int score) async {
    setState(() => _highScore = score);
    await _prefs.setInt('focus_spark_high_score', score);
  }

  Future<void> _recordLeaderboardScore(int level, int streak) async {
    if (level <= 1 && streak <= 0) return;

    final entry = LeaderboardEntry(
      playerName: 'You',
      level: level,
      streak: streak,
      date: DateTime.now(),
    );

    _leaderboard.add(entry);
    _leaderboard.sort((a, b) {
      int cmp = b.level.compareTo(a.level);
      if (cmp == 0) return b.streak.compareTo(a.streak);
      return cmp;
    });

    if (_leaderboard.length > 10) {
      _leaderboard = _leaderboard.sublist(0, 10);
    }

    final String jsonStr = jsonEncode(_leaderboard.map((e) => e.toJson()).toList());
    await _prefs.setString('focus_spark_hall_of_fame', jsonStr);
    if (mounted) setState(() {});
  }

  Future<void> _toggleZenMode() async {
    setState(() => _isZenMode = !_isZenMode);
    await _prefs.setBool('focus_spark_zen_mode', _isZenMode);
  }

  Future<void> _toggleMusic() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isMusicMuted = !_isMusicMuted;
    });
    await _prefs.setBool('focus_spark_is_music_muted', _isMusicMuted);
    if (_isMusicMuted) {
      AudioService.instance.stopAmbientMusic();
    } else {
      AudioService.instance.startAmbientMusic();
    }
  }

  void _toggleSfx() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isSfxMuted = !_isSfxMuted;
    });
    await _prefs.setBool('focus_spark_is_sfx_muted', _isSfxMuted);
  }

  Future<void> _selectTheme(int index) async {
    setState(() => _selectedThemeIndex = index);
    await _prefs.setInt('focus_spark_theme_index', index);
  }

  // ── Particle helpers ─────────────────────────────────────────────────────
  void _spawnTileSparks(int index, Color color) {
    final col = (index % 3).toDouble();
    final row = (index ~/ 3).toDouble();
    final tileW = _gridWidth / 3;
    final tileH = _gridHeight / 3;
    _particleManager.spawnSparks(
      tileW * col + tileW / 2,
      tileH * row + tileH / 2,
      color,
      14,
    );
  }

  void _spawnSuccessSparks(Color color) {
    _particleManager.spawnSparks(_gridWidth / 2, _gridHeight / 2, color, 60);
  }

  // ── Session Control ──────────────────────────────────────────────────────
  void _startSession() async {
    void launchGame() {
      if (!mounted) return;
      _cancelInputTimer();
      _particleManager.clear();
      _playbackSessionId++;
      final currentSession = _playbackSessionId;
      HapticFeedback.mediumImpact();

      setState(() {
        if (!_hasSeenTutorial) {
          _hasSeenTutorial = true;
          _showTutorialCard = false;
          _prefs.setBool('focus_spark_has_seen_tutorial', true);
        }
        _gameState = GameState.playback;
        _sequence.clear();
        _playerInput.clear();
        _level = 1;
        _currentStreak = 0;
        _sessionMaxLevel = 1;
        _sessionMaxStreak = 0;
        _showSessionSummary = false;
        _freeHintsRemainingInLevel = 1;
        _hintedTile = null;
        _tileEntryScales = List.filled(9, 0.0);
      });

      _saveGameProgress();

      // Staggered tile entry animation then run playback
      Future.microtask(() async {
        for (int i = 0; i < 9; i++) {
          await Future.delayed(const Duration(milliseconds: 60));
          if (!mounted || _gameState == GameState.startScreen || _playbackSessionId != currentSession) return;
          setState(() => _tileEntryScales[i] = 1.0);
        }

        if (!mounted || _gameState == GameState.startScreen || _playbackSessionId != currentSession) return;
        setState(() => _sequence.add(_random.nextInt(9)));
        _runPlayback();
      });
    }

    if (kIsWeb) {
      _showTestInterstitialOverlay(onDismissed: launchGame);
    } else {
      final shown = await AdService.instance.showInterstitialAdOrLoad(onDismissed: launchGame);
      if (!shown) {
        launchGame();
      }
    }
  }

  void _continueSession() async {
    _cancelInputTimer();
    _particleManager.clear();
    _playbackSessionId++;
    final currentSession = _playbackSessionId;
    HapticFeedback.mediumImpact();

    setState(() {
      if (!_hasSeenTutorial) {
        _hasSeenTutorial = true;
        _showTutorialCard = false;
        _prefs.setBool('focus_spark_has_seen_tutorial', true);
      }
      _gameState = GameState.playback;
      _playerInput.clear();
      _showSessionSummary = false;
      _freeHintsRemainingInLevel = 1;
      _hintedTile = null;
      _tileEntryScales = List.filled(9, 0.0);
    });

    // Staggered tile entry animation
    for (int i = 0; i < 9; i++) {
      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted || _gameState == GameState.startScreen || _playbackSessionId != currentSession) return;
      setState(() => _tileEntryScales[i] = 1.0);
    }

    if (_playbackSessionId != currentSession) return;
    if (_sequence.isEmpty) {
      _level = 1;
      _sequence.add(_random.nextInt(9));
      await _saveGameProgress();
    }
    _runPlayback();
  }

  // ── Playback Engine ──────────────────────────────────────────────────────
  Future<void> _runPlayback() async {
    if (_gameState != GameState.playback) return;
    final currentSession = _playbackSessionId;

    // Adaptive speed: Max(380ms, 650ms - level*25ms)
    final int speedMs = (650 - (_level * 25)).clamp(380, 650);
    final int activeMs = (speedMs * 0.75).round();
    final int gapMs = speedMs - activeMs;

    // Brief pre-playback pause so user can settle
    await Future.delayed(const Duration(milliseconds: 300));
    if (_gameState != GameState.playback || _playbackSessionId != currentSession) return;

    for (int i = 0; i < _sequence.length; i++) {
      if (_gameState != GameState.playback || _playbackSessionId != currentSession) return;
      final tileIndex = _sequence[i];

      setState(() => _activePlaybackTile = tileIndex);

      final theme = _themes[_selectedThemeIndex];
      _spawnTileSparks(tileIndex, theme.tileActiveGlow.withValues(alpha: 0.35));

      if (!_isSfxMuted) {
        AudioService.instance.playTone(_frequencies[tileIndex], activeMs / 1000.0);
      }

      await Future.delayed(Duration(milliseconds: activeMs));
      if (_gameState != GameState.playback || _playbackSessionId != currentSession) return;

      setState(() => _activePlaybackTile = null);
      await Future.delayed(Duration(milliseconds: gapMs));
    }

    if (_gameState == GameState.playback && _playbackSessionId == currentSession) {
      setState(() {
        _gameState = GameState.playerInput;
        _playerInput.clear();
      });
      _startInputTimer();
    }
  }

  // ── Input Timer ──────────────────────────────────────────────────────────
  void _startInputTimer() {
    _cancelInputTimer();
    _totalInputTime = 6.0 + (_sequence.length * 1.2);
    _elapsedInputTime = 0.0;
    _inputTimerPercentage = 1.0;

    _inputTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_gameState != GameState.playerInput) {
        _cancelInputTimer();
        return;
      }
      setState(() {
        _elapsedInputTime += 0.05;
        _inputTimerPercentage =
            (1.0 - (_elapsedInputTime / _totalInputTime)).clamp(0.0, 1.0);
      });
      if (_elapsedInputTime >= _totalInputTime) {
        _cancelInputTimer();
        _handleTimeout();
      }
    });
  }

  void _cancelInputTimer() {
    _inputTimer?.cancel();
    _inputTimer = null;
  }

  void _handleTimeout() {
    if (_gameState != GameState.playerInput) return;
    setState(() {
      _gameState = GameState.errorTransition;
      _currentStreak = 0;
      _correctErrorTile = _sequence[_playerInput.length];
      _hintedTile = null;
    });
    HapticFeedback.vibrate();
    if (!_isSfxMuted) AudioService.instance.playTone(130.81, 0.4);

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _gameState == GameState.errorTransition) {
        setState(() {
          _correctErrorTile = null;
          _gameState = GameState.playback;
          _playerInput.clear();
        });
        _runPlayback();
      }
    });
  }

  // ── Pause / Resume ───────────────────────────────────────────────────────
  void _togglePause() {
    if (_gameState == GameState.playback || _gameState == GameState.playerInput) {
      _cancelInputTimer();
      setState(() {
        _gameState = GameState.paused;
        _activePlaybackTile = null;
      });
      HapticFeedback.selectionClick();
    } else if (_gameState == GameState.paused) {
      setState(() => _gameState = GameState.playback);
      HapticFeedback.selectionClick();
      _runPlayback();
    }
  }

  // ── Hint & Direct Rewarded Ad System ────────────────────────────────────
  void _triggerHint() {
    if (_gameState != GameState.playerInput || _playerInput.length >= _sequence.length) return;
    final nextTile = _sequence[_playerInput.length];
    final theme = _themes[_selectedThemeIndex];

    _spawnTileSparks(nextTile, theme.tileActiveGlow);

    setState(() {
      _hintedTile = nextTile;
    });

    HapticFeedback.mediumImpact();
  }

  void _onHintPressed() {
    if (_gameState != GameState.playerInput || _isAdActive) return;

    if (_freeHintsRemainingInLevel > 0) {
      setState(() {
        _freeHintsRemainingInLevel--;
      });
      _triggerHint();
    } else {
      _playDirectRewardedAd();
    }
  }

  void _showTestInterstitialOverlay({VoidCallback? onDismissed}) async {
    if (_isAdActive) return;
    _cancelInputTimer();
    HapticFeedback.mediumImpact();

    setState(() {
      _isAdActive = true;
      _activeAdType = 'INTERSTITIAL TEST AD';
    });

    await Future.delayed(const Duration(milliseconds: 2500));

    if (!mounted) return;

    setState(() {
      _isAdActive = false;
    });

    onDismissed?.call();
  }

  void _playDirectRewardedAd() async {
    if (_isAdActive) return;
    _cancelInputTimer();
    HapticFeedback.mediumImpact();

    final shown = await AdService.instance.showRewardedAdOrLoad(
      onUserEarnedReward: (reward) {
        if (_gameState == GameState.playerInput && mounted) {
          _startInputTimer();
          _triggerHint();
        }
      },
    );

    if (shown) return;

    // Fallback visible test ad overlay for rewarded ad
    setState(() {
      _isAdActive = true;
      _activeAdType = 'REWARDED VIDEO TEST AD';
    });

    await Future.delayed(const Duration(milliseconds: 3000));

    if (!mounted) return;

    setState(() {
      _isAdActive = false;
    });

    if (_gameState == GameState.playerInput) {
      _startInputTimer();
      _triggerHint();
    }
  }

  Widget _buildDirectAdOverlay(GameTheme theme) {
    if (!_isAdActive) return const SizedBox.shrink();
    final isRewarded = _activeAdType.contains('REWARDED');

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.94),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: BoxDecoration(
                color: theme.panelBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF4285F4).withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                    blurRadius: 32,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Google AdMob Test Ad Header Tag
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA4335),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Ad',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Google AdMob Test Ad',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: theme.textPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Center Ad Icon
                  Icon(
                    isRewarded ? Icons.ondemand_video_rounded : Icons.branding_watermark_rounded,
                    color: const Color(0xFF4285F4),
                    size: 48,
                  ),
                  const SizedBox(height: 16),

                  Text(
                    _activeAdType,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isRewarded
                        ? 'Watching Test Video... Reward: +1 Free Hint'
                        : 'Google Test Interstitial Ad View',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.textPrimary.withValues(alpha: 0.65),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Progress loading indicator
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4285F4)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Ad Unit ID Subtitle
                  Text(
                    isRewarded
                        ? 'Unit ID: ca-app-pub-3940256099942544/5224354917'
                        : 'Unit ID: ca-app-pub-3940256099942544/1033173712',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: theme.textPrimary.withValues(alpha: 0.4),
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

  // ── Go Home ──────────────────────────────────────────────────────────────
  void _goHome() async {
    _cancelInputTimer();
    _particleManager.clear();
    _playbackSessionId++; // Cancel any active async playback loops

    if (_sequence.isNotEmpty) {
      await _saveGameProgress();
    }

    setState(() {
      _gameState = GameState.startScreen;
      _activePlaybackTile = null;
      _correctErrorTile = null;
      _activeTapTile = null;
      _hintedTile = null;
      _tileEntryScales = List.filled(9, 1.0);
      _inputTimerPercentage = 1.0;
    });
    HapticFeedback.selectionClick();
  }

  // ── Reset Session ────────────────────────────────────────────────────────
  void _resetSession() {
    _cancelInputTimer();
    _particleManager.clear();
    _playbackSessionId++; // Cancel any active async playback loops

    // Capture session summary before reset
    final lvl = _level;
    final streak = _currentStreak;
    final wasMeaningful = lvl > 1 || streak > 0;

    setState(() {
      _gameState = GameState.startScreen;
      _sequence.clear();
      _playerInput.clear();
      _level = 1;
      _currentStreak = 0;
      _activePlaybackTile = null;
      _correctErrorTile = null;
      _activeTapTile = null;
      _hintedTile = null;
      _tileEntryScales = List.filled(9, 1.0);
      _inputTimerPercentage = 1.0;
      if (wasMeaningful) {
        _sessionMaxLevel = lvl;
        _sessionMaxStreak = streak;
        _showSessionSummary = true;
      }
    });
    HapticFeedback.mediumImpact();

    if (wasMeaningful) {
      // Auto-dismiss summary after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showSessionSummary = false);
      });
    }
  }

  // ── Tile Click ───────────────────────────────────────────────────────────
  void _handleTileClick(int clickedIndex) {
    if (_gameState != GameState.playerInput) return;

    if (_hintedTile != null) {
      setState(() {
        _hintedTile = null;
      });
    }

    final expectedIndex = _sequence[_playerInput.length];
    final theme = _themes[_selectedThemeIndex];

    if (clickedIndex == expectedIndex) {
      setState(() => _playerInput.add(clickedIndex));

      if (_playerInput.length == _sequence.length) {
        // SUCCESS
        _cancelInputTimer();
        final completedLevel = _level;
        setState(() {
          _gameState = GameState.successTransition;
          _currentStreak++;
          _level++;
          _freeHintsRemainingInLevel = 1;
          if (_level > _sessionMaxLevel) _sessionMaxLevel = _level;
          if (_currentStreak > _sessionMaxStreak) _sessionMaxStreak = _currentStreak;
          if (completedLevel > _highScore) {
            _highScore = completedLevel;
          }
        });
        if (completedLevel > _highScore) _updateHighScore(completedLevel);
        _recordLeaderboardScore(completedLevel, _currentStreak);

        _spawnSuccessSparks(theme.accentColor);

        if (!_isSfxMuted) {
          final frequency = _frequencies[clickedIndex];
          AudioService.instance.playTone(frequency, 0.25);
          Future.delayed(const Duration(milliseconds: 120),
              () => AudioService.instance.playTone(587.33, 0.22));
        }

        Future.delayed(const Duration(milliseconds: 850), () {
          if (mounted && _gameState == GameState.successTransition) {
            _showLevelCompletedModal(context, theme, completedLevel);
          }
        });
      }
    } else {
      // FAILURE (zero-punishment rule)
      _cancelInputTimer();
      setState(() {
        _gameState = GameState.errorTransition;
        _currentStreak = 0;
        _correctErrorTile = expectedIndex;
      });
      _saveGameProgress();
      HapticFeedback.vibrate();
      if (!_isSfxMuted) AudioService.instance.playTone(130.81, 0.4);

      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && _gameState == GameState.errorTransition) {
          setState(() {
            _correctErrorTile = null;
            _gameState = GameState.playback;
            _playerInput.clear();
          });
          _runPlayback();
        }
      });
    }
  }

  // ── Status Text ──────────────────────────────────────────────────────────
  String _getStatusText() {
    switch (_gameState) {
      case GameState.startScreen:
        return 'Clear your mind. Tap Start to begin.';
      case GameState.playback:
        return 'Watch the spark pattern carefully...';
      case GameState.playerInput:
        return 'Now replicate the pattern from memory.';
      case GameState.paused:
        return 'Breathe in, breathe out. Session paused.';
      case GameState.successTransition:
        return '✦ Excellent focus! Advancing...';
      case GameState.errorTransition:
        return 'Focus shifted. Replaying the pattern...';
    }
  }

  // ── Grid Tile Builder ─────────────────────────────────────────────────────
  Widget _buildGridTile(int index, GameTheme theme) {
    final bool isHovered = _hoverStates[index];
    final bool isPlaybackFlash =
        _gameState == GameState.playback && _activePlaybackTile == index;
    final bool isTapFlash = _activeTapTile == index;
    final bool isHinted = _hintedTile == index;
    final bool isErrorFlash =
        _gameState == GameState.errorTransition && _correctErrorTile == index;
    final bool isSuccess = _gameState == GameState.successTransition;
    final bool isFlashing = isPlaybackFlash || isTapFlash || isHinted;
    final bool inputLock = _gameState != GameState.playerInput;

    double scale = _tileEntryScales[index];
    if (isTapFlash) {
      scale *= 0.94;
    } else if (isFlashing) {
      scale *= 1.05;
    }

    double translateY = 0.0;
    if (isTapFlash) {
      translateY = 2.0;
    } else if (isHovered && !inputLock) {
      translateY = -4.0;
    }

    Color tileColor = theme.tileDefault;
    if (isSuccess) {
      tileColor = theme.successColor.withValues(alpha: 0.18);
    } else if (isFlashing) {
      tileColor = theme.tileActiveGlow.withValues(alpha: 0.85);
    } else if (isErrorFlash) {
      tileColor = const Color(0xFFEF4444).withValues(alpha: 0.75);
    } else if (isHovered && !inputLock) {
      tileColor = theme.tileDefault.withValues(alpha: 0.20);
    }

    BoxShadow? glowShadow;
    if (isSuccess) {
      glowShadow = BoxShadow(
        color: theme.successColor.withValues(alpha: 0.4),
        blurRadius: 16,
        spreadRadius: 1,
      );
    } else if (isFlashing) {
      glowShadow = BoxShadow(
        color: theme.tileActiveGlow.withValues(alpha: 0.85),
        blurRadius: 22,
        spreadRadius: 3,
      );
    } else if (isErrorFlash) {
      glowShadow = BoxShadow(
        color: const Color(0xFFEF4444).withValues(alpha: 0.80),
        blurRadius: 22,
        spreadRadius: 3,
      );
    }

    // Highlight the most recently correctly-entered tile briefly
    final bool playerHitHighlight = _gameState == GameState.playerInput &&
        _playerInput.isNotEmpty &&
        _playerInput.last == index;

    return _HintTilePulse(
      isHinted: isHinted,
      pulseColor: theme.tileActiveGlow,
      child: MouseRegion(
        cursor: inputLock ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) {
          if (!inputLock) setState(() => _hoverStates[index] = true);
        },
        onExit: (_) => setState(() => _hoverStates[index] = false),
        child: GestureDetector(
          onTapDown: (_) {
            if (!inputLock) {
              setState(() => _activeTapTile = index);
              _spawnTileSparks(index, theme.tileActiveGlow);
              HapticFeedback.selectionClick();
              if (!_isSfxMuted) {
                AudioService.instance.playTone(_frequencies[index], 0.22);
              }
            }
          },
          onTapUp: (_) {
            if (_activeTapTile == index) {
              setState(() => _activeTapTile = null);
              _handleTileClick(index);
            }
          },
          onTapCancel: () {
            if (_activeTapTile == index) setState(() => _activeTapTile = null);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOutCubic,
            transform: Matrix4.identity()
              ..translate(0.0, translateY)
              ..scale(scale),
            decoration: BoxDecoration(
              color: tileColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isErrorFlash
                    ? const Color(0xFFEF4444)
                    : isSuccess
                        ? theme.successColor.withValues(alpha: 0.5)
                        : isFlashing
                            ? theme.tileActiveGlow
                            : playerHitHighlight
                                ? theme.accentColor.withValues(alpha: 0.6)
                                : theme.panelBorder.withValues(alpha: 0.45),
                width: isFlashing || isErrorFlash || isSuccess ? 2.0 : 1.0,
              ),
              boxShadow: glowShadow != null
                  ? [glowShadow]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 4),
                      )
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Center(
                  child: AnimatedOpacity(
                    opacity: isFlashing || isErrorFlash || isSuccess ? 0.0 : (inputLock ? 0.0 : 0.15),
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── HUD Item ─────────────────────────────────────────────────────────────
  Widget _buildHUDItem(String title, String value, GameTheme theme, {Color? valueColor, double fontSize = 18.0}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: theme.textPrimary.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(height: 3),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: child,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              key: ValueKey<String>(value),
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: valueColor ?? theme.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Theme Dot ─────────────────────────────────────────────────────────────
  Widget _buildThemeDot(int index, GameTheme currentTheme) {
    final isSelected = _selectedThemeIndex == index;
    final themePreset = _themes[index];

    return GestureDetector(
      onTap: () {
        _selectTheme(index);
        HapticFeedback.selectionClick();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        width: isSelected ? 24 : 18,
        height: isSelected ? 24 : 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [themePreset.bgGradient[1], themePreset.accentColor],
          ),
          border: Border.all(
            color: isSelected ? currentTheme.textPrimary : Colors.transparent,
            width: 2.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: themePreset.accentColor.withValues(alpha: 0.6),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
      ),
    );
  }

  // ── Sequence Progress Dots ───────────────────────────────────────────────
  Widget _buildProgressDots(GameTheme theme) {
    if (_gameState != GameState.playerInput || _sequence.isEmpty) {
      return const SizedBox(height: 16);
    }
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_sequence.length, (i) {
          final bool filled = i < _playerInput.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: filled ? 8 : 6,
            height: filled ? 8 : 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? theme.accentColor
                  : theme.textPrimary.withValues(alpha: 0.2),
              boxShadow: filled
                  ? [BoxShadow(color: theme.accentColor.withValues(alpha: 0.5), blurRadius: 6)]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  // ── Session Summary Card ─────────────────────────────────────────────────
  Widget _buildSessionSummary(GameTheme theme) {
    return AnimatedOpacity(
      opacity: _showSessionSummary ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      child: IgnorePointer(
        ignoring: !_showSessionSummary,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: theme.panelBg.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.accentColor.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(color: theme.accentColor.withValues(alpha: 0.1), blurRadius: 20),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text('SESSION',
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.6,
                          color: theme.textPrimary.withValues(alpha: 0.4))),
                  const SizedBox(height: 2),
                  Text('SUMMARY',
                      style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.6,
                          color: theme.textPrimary.withValues(alpha: 0.4))),
                ],
              ),
              _buildHUDItem('LEVEL REACHED', _sessionMaxLevel.toString(), theme,
                  valueColor: theme.accentColor),
              _buildHUDItem('BEST STREAK', _sessionMaxStreak.toString(), theme),
            ],
          ),
        ),
      ),
    );
  }

  // ── Pause Overlay ────────────────────────────────────────────────────────
  Widget _buildPauseOverlay(GameTheme theme) {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _gameState == GameState.paused ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: _gameState != GameState.paused,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: Colors.black.withValues(alpha: 0.45),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.pause_circle_outline_rounded,
                        size: 52, color: theme.accentColor.withValues(alpha: 0.85)),
                    const SizedBox(height: 12),
                    Text(
                      'PAUSED',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Take a moment to breathe.',
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.textPrimary.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Splash Screen Decorative Panel ───────────────────────────────────────
  Widget _buildSplashContent(GameTheme theme) {
    return Column(
      children: [
        const SizedBox(height: 12),
        // Orbital Pulsing Hero Logo
        _OrbitalHeroLogo(
          accentColor: theme.accentColor,
          onTap: () => _showLevelRoadmapModal(context, theme),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  Widget _buildInstruction(String bullet, String text, GameTheme theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(bullet,
              style: TextStyle(
                  color: theme.accentColor.withValues(alpha: 0.7), fontSize: 10)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 12,
                  color: theme.textPrimary.withValues(alpha: 0.6),
                  height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Main Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = _themes[_selectedThemeIndex];
    final isStart = _gameState == GameState.startScreen;
    final isGameActive = !isStart;
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : 18.0;

    if (_splashStage == 0) {
      return _CompanySplashScreen(
        theme: theme,
        onComplete: () {
          if (mounted) {
            setState(() {
              _splashStage = 1;
            });
          }
        },
      );
    }

    if (_splashStage == 1) {
      return _FullScreenSplashScreen(
        theme: theme,
        onLoadingComplete: () {
          if (mounted) {
            setState(() {
              _splashStage = 2;
            });
            if (!_isMusicMuted) {
              AudioService.instance.startAmbientMusic();
            }
          }
        },
      );
    }

    return Scaffold(
      body: AnimatedGradientBackground(
        colors: theme.bgGradient,
        child: SafeArea(
          child: Column(
            children: [
              // ── Full-Width Edge-to-Edge Header Bar ──────────────────────────────
              Padding(
                padding: EdgeInsets.only(
                  left: horizontalPadding,
                  right: horizontalPadding,
                  top: 28.0,
                  bottom: 16.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox.shrink(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1. Leaderboard / Hall of Fame Icon (Home Screen Only)
                        if (isStart) ...[
                          _buildIconToggle(
                            icon: Icons.emoji_events_outlined,
                            isActive: false,
                            onTap: () => _showLeaderboardModal(context, theme),
                            theme: theme,
                            tooltip: 'Hall of Fame',
                          ),
                          const SizedBox(width: 4),
                        ],

                        // Return to Home (Active Gameplay Only)
                        if (isGameActive) ...[
                          _buildIconToggle(
                            icon: Icons.home_outlined,
                            isActive: false,
                            onTap: _goHome,
                            theme: theme,
                            tooltip: 'Return to Home',
                          ),
                          const SizedBox(width: 4),
                        ],

                        // 2a. Ambient Music Toggle Button
                        _buildIconToggle(
                          icon: _isMusicMuted
                              ? Icons.music_off_rounded
                              : Icons.music_note_rounded,
                          isActive: !_isMusicMuted,
                          onTap: _toggleMusic,
                          theme: theme,
                          tooltip: _isMusicMuted ? 'Enable Music' : 'Mute Music',
                        ),
                        const SizedBox(width: 4),

                        // 2b. Sound Effects (SFX) Toggle Button
                        _buildIconToggle(
                          icon: _isSfxMuted
                              ? Icons.volume_off_outlined
                              : Icons.volume_up_outlined,
                          isActive: !_isSfxMuted,
                          onTap: _toggleSfx,
                          theme: theme,
                          tooltip: _isSfxMuted ? 'Enable SFX' : 'Mute SFX',
                        ),
                        const SizedBox(width: 4),

                        // 3. How to Play Icon (Home Screen Only)
                        if (isStart) ...[
                          _buildIconToggle(
                            icon: Icons.help_outline_rounded,
                            isActive: false,
                            onTap: () => _showInstructionsModal(context, theme),
                            theme: theme,
                            tooltip: 'How to Play',
                          ),
                          const SizedBox(width: 4),
                        ],

                        // 4. Zen Mode Button
                        _buildIconToggle(
                          icon: _isZenMode ? Icons.spa : Icons.spa_outlined,
                          isActive: _isZenMode,
                          onTap: _toggleZenMode,
                          theme: theme,
                          tooltip: _isZenMode
                              ? 'Disable Zen Mode'
                              : 'Enable Zen Mode',
                        ),
                        const SizedBox(width: 4),

                        // 5. Theme Dots (Cosmic Indigo, Sage Calm, Midnight Cyber)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            _themes.length,
                            (i) => _buildThemeDot(i, theme),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Centered Main Content Area ─────────────────────────────────────
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8.0),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Session Summary (appears on splash after a session) ─
                          if (isStart) _buildSessionSummary(theme),

                    // ── Glassmorphic Main Panel ───────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: theme.panelBg,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _gameState == GameState.successTransition
                              ? theme.successColor.withValues(alpha: 0.55)
                              : theme.panelBorder,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                          if (_gameState == GameState.successTransition)
                            BoxShadow(
                              color: theme.successColor.withValues(alpha: 0.12),
                              blurRadius: 24,
                              spreadRadius: 4,
                            ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                        child: Padding(
                          padding: const EdgeInsets.all(22.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ── HUD ─────────────────────────────────────
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 280),
                                crossFadeState: _isZenMode || isStart
                                    ? CrossFadeState.showFirst
                                    : CrossFadeState.showSecond,
                                firstChild: const SizedBox(height: 0, width: double.infinity),
                                secondChild: Padding(
                                  padding: const EdgeInsets.only(bottom: 18.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildHUDItem('LEVEL', _level.toString(), theme),
                                      _buildHUDItem('STREAK', _currentStreak.toString(), theme,
                                          valueColor: _currentStreak > 0
                                              ? theme.accentColor
                                              : null),
                                      _buildHUDItem(
                                          'BEST', _highScore.toString(), theme),
                                    ],
                                  ),
                                ),
                              ),

                              // ── Input Timer Bar ──────────────────────────
                              AnimatedOpacity(
                                opacity: _gameState == GameState.playerInput ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 250),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Container(
                                          height: 5,
                                          color: theme.tileDefault,
                                          child: FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: _inputTimerPercentage,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    _inputTimerPercentage > 0.3
                                                        ? theme.accentColor
                                                        : const Color(0xFFEF4444),
                                                    theme.tileActiveGlow,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // ── Grid (or splash content) ─────────────────
                              if (isStart)
                                _buildSplashContent(theme)
                              else
                                Stack(
                                  children: [
                                    ShakeWidget(
                                      shake: _gameState == GameState.errorTransition,
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          _gridWidth = constraints.maxWidth;
                                          _gridHeight = constraints.maxWidth;
                                          return GridView.count(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            crossAxisCount: 3,
                                            mainAxisSpacing: 12,
                                            crossAxisSpacing: 12,
                                            children: List.generate(
                                              9,
                                              (index) => _buildGridTile(index, theme),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    // Particle canvas overlay
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: ListenableBuilder(
                                          listenable: _particleManager,
                                          builder: (context, _) => CustomPaint(
                                            painter: ParticlePainter(
                                                particles:
                                                    _particleManager.particles),
                                          ),
                                        ),
                                      ),
                                    ),
                                     // Pause overlay
                                     _buildPauseOverlay(theme),
                                     // Direct Rewarded Ad overlay
                                     _buildDirectAdOverlay(theme),
                                   ],
                                 ),

                              if (isGameActive) ...[
                                const SizedBox(height: 14),
                                // Progress dots
                                _buildProgressDots(theme),
                                const SizedBox(height: 12),
                                // Status text
                                Text(
                                  _getStatusText(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.textPrimary.withValues(alpha: 0.65),
                                    height: 1.4,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 56),

                    // ── Controls Row ────────────────────────────────────────
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        // Action Buttons
                        Wrap(
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (isGameActive) ...[
                              ElevatedButton.icon(
                                onPressed: (_gameState != GameState.playerInput || _isAdActive)
                                    ? null
                                    : _onHintPressed,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _freeHintsRemainingInLevel > 0
                                      ? theme.accentColor.withValues(alpha: 0.22)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.22),
                                  foregroundColor: theme.textPrimary,
                                  disabledBackgroundColor:
                                      theme.tileDefault.withValues(alpha: 0.4),
                                  disabledForegroundColor:
                                      theme.textPrimary.withValues(alpha: 0.3),
                                  side: BorderSide(
                                    color: _freeHintsRemainingInLevel > 0
                                        ? theme.accentColor.withValues(alpha: 0.45)
                                        : const Color(0xFFF59E0B).withValues(alpha: 0.6),
                                  ),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(
                                  _freeHintsRemainingInLevel > 0
                                      ? Icons.lightbulb_outline_rounded
                                      : Icons.ondemand_video_rounded,
                                  size: 16,
                                  color: _freeHintsRemainingInLevel > 0
                                      ? theme.accentColor
                                      : const Color(0xFFF59E0B),
                                ),
                                label: Text(
                                  _freeHintsRemainingInLevel > 0 ? 'HINT (FREE)' : 'HINT (+AD)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    letterSpacing: 0.8,
                                    color: _freeHintsRemainingInLevel > 0
                                        ? theme.accentColor
                                        : const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _startSession,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'RESTART',
                                  style: TextStyle(
                                    color: theme.textPrimary.withValues(alpha: 0.55),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: (_gameState == GameState.successTransition ||
                                        _gameState == GameState.errorTransition)
                                    ? null
                                    : _togglePause,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      theme.accentColor.withValues(alpha: 0.22),
                                  foregroundColor: theme.textPrimary,
                                  disabledBackgroundColor:
                                      theme.tileDefault.withValues(alpha: 0.4),
                                  disabledForegroundColor:
                                      theme.textPrimary.withValues(alpha: 0.3),
                                  side: BorderSide(
                                      color: theme.accentColor.withValues(alpha: 0.45)),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                icon: Icon(
                                  _gameState == GameState.paused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  _gameState == GameState.paused ? 'RESUME' : 'PAUSE',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1.0),
                                ),
                              ),
                            ] else ...[
                              if (_hasSavedSession) ...[
                                TextButton(
                                  onPressed: _startSession,
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 8),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    'NEW SESSION',
                                    style: TextStyle(
                                      color: theme.textPrimary.withValues(alpha: 0.55),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _continueSession,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.accentColor,
                                    foregroundColor: Colors.black87,
                                    elevation: 6,
                                    shadowColor: theme.accentColor.withValues(alpha: 0.45),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16)),
                                  ),
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: Text(
                                    'CONTINUE (LVL $_level)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                ElevatedButton(
                                  onPressed: _startSession,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.accentColor,
                                    foregroundColor: Colors.black87,
                                    elevation: 6,
                                    shadowColor: theme.accentColor.withValues(alpha: 0.45),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: const Text(
                                    'NEW SESSION',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildBannerAdSpace(theme),
      ],
    ),
        ),
      ),
    );
  }

  Widget _buildBannerAdSpace(GameTheme theme) {
    return Container(
      width: double.infinity,
      height: 52.0,
      decoration: BoxDecoration(
        color: theme.panelBg.withValues(alpha: 0.45),
        border: Border(
          top: BorderSide(
            color: theme.panelBorder.withValues(alpha: 0.35),
            width: 1.0,
          ),
        ),
      ),
      child: Center(
        child: _isBannerAdLoaded && _bannerAd != null
            ? SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.subtitles_outlined,
                    size: 15,
                    color: theme.textPrimary.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'BANNER AD SPACE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.6,
                      color: theme.textPrimary.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Level Progression Helper ─────────────────────────────────────────────
  void _advanceToNextLevelPlayback(int completedLevel) {
    if (!mounted || _gameState != GameState.successTransition) return;

    // Custom Interstitial Ad Frequency Rule
    if (AdService.shouldShowInterstitialOnLevelComplete(completedLevel)) {
      AdService.instance.showInterstitialAdOrLoad();
    }

    setState(() {
      _gameState = GameState.playback;
      _sequence.add(_random.nextInt(9));
    });
    _saveGameProgress();
    _runPlayback();
  }

  // ── Level Completed Victory Modal ───────────────────────────────────────
  void _showLevelCompletedModal(BuildContext context, GameTheme theme, int completedLevel) {
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 80), () => HapticFeedback.mediumImpact());

    String? milestoneRank;
    if (completedLevel == 5) {
      milestoneRank = 'SPARK INITIATE';
    } else if (completedLevel == 10) {
      milestoneRank = 'MATRIX ADEPT';
    } else if (completedLevel == 15) {
      milestoneRank = 'FOCUS SCHOLAR';
    } else if (completedLevel == 20) {
      milestoneRank = 'SPARK MASTER';
    } else if (completedLevel == 25) {
      milestoneRank = 'MATRIX GRANDMASTER';
    } else if (completedLevel == 30) {
      milestoneRank = 'MINDFUL LEGEND';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: theme.panelBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.accentColor.withValues(alpha: 0.6), width: 1.5),
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
                // Glowing Trophy Icon Badge
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.accentColor.withValues(alpha: 0.15),
                    border: Border.all(color: theme.accentColor, width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: theme.accentColor.withValues(alpha: 0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: 42,
                    color: theme.accentColor,
                  ),
                ),
                const SizedBox(height: 18),

                // Victory Header
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Colors.white,
                      theme.accentColor,
                      theme.tileActiveGlow,
                    ],
                  ).createShader(bounds),
                  child: Text(
                    'LEVEL $completedLevel COMPLETED!',
                    style: GoogleFonts.orbitron(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'EXCELLENT PATTERN REPLICATION',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: theme.textPrimary.withValues(alpha: 0.6),
                  ),
                  textAlign: TextAlign.center,
                ),

                if (milestoneRank != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.accentColor.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          'RANK UNLOCKED: $milestoneRank',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: theme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 22),

                // Performance Summary HUD Grid
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.panelBorder.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildHUDItem('NEXT LEVEL', 'LVL $_level', theme,
                            valueColor: theme.accentColor, fontSize: 14.0),
                      ),
                      Container(
                        height: 24,
                        width: 1,
                        color: theme.panelBorder.withValues(alpha: 0.3),
                      ),
                      Expanded(
                        child: _buildHUDItem('STREAK', '$_currentStreak 🔥', theme,
                            fontSize: 14.0),
                      ),
                      Container(
                        height: 24,
                        width: 1,
                        color: theme.panelBorder.withValues(alpha: 0.3),
                      ),
                      Expanded(
                        child: _buildHUDItem(
                            'BEST SCORE',
                            'LVL ${math.max(completedLevel, _highScore > completedLevel && _highScore == completedLevel + 1 ? completedLevel : _highScore)}',
                            theme,
                            fontSize: 14.0),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 26),

                // Primary Action Button: CONTINUE TO NEXT LEVEL
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _advanceToNextLevelPlayback(completedLevel);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accentColor,
                      foregroundColor: Colors.black87,
                      elevation: 8,
                      shadowColor: theme.accentColor.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: Text(
                      'CONTINUE TO LEVEL $_level',
                      style: GoogleFonts.orbitron(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Secondary Action Button: VIEW ROADMAP
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showLevelRoadmapModal(
                        context,
                        theme,
                        onDismiss: () {
                          _advanceToNextLevelPlayback(completedLevel);
                        },
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.textPrimary,
                      side: BorderSide(color: theme.panelBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: Icon(Icons.map_outlined, size: 16, color: theme.textPrimary.withValues(alpha: 0.7)),
                    label: Text(
                      'VIEW ROADMAP',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: theme.textPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Instructions Modal ────────────────────────────────────────────────
  void _showInstructionsModal(BuildContext context, GameTheme theme) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
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
                  padding: const EdgeInsets.all(22.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                                style: TextStyle(
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
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Colors.white12),
                      const SizedBox(height: 16),
                      _buildInstruction('✦', 'Watch the tiles flash in sequence', theme),
                      _buildInstruction('✦', 'Replicate the pattern by tapping', theme),
                      _buildInstruction('✦', 'Each round adds one more step', theme),
                      _buildInstruction('✦', '1 Free Hint per level + Direct Rewarded Ad', theme),
                      _buildInstruction('✦', 'No punishment — just keep going & stay focused!', theme),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.accentColor,
                            foregroundColor: Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'GOT IT!',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Level Roadmap Modal ────────────────────────────────────────────────
  void _showLevelRoadmapModal(BuildContext context, GameTheme theme, {VoidCallback? onDismiss}) {
    HapticFeedback.selectionClick();
    final clearedLevel = _level > 1 ? _level - 1 : 0;
    final effectiveBest = math.max(clearedLevel, _highScore);
    final maxTargetLevel = math.max(effectiveBest + 8, 25);
    final ScrollController scrollController = ScrollController();

    // Auto-scroll to center current level after frame render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        final targetOffset = (_level - 1) * 70.0;
        scrollController.animateTo(
          targetOffset.clamp(0.0, scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
        );
      }
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
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
                                style: TextStyle(
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
                              'CURRENT: LVL $_level',
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

                      // Winding Level Path
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: maxTargetLevel,
                          itemBuilder: (context, index) {
                            final lvl = index + 1;
                            final isCurrent = lvl == _level;
                            final isBestPeak = lvl == _highScore && _highScore > 0;
                            final isPassed = (lvl < _level) || (lvl <= _highScore && !isCurrent && !isBestPeak);

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
                                SizedBox(
                                  height: 70,
                                  child: Stack(
                                    children: [
                                      // Seamless Bezier Curved Connecting Line
                                      if (lvl < maxTargetLevel)
                                        Positioned.fill(
                                          child: CustomPaint(
                                            painter: _RoadmapSegmentPainter(
                                              startAlignX: alignX,
                                              endAlignX: nextAlignX,
                                              lineColor: isPassed || isCurrent || (lvl < _highScore)
                                                  ? theme.accentColor.withValues(alpha: 0.65)
                                                  : theme.panelBorder.withValues(alpha: 0.3),
                                            ),
                                          ),
                                        ),
                                      // Level Node
                                      Align(
                                        alignment: Alignment(alignX, 0.0),
                                        child: nodeWidget,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (_gameState == GameState.successTransition) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.accentColor,
                              foregroundColor: Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: Text(
                              'CONTINUE TO LEVEL $_level',
                              style: GoogleFonts.orbitron(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((_) {
      onDismiss?.call();
    });
  }

  // ── Leaderboard Modal ──────────────────────────────────────────────────
  void _showLeaderboardModal(BuildContext context, GameTheme theme) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
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
                      // Modal Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.emoji_events_rounded,
                                  color: Color(0xFFFFD700), size: 24),
                              const SizedBox(width: 8),
                              Text(
                                'HALL OF FAME',
                                style: TextStyle(
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
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Colors.white12),
                      const SizedBox(height: 12),

                      // Leaderboard Content List
                      Expanded(
                        child: _leaderboard.isEmpty
                            ? Center(
                                child: Text(
                                  'No scores recorded yet.\nPlay a session to enter the Hall of Fame!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.textPrimary.withValues(alpha: 0.5),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _leaderboard.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final entry = _leaderboard[index];
                                  final rank = index + 1;
                                  final isTop3 = rank <= 3;
                                  Color badgeColor = theme.accentColor;
                                  if (rank == 1) badgeColor = const Color(0xFFFFD700);
                                  if (rank == 2) badgeColor = const Color(0xFFC0C0C0);
                                  if (rank == 3) badgeColor = const Color(0xFFCD7F32);

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isTop3
                                          ? badgeColor.withValues(alpha: 0.12)
                                          : theme.tileDefault.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isTop3
                                            ? badgeColor.withValues(alpha: 0.4)
                                            : theme.panelBorder.withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Rank Badge
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: badgeColor.withValues(alpha: 0.22),
                                            border: Border.all(
                                                color: badgeColor.withValues(alpha: 0.6),
                                                width: 1),
                                          ),
                                          child: Center(
                                            child: Text(
                                              rank == 1
                                                  ? '🥇'
                                                  : rank == 2
                                                      ? '🥈'
                                                      : rank == 3
                                                          ? '🥉'
                                                          : '#$rank',
                                              style: TextStyle(
                                                fontSize: isTop3 ? 14 : 11,
                                                fontWeight: FontWeight.bold,
                                                color: isTop3
                                                    ? badgeColor
                                                    : theme.textPrimary
                                                        .withValues(alpha: 0.7),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Name & Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                entry.playerName,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                  color: theme.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Streak: ${entry.streak} • ${_formatDate(entry.date)}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: theme.textPrimary
                                                      .withValues(alpha: 0.45),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Level Tag
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(
                                                color: badgeColor.withValues(alpha: 0.35)),
                                          ),
                                          child: Text(
                                            'LVL ${entry.level}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: badgeColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
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
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildIconToggle({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required GameTheme theme,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () {
          onTap();
          HapticFeedback.selectionClick();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive
                ? theme.accentColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? theme.accentColor.withValues(alpha: 0.4)
                  : theme.textPrimary.withValues(alpha: 0.12),
            ),
          ),
          child: Icon(
            icon,
            color: isActive
                ? theme.accentColor
                : theme.textPrimary.withValues(alpha: 0.55),
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hint tile pulse animation widget
// ---------------------------------------------------------------------------
class _HintTilePulse extends StatefulWidget {
  final Widget child;
  final bool isHinted;
  final Color pulseColor;

  const _HintTilePulse({
    required this.child,
    required this.isHinted,
    required this.pulseColor,
  });

  @override
  State<_HintTilePulse> createState() => _HintTilePulseState();
}

class _HintTilePulseState extends State<_HintTilePulse>
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
  void didUpdateWidget(covariant _HintTilePulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHinted && !oldWidget.isHinted) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isHinted && oldWidget.isHinted) {
      _ctrl.stop();
      _ctrl.reset();
    }
  }

  void _startPulse() {
    _ctrl.forward(from: 0.0).then((_) {
      if (mounted) {
        _ctrl.reverse();
      }
    });
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
    path.moveTo(startX, 35);
    path.cubicTo(startX, 52, endX, 53, endX, 70);

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
// Orbital pulsing hero logo widget
// ---------------------------------------------------------------------------
class _OrbitalHeroLogo extends StatefulWidget {
  final Color accentColor;
  final VoidCallback? onTap;
  const _OrbitalHeroLogo({required this.accentColor, this.onTap});

  @override
  State<_OrbitalHeroLogo> createState() => _OrbitalHeroLogoState();
}

class _OrbitalHeroLogoState extends State<_OrbitalHeroLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _rotationAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 3200),
      vsync: this,
    )..repeat();
    _rotationAnim = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(_ctrl);
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
      builder: (context, _) {
        final scale = _ctrl.value <= 0.5
            ? (0.88 + (_ctrl.value * 2 * 0.22))
            : (1.10 - ((_ctrl.value - 0.5) * 2 * 0.22));

        return GestureDetector(
          onTap: () {
            if (widget.onTap != null) {
              HapticFeedback.selectionClick();
              widget.onTap!();
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 105,
                height: 105,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Ambient Glow Aura
                    Container(
                      width: 95 * scale,
                      height: 95 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accentColor.withValues(alpha: 0.15),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accentColor.withValues(alpha: 0.35 * scale),
                            blurRadius: 32 * scale,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    // Outer Orbit Ring
                    Transform.rotate(
                      angle: _rotationAnim.value,
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.accentColor.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.accentColor,
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor,
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Inner Core Container
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            widget.accentColor.withValues(alpha: 0.65),
                            widget.accentColor.withValues(alpha: 0.12),
                          ],
                        ),
                        border: Border.all(
                          color: widget.accentColor.withValues(alpha: 0.75),
                          width: 1.8,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.bolt_rounded,
                          color: widget.accentColor,
                          size: 34,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 11, color: widget.accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'TAP FOR LEVEL MAP',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                        color: widget.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing glow animation widget (for splash logo)
// ---------------------------------------------------------------------------
class _PulsingGlow extends StatefulWidget {
  final Widget child;
  final Color color;
  const _PulsingGlow({required this.child, required this.color});

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
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
      animation: _anim,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * _anim.value),
                blurRadius: 30 * _anim.value,
                spreadRadius: 6 * _anim.value,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Animated Gradient Background
// ---------------------------------------------------------------------------
class AnimatedGradientBackground extends StatefulWidget {
  final List<Color> colors;
  final Widget child;

  const AnimatedGradientBackground({
    super.key,
    required this.colors,
    required this.child,
  });

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 22),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final val = _animation.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1.0 + val * 0.4, -1.0 + (1 - val) * 0.4),
              end: Alignment(1.0 - val * 0.4, 1.0 - (1 - val) * 0.4),
              colors: widget.colors,
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Shake Widget
// ---------------------------------------------------------------------------
class ShakeWidget extends StatefulWidget {
  final Widget child;
  final bool shake;

  const ShakeWidget({super.key, required this.child, required this.shake});

  @override
  State<ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shake && !oldWidget.shake) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final val = _controller.value;
        final dx = (val > 0.0 && val < 1.0)
            ? 11.0 * math.sin(val * 4 * math.pi)
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: widget.child);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Particle System
// ---------------------------------------------------------------------------
class SparkParticle {
  double x, y, vx, vy, size, alpha, lifetime;
  final Color color;
  final double maxLifetime;

  SparkParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.maxLifetime,
  })  : alpha = 1.0,
        lifetime = 0.0;

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 90.0 * dt;
    lifetime += dt;
    alpha = (1.0 - (lifetime / maxLifetime)).clamp(0.0, 1.0);
  }

  bool get isDead => lifetime >= maxLifetime;
}

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
      canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ParticlePainter oldDelegate) => true;
}

// ---------------------------------------------------------------------------
// Leaderboard Data Model
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Stage 1: Full-Screen Company Logo Splash Screen
// ---------------------------------------------------------------------------
class _CompanySplashScreen extends StatefulWidget {
  final GameTheme theme;
  final VoidCallback onComplete;

  const _CompanySplashScreen({
    required this.theme,
    required this.onComplete,
  });

  @override
  State<_CompanySplashScreen> createState() => _CompanySplashScreenState();
}

class _CompanySplashScreenState extends State<_CompanySplashScreen>
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
                // Ambient center radial glow
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
                      // Company Logo Shield Emblem
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

                      // Company Name
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

                      // Subtitle
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

                      // Footer Presenter Tag
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

// ---------------------------------------------------------------------------
// Stage 2: Full-Screen Game Launch Splash Screen with Progress Loading Bar
// ---------------------------------------------------------------------------
class _FullScreenSplashScreen extends StatefulWidget {
  final GameTheme theme;
  final VoidCallback onLoadingComplete;

  const _FullScreenSplashScreen({
    required this.theme,
    required this.onLoadingComplete,
  });

  @override
  State<_FullScreenSplashScreen> createState() => _FullScreenSplashScreenState();
}

class _FullScreenSplashScreenState extends State<_FullScreenSplashScreen>
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
              // Ambient background spark glow
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
                      // Studio Branding Tag Badge
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

                      // Dedicated Splash Cosmic Spark Emblem
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
                                  // Rotating energy ring
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

                      // Gradient Shader Futuristic Orbitron Title Text
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

                      // Subtitle Tagline Badge
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

                      // Animated Progress Loading Bar
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

