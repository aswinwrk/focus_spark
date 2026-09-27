import 'package:flutter_test/flutter_test.dart';
import 'package:focus_spark/game/game_controller.dart';
import 'package:focus_spark/game/game_state_enums.dart';

void main() {
  group('GameController Unit Tests', () {
    late GameController controller;

    setUp(() {
      controller = GameController();
    });

    test('Initial state default values', () {
      expect(controller.gameState, GameState.startScreen);
      expect(controller.level, 1);
      expect(controller.currentStreak, 0);
      expect(controller.highScore, 0);
    });

    test('Start new game sets level 1 and playback state', () {
      controller.startNewGame();
      expect(controller.level, 1);
      expect(controller.gameState, GameState.playback);
      expect(controller.sequence.length, 2);
    });

    test('Reverse level calculation identifies milestone rounds (5, 10, 15)', () {
      expect(controller.isReverseLevel(1), false);
      expect(controller.isReverseLevel(4), false);
      expect(controller.isReverseLevel(5), true);
      expect(controller.isReverseLevel(10), true);
      expect(controller.isReverseLevel(12), false);
      expect(controller.isReverseLevel(15), true);
    });

    test('Normal mode input validation (forward order)', () {
      controller.resumeGame(1, 0, [3, 7]);
      controller.setGameState(GameState.playerInput);

      final correctFirstTap = controller.handleTileTap(3);
      expect(correctFirstTap, true);
      expect(controller.playerInputIndex, 1);
      expect(controller.gameState, GameState.playerInput);

      final correctSecondTap = controller.handleTileTap(7);
      expect(correctSecondTap, true);
      expect(controller.gameState, GameState.successTransition);
      expect(controller.currentStreak, 1);
    });

    test('Reverse mode input validation (reverse order)', () {
      controller.resumeGame(5, 0, [2, 8, 4]); // Reverse level
      controller.setGameState(GameState.playerInput);

      // In reverse mode, expected first tap is last element (4)
      final correctFirstTap = controller.handleTileTap(4);
      expect(correctFirstTap, true);
      expect(controller.playerInputIndex, 1);

      // Expected second tap is middle element (8)
      final correctSecondTap = controller.handleTileTap(8);
      expect(correctSecondTap, true);
      expect(controller.playerInputIndex, 2);

      // Expected final tap is first element (2)
      final correctThirdTap = controller.handleTileTap(2);
      expect(correctThirdTap, true);
      expect(controller.gameState, GameState.successTransition);
    });

    test('Wrong tile tap triggers error transition and resets streak', () {
      controller.resumeGame(1, 4, [1, 5]);
      controller.setGameState(GameState.playerInput);

      final result = controller.handleTileTap(9); // Wrong tile
      expect(result, false);
      expect(controller.currentStreak, 0);
      expect(controller.gameState, GameState.errorTransition);
    });

    test('Star rating calculation evaluates time remaining percentage', () {
      expect(controller.calculateStars(0.80), 3);
      expect(controller.calculateStars(0.50), 2);
      expect(controller.calculateStars(0.10), 1);
    });
  });
}
