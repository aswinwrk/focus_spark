import 'dart:math';
import 'package:flutter/foundation.dart';
import 'game_state_enums.dart';

class GameController extends ChangeNotifier {
  final Random _random = Random();

  GameState _gameState = GameState.startScreen;
  int _level = 1;
  int _currentStreak = 0;
  int _highScore = 0;
  List<int> _sequence = [];
  int _playerInputIndex = 0;

  // Getters
  GameState get gameState => _gameState;
  int get level => _level;
  int get currentStreak => _currentStreak;
  int get highScore => _highScore;
  List<int> get sequence => List.unmodifiable(_sequence);
  int get playerInputIndex => _playerInputIndex;

  bool isReverseLevel([int? targetLevel]) {
    final lvl = targetLevel ?? _level;
    return lvl >= 5 && lvl % 5 == 0;
  }

  void setHighScore(int score) {
    if (score > _highScore) {
      _highScore = score;
      notifyListeners();
    }
  }

  void startNewGame() {
    _level = 1;
    _currentStreak = 0;
    _gameState = GameState.playback;
    _sequence = _generateSequence(_level);
    _playerInputIndex = 0;
    notifyListeners();
  }

  void resumeGame(int level, int streak, List<int> sequence) {
    _level = level;
    _currentStreak = streak;
    _sequence = sequence.isNotEmpty ? List.from(sequence) : _generateSequence(level);
    _playerInputIndex = 0;
    _gameState = GameState.playback;
    notifyListeners();
  }

  List<int> _generateSequence(int lvl) {
    final length = 2 + (lvl ~/ 2);
    return List.generate(length, (_) => _random.nextInt(9));
  }

  bool handleTileTap(int tileIndex) {
    if (_gameState != GameState.playerInput || _playerInputIndex >= _sequence.length) {
      return false;
    }

    final bool isReverse = isReverseLevel();
    final int expectedIndex = isReverse
        ? _sequence.length - 1 - _playerInputIndex
        : _playerInputIndex;

    final bool isCorrect = tileIndex == _sequence[expectedIndex];

    if (isCorrect) {
      _playerInputIndex++;
      if (_playerInputIndex >= _sequence.length) {
        // Round completed successfully!
        _currentStreak++;
        if (_level > _highScore) {
          _highScore = _level;
        }
        _gameState = GameState.successTransition;
      }
      notifyListeners();
      return true;
    } else {
      // Wrong move!
      _currentStreak = 0;
      _gameState = GameState.errorTransition;
      notifyListeners();
      return false;
    }
  }

  void advanceToNextLevel() {
    _level++;
    _playerInputIndex = 0;
    _sequence = _generateSequence(_level);
    _gameState = GameState.playback;
    notifyListeners();
  }

  void replayCurrentSequence() {
    _playerInputIndex = 0;
    _gameState = GameState.playback;
    notifyListeners();
  }

  void setGameState(GameState state) {
    _gameState = state;
    notifyListeners();
  }

  int calculateStars(double timeRemainingFactor) {
    if (timeRemainingFactor >= 0.65) {
      return 3;
    } else if (timeRemainingFactor >= 0.30) {
      return 2;
    } else {
      return 1;
    }
  }
}
