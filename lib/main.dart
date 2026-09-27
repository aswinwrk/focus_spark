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
import 'game/game_state_enums.dart';
import 'models/game_theme.dart';
import 'models/particle.dart';
import 'models/leaderboard_entry.dart';
import 'utils/particle_manager.dart';
import 'ui/components/animated_gradient_bg.dart';
import 'ui/components/shake_widget.dart';
import 'ui/components/hint_tile_pulse.dart';
import 'ui/screens/company_splash_screen.dart';
import 'ui/screens/fullscreen_splash_screen.dart';
import 'ui/modals/leaderboard_modal.dart';
import 'ui/modals/level_roadmap_modal.dart';
import 'ui/modals/tutorial_modal.dart';
import 'ui/modals/edit_player_name_modal.dart';
import 'services/storage_service.dart';
import 'game/game_controller.dart';

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
      title: 'Brain Reboot',
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
// Main Screen
// ---------------------------------------------------------------------------
class FocusSparkScreen extends StatefulWidget {
  const FocusSparkScreen({super.key});

  @override
  State<FocusSparkScreen> createState() => _FocusSparkScreenState();
}

class _FocusSparkScreenState extends State<FocusSparkScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Theme Presets ───────────────────────────────────────────────────────
  final List<GameTheme> _themes = gameThemes;

  int _selectedThemeIndex = 0;

  // ── Pure Consonant C-Major Pentatonic Scale Frequencies (C4–G5) ────────────
  static const List<double> _frequencies = [
    261.63, // C4 (Tile 0 - Top Left)
    293.66, // D4 (Tile 1 - Top Center)
    329.63, // E4 (Tile 2 - Top Right)
    392.00, // G4 (Tile 3 - Mid Left)
    440.00, // A4 (Tile 4 - Center Tile)
    523.25, // C5 (Tile 5 - Mid Right)
    587.33, // D5 (Tile 6 - Bottom Left)
    659.25, // E5 (Tile 7 - Bottom Center)
    783.99, // G5 (Tile 8 - Bottom Right)
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

  bool _isMusicMuted = false;
  bool _isSfxMuted = false;
  bool _isHapticsMuted = false;
  String _playerName = 'You';

  // ── Tile Interaction State ───────────────────────────────────────────────
  int? _activePlaybackTile;
  int? _correctErrorTile;
  int? _activeTapTile;
  int? _rippleTileIndex;
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
  late AnimationController _praiseController;
  late Animation<double> _praiseScaleAnimation;
  late Animation<double> _praiseOpacityAnimation;
  String? _activePraiseText;
  Color _activePraiseColor = const Color(0xFFA78BFA);

  int _splashStage = 0;
  StorageService? _storageService;
  final math.Random _random = math.Random();
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  String _activeAdType = 'REWARDED VIDEO TEST AD';
  final ValueNotifier<double> _timerNotifier = ValueNotifier<double>(1.0);

  late AnimationController _tutorialHandController;
  bool _isVisualTutorialActive = false;
  bool _showReverseAnnouncementOverlay = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _particleManager = ParticleManager(this);

    _praiseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _praiseScaleAnimation = CurvedAnimation(
      parent: _praiseController,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    );

    _praiseOpacityAnimation = CurvedAnimation(
      parent: _praiseController,
      curve: const Interval(0.65, 1.0, curve: Curves.easeOut),
    );

    _tutorialHandController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _loadSettings();
    _initAdMobBanner();

    AdService.instance.onAdOpened = () {
      if (!mounted) return;
      AudioService.instance.stopAmbientMusic();
      _cancelInputTimer();
    };

    AdService.instance.onAdClosed = () {
      if (!mounted) return;
      if (!_isMusicMuted) {
        AudioService.instance.startAmbientMusic();
      }
      if (_gameState == GameState.playerInput) {
        _startInputTimer();
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
    WidgetsBinding.instance.removeObserver(this);
    _praiseController.dispose();
    _tutorialHandController.dispose();
    _timerNotifier.dispose();
    _bannerAd?.dispose();
    _particleManager.disposeTicker();
    _particleManager.dispose();
    _cancelInputTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      AudioService.instance.stopAmbientMusic();
      _cancelInputTimer();
      if (_gameState == GameState.playerInput || _gameState == GameState.playback) {
        setState(() {
          _gameState = GameState.paused;
          _activePlaybackTile = null;
        });
        _saveGameProgress();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_isMusicMuted && _splashStage == 2) {
        AudioService.instance.startAmbientMusic();
      }
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────────
  Future<void> _loadSettings() async {
    _storageService = await StorageService.init();
    final bool hasSavedGame = _storageService!.hasActiveGame();
    final int savedLevel = _storageService!.getCurrentLevel();
    final int savedStreak = _storageService!.getCurrentStreak();
    final String seqStr = _storageService!.getCurrentSequenceStr();

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
      _highScore = _storageService!.getHighScore();
      _isMusicMuted = _storageService!.isMusicMuted();
      _isSfxMuted = _storageService!.isSfxMuted();
      _isHapticsMuted = _storageService!.isHapticsMuted();
      _playerName = _storageService!.getPlayerName();
      _selectedThemeIndex = _storageService!.getThemeIndex();
      _hasSeenTutorial = _storageService!.hasSeenTutorial();
      _showTutorialCard = !_hasSeenTutorial;
      if (!_hasSeenTutorial) {
        _isVisualTutorialActive = true;
      }

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

      final completedSavedLevel = _level - 1;
      if (completedSavedLevel > _highScore) {
        _highScore = completedSavedLevel;
        _storageService!.setHighScore(_highScore);
      }

      if (!_isMusicMuted) {
        AudioService.instance.startAmbientMusic();
      } else {
        AudioService.instance.stopAmbientMusic();
      }

      // Load Hall of Fame Leaderboard
      final String leaderboardStr = _storageService!.getHallOfFameJson();
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
          LeaderboardEntry(playerName: 'Brain Rebooter', level: 7, streak: 7, date: now.subtract(const Duration(days: 5))),
          LeaderboardEntry(playerName: 'Memory Runner', level: 5, streak: 5, date: now.subtract(const Duration(days: 7))),
          LeaderboardEntry(playerName: 'Calm Thinker', level: 3, streak: 3, date: now.subtract(const Duration(days: 9))),
        ];
      }
      _leaderboard = _deduplicateLeaderboardEntries(loadedLeaderboard);
    });
  }

  Future<void> _saveGameProgress() async {
    if (!mounted) return;
    if (_storageService != null) {
      await _storageService!.saveActiveGame(
        level: _level,
        streak: _currentStreak,
        sequence: _sequence,
      );
    }
    if (!_hasSavedSession) {
      setState(() {
        _hasSavedSession = true;
      });
    }
  }

  Future<void> _updateHighScore(int score) async {
    setState(() => _highScore = score);
    if (_storageService != null) {
      await _storageService!.setHighScore(score);
    }
  }

  List<LeaderboardEntry> _deduplicateLeaderboardEntries(List<LeaderboardEntry> entries) {
    final Map<String, LeaderboardEntry> bestEntries = {};
    for (final entry in entries) {
      final existing = bestEntries[entry.playerName];
      if (existing == null || entry.level > existing.level) {
        bestEntries[entry.playerName] = entry;
      }
    }
    final sorted = bestEntries.values.toList()
      ..sort((a, b) => b.level.compareTo(a.level));
    return sorted;
  }

  Future<void> _recordLeaderboardScore(int level, int streak) async {
    final existingIndex = _leaderboard.indexWhere((e) => e.playerName == _playerName);
    if (existingIndex != -1) {
      if (level > _leaderboard[existingIndex].level) {
        _leaderboard[existingIndex] = LeaderboardEntry(
          playerName: _playerName,
          level: level,
          streak: streak,
          date: DateTime.now(),
        );
      }
    } else {
      _leaderboard.add(LeaderboardEntry(
        playerName: _playerName,
        level: level,
        streak: streak,
        date: DateTime.now(),
      ));
    }

    _leaderboard = _deduplicateLeaderboardEntries(_leaderboard);

    if (_leaderboard.length > 10) {
      _leaderboard = _leaderboard.sublist(0, 10);
    }

    final String jsonStr = jsonEncode(_leaderboard.map((e) => e.toJson()).toList());
    await _storageService?.setHallOfFameJson(jsonStr);
    if (mounted) setState(() {});
  }

  // ── Haptic Engine Helper ──────────────────────────────────────────────────
  void _triggerHaptic(HapticType type) {
    if (_isHapticsMuted) return;
    switch (type) {
      case HapticType.light:
        HapticFeedback.lightImpact();
        AudioService.instance.vibrate(durationMs: 55);
        break;
      case HapticType.medium:
        HapticFeedback.mediumImpact();
        AudioService.instance.vibrate(durationMs: 75);
        break;
      case HapticType.heavy:
        HapticFeedback.heavyImpact();
        AudioService.instance.vibrate(durationMs: 110);
        break;
      case HapticType.victory:
        HapticFeedback.heavyImpact();
        AudioService.instance.vibrate(durationMs: 120);
        Future.delayed(const Duration(milliseconds: 140), () {
          HapticFeedback.lightImpact();
          AudioService.instance.vibrate(durationMs: 60);
        });
        break;
      case HapticType.error:
        HapticFeedback.vibrate();
        AudioService.instance.vibrate(durationMs: 160);
        break;
      case HapticType.heartbeat:
        HapticFeedback.selectionClick();
        AudioService.instance.vibrate(durationMs: 40);
        break;
      case HapticType.selection:
        HapticFeedback.selectionClick();
        AudioService.instance.vibrate(durationMs: 40);
        break;
    }
  }

  void _playWrongMoveTune() {
    if (_isSfxMuted) return;
    AudioService.instance.playTone(155.56, 0.15);
    Future.delayed(const Duration(milliseconds: 110), () {
      AudioService.instance.playTone(130.81, 0.25);
    });
  }

  void _playReverseLevelWarningTone() {
    if (_isSfxMuted) return;
    AudioService.instance.playTone(130.81, 0.12);
    Future.delayed(const Duration(milliseconds: 100), () {
      AudioService.instance.playTone(261.63, 0.14);
      Future.delayed(const Duration(milliseconds: 120), () {
        AudioService.instance.playTone(523.25, 0.22);
      });
    });
  }

  // ── Praise Text Engine ───────────────────────────────────────────────────
  void _triggerPraiseText(String text, Color glowColor) {
    setState(() {
      _activePraiseText = text;
      _activePraiseColor = glowColor;
    });
    _praiseController.forward(from: 0.0);
  }

  bool _isReverseLevel(int level) => level >= 5 && level % 5 == 0;

  String _getPraiseForLevel(int completedLevel) {
    if (_isReverseLevel(completedLevel)) {
      final List<String> reversePraises = [
        'REVERSE MASTERMIND! 🔄⚡',
        'MIND FLIPPED! 🧠💥',
        'SYNAPSE INVERSION! ⚡🔄',
        'REVERSE SPARK! 💥🔄',
      ];
      return reversePraises[(completedLevel ~/ 5) % reversePraises.length];
    }
    final List<String> tier1 = ['NICE FOCUS! 🎯', 'SPARK! ⚡', 'SHARP! ⚔️', 'SMART MOVE! 💡'];
    final List<String> tier2 = ['SYNAPSE SURGE! ⚡', 'BRILLIANT! 🌟', 'HYPER FOCUS! 👁️', 'LASER MATRIX! 🔮'];
    final List<String> tier3 = ['SUPERCHARGED! 🔋', 'BRAIN POWER! 🧠', 'UNSTOPPABLE! 🚀', 'LIGHTNING MIND! ⚡'];
    final List<String> tier4 = ['MASTERMIND! 👑', 'MIND BENDER! 🔮', 'CYBER OVERLORD! 🌐', 'ULTIMATE SPARK! 💥'];

    if (completedLevel <= 4) {
      return tier1[_random.nextInt(tier1.length)];
    } else if (completedLevel <= 9) {
      return tier2[_random.nextInt(tier2.length)];
    } else if (completedLevel <= 14) {
      return tier3[_random.nextInt(tier3.length)];
    } else {
      return tier4[_random.nextInt(tier4.length)];
    }
  }

  String _getFailurePraiseText() {
    return 'TRY AGAIN! 🔄';
  }

  Future<void> _toggleMusic() async {
    HapticFeedback.selectionClick();
    setState(() {
      _isMusicMuted = !_isMusicMuted;
    });
    await _storageService?.setMusicMuted(_isMusicMuted);
    if (_isMusicMuted) {
      AudioService.instance.stopAmbientMusic();
    } else {
      AudioService.instance.startAmbientMusic();
    }
  }

  void _toggleSfx() async {
    _triggerHaptic(HapticType.light);
    setState(() {
      _isSfxMuted = !_isSfxMuted;
    });
    await _storageService?.setSfxMuted(_isSfxMuted);
  }

  void _toggleHaptics() async {
    if (_isHapticsMuted) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _isHapticsMuted = !_isHapticsMuted;
    });
    await _storageService?.setHapticsMuted(_isHapticsMuted);
  }

  Future<void> _selectTheme(int index) async {
    setState(() => _selectedThemeIndex = index);
    await _storageService?.setThemeIndex(index);
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
    _particleManager.spawnConfettiBurst(_gridWidth / 2, _gridHeight / 2, 45);
  }

  Future<void> _triggerGridRippleWave() async {
    for (int i = 0; i < 9; i++) {
      if (!mounted) return;
      setState(() => _rippleTileIndex = i);
      if (!_isSfxMuted) {
        AudioService.instance.playTone(_frequencies[i], 0.08);
      }
      await Future.delayed(const Duration(milliseconds: 40));
    }
    if (mounted) {
      setState(() => _rippleTileIndex = null);
    }
  }

  void _startVisualTutorial() {
    if (!mounted) return;
    setState(() {
      _isVisualTutorialActive = true;
      _hasSeenTutorial = true;
      _showTutorialCard = false;
    });
    _storageService?.setSeenTutorial(true);
    _startSession();
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
          _storageService?.setSeenTutorial(true);
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

    launchGame();
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
        _storageService?.setSeenTutorial(true);
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

    final bool isTutorialMode = _isVisualTutorialActive && _level <= 2;

    final bool isReverseMode = _isReverseLevel(_level);
    if (isReverseMode) {
      _playReverseLevelWarningTone();
      _triggerHaptic(HapticType.heavy);
      if (mounted) {
        setState(() => _showReverseAnnouncementOverlay = true);
      }
    }

    // Adaptive speed: Max(380ms, 650ms - level*25ms)
    final int speedMs = isTutorialMode ? 1600 : (650 - (_level * 25)).clamp(380, 650);
    final int activeMs = isTutorialMode ? 1000 : (speedMs * 0.75).round();
    final int gapMs = isTutorialMode ? 600 : (speedMs - activeMs);

    // Pre-playback pause (2.4s for tutorial, 2.2s for Reverse Mode announcement) so user can comfortably read text
    final int prePauseMs = isTutorialMode ? 2400 : (isReverseMode ? 2200 : 300);
    await Future.delayed(Duration(milliseconds: prePauseMs));
    if (_showReverseAnnouncementOverlay && mounted) {
      setState(() => _showReverseAnnouncementOverlay = false);
    }
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
      if (isTutorialMode) {
        // Generous 2.2s transition pause so user can comfortably read Step 2 text before tapping
        await Future.delayed(const Duration(milliseconds: 2200));
        if (_gameState != GameState.playback || _playbackSessionId != currentSession) return;
      }
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
    if (_isVisualTutorialActive && _level <= 2) {
      _inputTimerPercentage = 1.0;
      _timerNotifier.value = 1.0;
      return;
    }
    _totalInputTime = 6.0 + (_sequence.length * 1.2);
    _elapsedInputTime = 0.0;
    _inputTimerPercentage = 1.0;
    _timerNotifier.value = 1.0;

    _inputTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (_gameState != GameState.playerInput) {
        _cancelInputTimer();
        return;
      }
      _elapsedInputTime += 0.05;
      final pct = (1.0 - (_elapsedInputTime / _totalInputTime)).clamp(0.0, 1.0);
      _inputTimerPercentage = pct;
      _timerNotifier.value = pct;

      if (_elapsedInputTime >= _totalInputTime) {
        _cancelInputTimer();
        _handleTimeout();
      } else {
        // Heartbeat haptic pulse during critical time (< 20%)
        if (pct <= 0.20 && (timer.tick % 10 == 0)) {
          _triggerHaptic(HapticType.heartbeat);
        }
      }
    });
  }

  void _cancelInputTimer() {
    _inputTimer?.cancel();
    _inputTimer = null;
  }

  void _handleTimeout() {
    if (_gameState != GameState.playerInput) return;
    _triggerHaptic(HapticType.error);
    setState(() {
      _gameState = GameState.errorTransition;
      _currentStreak = 0;
      _correctErrorTile = _sequence[_playerInput.length];
      _hintedTile = null;
    });
    _playWrongMoveTune();

    final failMsg = _getFailurePraiseText();
    _triggerPraiseText(failMsg, const Color(0xFFEF4444));

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

    final bool isReverse = _isReverseLevel(_level);
    final nextTile = isReverse
        ? _sequence[_sequence.length - 1 - _playerInput.length]
        : _sequence[_playerInput.length];
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
        if (mounted) {
          if (_gameState != GameState.playerInput) {
            setState(() {
              _gameState = GameState.playerInput;
            });
          }
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
      if (_gameState != GameState.playerInput) {
        _gameState = GameState.playerInput;
      }
    });

    _startInputTimer();
    _triggerHint();
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

    _triggerHaptic(HapticType.light);

    if (_hintedTile != null) {
      setState(() {
        _hintedTile = null;
      });
    }

    final bool isReverse = _isReverseLevel(_level);
    final expectedIndex = isReverse
        ? _sequence[_sequence.length - 1 - _playerInput.length]
        : _sequence[_playerInput.length];
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
            _storageService?.setHighScore(_highScore);
          }

          if (_isVisualTutorialActive && _level > 2) {
            _isVisualTutorialActive = false;
            _hasSeenTutorial = true;
            _storageService?.setSeenTutorial(true);
          }
        });
        _recordLeaderboardScore(completedLevel, _currentStreak);

        _triggerHaptic(HapticType.victory);
        _spawnSuccessSparks(theme.accentColor);
        _triggerGridRippleWave();

        // Trigger Focus Praise Text Popup!
        final praiseMsg = _getPraiseForLevel(completedLevel);
        _triggerPraiseText(praiseMsg, theme.accentColor);

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
      _triggerHaptic(HapticType.error);
      _playWrongMoveTune();

      final failMsg = _getFailurePraiseText();
      _triggerPraiseText(failMsg, const Color(0xFFEF4444));

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
    final bool isReverse = _isReverseLevel(_level);
    switch (_gameState) {
      case GameState.startScreen:
        return 'Clear your mind. Tap Start to begin.';
      case GameState.playback:
        return isReverse
            ? '🔄 Watch pattern... Tap in REVERSE order!'
            : 'Watch the spark pattern carefully...';
      case GameState.playerInput:
        return isReverse
            ? '🔄 Tap the pattern in REVERSE order!'
            : 'Now replicate the pattern from memory.';
      case GameState.paused:
        return 'Breathe in, breathe out. Session paused.';
      case GameState.successTransition:
        return isReverse ? '✦ Reverse Inversion Mastered! Advancing...' : '✦ Excellent focus! Advancing...';
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
    final bool isRippleFlash = _rippleTileIndex == index;
    final bool isErrorFlash =
        _gameState == GameState.errorTransition && _correctErrorTile == index;
    final bool isSuccess = _gameState == GameState.successTransition;
    final bool isFlashing = isPlaybackFlash || isTapFlash || isHinted || isRippleFlash;
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

    final bool isReverse = _isReverseLevel(_level);
    final Color activeGlowColor = isReverse ? const Color(0xFFC084FC) : theme.tileActiveGlow;

    Color tileColor = theme.tileDefault;
    if (isSuccess) {
      tileColor = theme.successColor.withValues(alpha: 0.18);
    } else if (isFlashing) {
      tileColor = activeGlowColor.withValues(alpha: 0.85);
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
        color: activeGlowColor.withValues(alpha: 0.85),
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

    // Spotlight Focus Dimming during Level 1 & 2 Visual Tutorial
    final bool isTutorialActive = _isVisualTutorialActive && _level <= 2;
    int? activeTutorialTargetTile;
    if (isTutorialActive) {
      if (_gameState == GameState.playback) {
        activeTutorialTargetTile = _activePlaybackTile;
      } else if (_gameState == GameState.playerInput && _playerInput.length < _sequence.length) {
        activeTutorialTargetTile = _sequence[_playerInput.length];
      }
    }

    final double tileOpacity = (isTutorialActive && activeTutorialTargetTile != null && index != activeTutorialTargetTile)
        ? 0.28
        : 1.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: tileOpacity,
      child: HintTilePulse(
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
    ),
  );
}

  // ── Input Timer Bar ──────────────────────────────────────────────────────
  Widget _buildInputTimerBar(GameTheme theme) {
    if (_isVisualTutorialActive && _level <= 2) {
      return const SizedBox(height: 0, width: double.infinity);
    }
    return ValueListenableBuilder<double>(
      valueListenable: _timerNotifier,
      builder: (context, pctVal, _) {
        final remainingSecs = math.max(0.0, _totalInputTime - _elapsedInputTime);
        final pct = pctVal.clamp(0.0, 1.0);

    final Color barColor;
    final Color glowColor;
    final String statusText;
    final IconData statusIcon;

    if (pct > 0.40) {
      barColor = theme.accentColor;
      glowColor = theme.tileActiveGlow;
      statusText = 'TIME REMAINING';
      statusIcon = Icons.timer_outlined;
    } else if (pct > 0.20) {
      barColor = const Color(0xFFF59E0B);
      glowColor = const Color(0xFFFBBF24);
      statusText = 'HURRY UP!';
      statusIcon = Icons.bolt_rounded;
    } else {
      barColor = const Color(0xFFEF4444);
      glowColor = const Color(0xFFF87171);
      statusText = 'CRITICAL TIME!';
      statusIcon = Icons.warning_amber_rounded;
    }

    return AnimatedOpacity(
      opacity: _gameState == GameState.playerInput ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14.0),
        child: Column(
          children: [
            // Header Row: Status Tag & Digital Seconds Counter
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: barColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: GoogleFonts.orbitron(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: barColor,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: barColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${remainingSecs.toStringAsFixed(1)}s',
                    style: GoogleFonts.orbitron(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: barColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Neon Capsule Energy Track
            LayoutBuilder(
              builder: (context, constraints) {
                final trackWidth = constraints.maxWidth;
                final barWidth = trackWidth * pct;

                return Container(
                  height: 10,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: barColor.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: barColor.withValues(alpha: 0.15),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Active Progress Fill
                      Container(
                        width: barWidth,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: LinearGradient(
                            colors: [
                              barColor.withValues(alpha: 0.6),
                              barColor,
                              glowColor,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: barColor.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),

                      // Leading-Edge Energy Spark Orb
                      if (pct > 0.02)
                        Positioned(
                          left: math.max(0, barWidth - 8),
                          top: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: barColor,
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  },
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

  // ── Praise Text Overlay ──────────────────────────────────────────────────
  Widget _buildPraiseTextOverlay(GameTheme theme) {
    if (_activePraiseText == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _praiseController,
      builder: (context, child) {
        if (_praiseController.isDismissed || _praiseController.value >= 0.98) {
          return const SizedBox.shrink();
        }

        final opacity = (1.0 - _praiseOpacityAnimation.value).clamp(0.0, 1.0);
        final scale = _praiseScaleAnimation.value.clamp(0.0, 1.4);
        final translateY = -40.0 * _praiseController.value;

        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: Offset(0, translateY),
                child: Transform.scale(
                  scale: scale,
                  child: Opacity(
                    opacity: opacity,
                    child: Text(
                      _activePraiseText!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.0,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: _activePraiseColor,
                            blurRadius: 28,
                          ),
                          Shadow(
                            color: _activePraiseColor.withValues(alpha: 0.8),
                            blurRadius: 16,
                          ),
                          const Shadow(
                            color: Colors.black,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Interactive Animated Visual Tutorial Overlay ─────────────────────────
  Widget _buildInteractiveTutorialOverlay(GameTheme theme) {
    if (!_isVisualTutorialActive || _level > 2 || _gameState == GameState.startScreen || _gameState == GameState.paused) {
      return const SizedBox.shrink();
    }

    int? targetTileIndex;
    String stepTitle = '';
    String stepInstruction = '';
    Color stepGlowColor = theme.accentColor;

    if (_gameState == GameState.playback) {
      targetTileIndex = _activePlaybackTile;
      stepTitle = 'STEP 1: WATCH THE SPARK 👁️';
      stepInstruction = targetTileIndex != null
          ? 'Watch the tiles flash in sequence!'
          : 'Get ready to observe the sequence!';
      stepGlowColor = theme.tileActiveGlow;
    } else if (_gameState == GameState.playerInput) {
      if (_playerInput.length < _sequence.length) {
        targetTileIndex = _sequence[_playerInput.length];
        stepTitle = 'STEP 2: REPLICATE PATTERN 🎯';
        stepInstruction = 'Now tap the exact same tile!';
        stepGlowColor = const Color(0xFFFFD700);
      }
    }

    final double spacing = 12.0;
    final double tileSize = (_gridWidth - (spacing * 2)) / 3.0;

    double? targetX;
    double? targetY;
    if (targetTileIndex != null) {
      final int row = targetTileIndex ~/ 3;
      final int col = targetTileIndex % 3;
      targetX = (col * (tileSize + spacing)) + (tileSize / 2.0);
      targetY = (row * (tileSize + spacing)) + (tileSize / 2.0);
    }

    final bool isTopRowTarget = targetTileIndex != null && targetTileIndex < 3;

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _tutorialHandController,
          builder: (context, child) {
            final bounceOffset = _tutorialHandController.value * 12.0;
            return Stack(
              children: [
                // Glowing Target Pulsing Halo Ring & Hand Pointer Icon (when target tile is active)
                if (targetX != null && targetY != null) ...[
                  Positioned(
                    left: targetX - 32,
                    top: targetY - 32,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: stepGlowColor, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: stepGlowColor.withValues(alpha: 0.6),
                            blurRadius: 18 + (_tutorialHandController.value * 10),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: targetX - 20,
                    top: targetY + 10 + bounceOffset,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          size: 40,
                          color: stepGlowColor,
                          shadows: [
                            Shadow(
                              color: stepGlowColor,
                              blurRadius: 14,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // Pure Floating 3D Neon Tutorial Text (No dialogue box)
                Positioned(
                  top: isTopRowTarget ? null : 8,
                  bottom: isTopRowTarget ? 8 : null,
                  left: 12,
                  right: 12,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stepTitle,
                        style: GoogleFonts.orbitron(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          color: stepGlowColor,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.9),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                            Shadow(
                              color: stepGlowColor.withValues(alpha: 0.8),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        stepInstruction,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.9),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Pause Overlay ────────────────────────────────────────────────────────
  Widget _buildPauseOverlay(GameTheme theme) {
    if (_showReverseAnnouncementOverlay && _gameState == GameState.playback) {
      return _buildReverseModeAnnouncementOverlay(theme);
    }

    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _gameState == GameState.paused ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
          ignoring: _gameState != GameState.paused,
          child: GestureDetector(
            onTap: _togglePause,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.accentColor.withValues(alpha: 0.40),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.accentColor.withValues(alpha: 0.20),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glowing Pulsing Pause Icon Badge
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.accentColor.withValues(alpha: 0.15),
                              border: Border.all(color: theme.accentColor, width: 1.8),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.accentColor.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.pause_rounded,
                              size: 30,
                              color: theme.accentColor,
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Header with Orbitron & Gradient Mask
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                Colors.white,
                                theme.accentColor,
                              ],
                            ).createShader(bounds),
                            child: Text(
                              'SESSION PAUSED',
                              style: GoogleFonts.orbitron(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2.0,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Take a deep breath • Tap to resume',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: theme.textPrimary.withValues(alpha: 0.65),
                            ),
                            textAlign: TextAlign.center,
                          ),

                          const SizedBox(height: 12),

                          // Session Stats HUD Snapshot
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.panelBorder.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildHUDItem('LEVEL', 'LVL $_level', theme,
                                    valueColor: theme.accentColor, fontSize: 11.0),
                                Container(height: 18, width: 1, color: theme.panelBorder.withValues(alpha: 0.3)),
                                _buildHUDItem('STREAK', '$_currentStreak 🔥', theme, fontSize: 11.0),
                                Container(height: 18, width: 1, color: theme.panelBorder.withValues(alpha: 0.3)),
                                _buildHUDItem('BEST', 'LVL $_highScore', theme, fontSize: 11.0),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Primary Action Button: RESUME SESSION
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _togglePause,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.accentColor,
                                foregroundColor: Colors.black87,
                                elevation: 6,
                                shadowColor: theme.accentColor.withValues(alpha: 0.4),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.play_arrow_rounded, size: 18),
                              label: Text(
                                'RESUME SESSION',
                                style: GoogleFonts.orbitron(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 10),

                          // Quick Audio Settings Bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildPauseQuickToggle(
                                icon: _isMusicMuted ? Icons.music_off_rounded : Icons.music_note_rounded,
                                label: 'MUSIC',
                                isActive: !_isMusicMuted,
                                onTap: _toggleMusic,
                                theme: theme,
                              ),
                              _buildPauseQuickToggle(
                                icon: _isSfxMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                label: 'SFX',
                                isActive: !_isSfxMuted,
                                onTap: _toggleSfx,
                                theme: theme,
                              ),
                              _buildPauseQuickToggle(
                                icon: _isHapticsMuted ? Icons.vibration_rounded : Icons.vibration_rounded,
                                label: 'HAPTICS',
                                isActive: !_isHapticsMuted,
                                onTap: _toggleHaptics,
                                theme: theme,
                              ),
                            ],
                          ),
                        ],
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

  Widget _buildPauseQuickToggle({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    required GameTheme theme,
  }) {
    final color = isActive ? theme.accentColor : theme.textPrimary.withValues(alpha: 0.35);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? theme.accentColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? theme.accentColor.withValues(alpha: 0.4) : theme.panelBorder.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReverseRoundBanner(GameTheme theme) {
    if (!_isReverseLevel(_level) || _gameState == GameState.startScreen || _gameState == GameState.paused) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC084FC).withValues(alpha: 0.7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.45),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔄', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reverse Round!',
                style: GoogleFonts.orbitron(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'Tap the pattern backwards — last tile first!',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.90),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReverseModeAnnouncementOverlay(GameTheme theme) {
    if (!_showReverseAnnouncementOverlay || _gameState != GameState.playback) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 250),
          opacity: _showReverseAnnouncementOverlay ? 1.0 : 0.0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.50),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFC084FC), width: 2.0),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFC084FC).withValues(alpha: 0.80),
                        blurRadius: 32,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.20),
                        ),
                        child: const Text('🔄', style: TextStyle(fontSize: 36)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'REVERSE MODE!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.orbitron(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.5,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black45, blurRadius: 12),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the pattern in reverse order — last tile first!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
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
    final isStart = _gameState == GameState.startScreen;
    final isGameActive = !isStart;
    final theme = (isGameActive && _isReverseLevel(_level))
        ? reverseTheme
        : _themes[_selectedThemeIndex];
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth < 360 ? 10.0 : 18.0;

    if (_splashStage == 0) {
      return CompanySplashScreen(
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
      return FullScreenSplashScreen(
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

                        // 2c. Haptic Feedback Toggle Button
                        _buildIconToggle(
                          icon: _isHapticsMuted
                              ? Icons.vibration_outlined
                              : Icons.vibration_rounded,
                          isActive: !_isHapticsMuted,
                          onTap: _toggleHaptics,
                          theme: theme,
                          tooltip: _isHapticsMuted ? 'Enable Haptics' : 'Mute Haptics',
                        ),
                        const SizedBox(width: 4),

                        // 3. How to Play Icon (Home Screen Only)
                        if (isStart) ...[
                          _buildIconToggle(
                            icon: Icons.help_outline_rounded,
                            isActive: false,
                            onTap: () => _showTutorialModal(context, theme),
                            theme: theme,
                            tooltip: 'How to Play',
                          ),
                          const SizedBox(width: 4),
                        ],

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
                                crossFadeState: isStart
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

                              // ── Reverse Challenge Round Banner ─────────────
                              if (!isStart) _buildReverseRoundBanner(theme),

                              // ── Input Timer Bar ──────────────────────────
                              _buildInputTimerBar(theme),

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
                                      // Praise Text Overlay
                                      _buildPraiseTextOverlay(theme),
                                      // Pause overlay
                                     _buildPauseOverlay(theme),
                                     // Direct Rewarded Ad overlay
                                     _buildDirectAdOverlay(theme),
                                      // Interactive Visual Tutorial Overlay
                                      _buildInteractiveTutorialOverlay(theme),
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
  void _advanceToNextLevelPlayback(int completedLevel) async {
    if (!mounted || _gameState != GameState.successTransition) return;

    void startNextLevelSequence() {
      if (!mounted) return;
      setState(() {
        _gameState = GameState.playback;
        _sequence.add(_random.nextInt(9));
      });
      _saveGameProgress();
      _runPlayback();
    }

    if (AdService.shouldShowInterstitialOnLevelComplete(completedLevel)) {
      if (kIsWeb) {
        _showTestInterstitialOverlay(onDismissed: startNextLevelSequence);
      } else {
        final shown = await AdService.instance.showInterstitialAdOrLoad(onDismissed: startNextLevelSequence);
        if (!shown) {
          startNextLevelSequence();
        }
      }
    } else {
      startNextLevelSequence();
    }
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
                const SizedBox(height: 10),

                // 3-Star Performance Rating System
                Builder(
                  builder: (context) {
                    final int starsEarned = _inputTimerPercentage >= 0.65 ? 3 : (_inputTimerPercentage >= 0.30 ? 2 : 1);
                    final String starRatingText = starsEarned == 3
                        ? 'PERFECT SPARK! ⚡'
                        : (starsEarned == 2 ? 'GREAT FOCUS! 🎯' : 'LEVEL CLEARED! 🏁');
                    final Color starColor = starsEarned == 3
                        ? const Color(0xFFF59E0B)
                        : (starsEarned == 2 ? const Color(0xFF10B981) : const Color(0xFF06B6D4));

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(3, (index) {
                            final isEarned = index < starsEarned;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4.0),
                              child: Icon(
                                isEarned ? Icons.star_rounded : Icons.star_border_rounded,
                                size: index == 1 ? 34 : 26,
                                color: isEarned ? starColor : Colors.white24,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          starRatingText,
                          style: GoogleFonts.orbitron(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: starColor,
                          ),
                        ),
                      ],
                    );
                  },
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
                            'LVL $_highScore',
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

  // ── Modular Modal Dialog Delegates ───────────────────────────────────────
  void _showTutorialModal(BuildContext context, GameTheme theme) {
    HapticFeedback.selectionClick();
    TutorialModal.show(
      context,
      theme: theme,
    );
  }

  void _showLevelRoadmapModal(BuildContext context, GameTheme theme, {VoidCallback? onDismiss}) {
    HapticFeedback.selectionClick();
    LevelRoadmapModal.show(
      context,
      theme: theme,
      currentLevel: _level,
      highScoreLevel: _highScore,
    ).then((_) {
      if (mounted) {
        onDismiss?.call();
      }
    });
  }

  void _showEditPlayerNameModal(BuildContext context, GameTheme theme, {bool returnToLeaderboard = true}) {
    HapticFeedback.selectionClick();
    EditPlayerNameModal.show(
      context,
      theme: theme,
      currentName: _playerName,
      onSave: (newName) async {
        final oldName = _playerName;
        if (!mounted) return;
        setState(() {
          _playerName = newName;
          for (int i = 0; i < _leaderboard.length; i++) {
            if (_leaderboard[i].playerName == oldName || _leaderboard[i].playerName == 'You') {
              _leaderboard[i] = LeaderboardEntry(
                playerName: newName,
                level: _leaderboard[i].level,
                streak: _leaderboard[i].streak,
                date: _leaderboard[i].date,
              );
            }
          }
        });
        if (_storageService != null) {
          await _storageService!.setPlayerName(newName);
          final String jsonStr = jsonEncode(_leaderboard.map((e) => e.toJson()).toList());
          await _storageService!.setHallOfFameJson(jsonStr);
        }
        if (returnToLeaderboard && mounted) {
          _showLeaderboardModal(context, theme);
        }
      },
    );
  }

  void _showLeaderboardModal(BuildContext context, GameTheme theme) {
    HapticFeedback.selectionClick();
    LeaderboardModal.show(
      context,
      theme: theme,
      leaderboard: _leaderboard,
      activePlayerName: _playerName,
      onEditGamerTag: () {
        _showEditPlayerNameModal(context, theme);
      },
    );
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



