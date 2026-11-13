import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';

class LeaderboardOpenResult {
  final bool opened;
  final String? error;

  const LeaderboardOpenResult({required this.opened, this.error});
}

/// Service for Google Play Games Services integration.
/// Handles authentication, score submission, and native leaderboard display.
class PlayGamesService {
  static const String _leaderboardId = 'CgkIoMGk--0UEAIQAA';
  static Completer<bool>? _authCompleter;
  static String? _lastAuthError;

  /// Check whether the player is genuinely signed in to Google Play Games natively.
  static Future<bool> isSignedIn() async {
    try {
      return await GamesServices.isSignedIn;
    } catch (e) {
      debugPrint('PlayGames isSignedIn check error: $e');
      return false;
    }
  }

  static String _formatError(Object e) {
    if (e is PlatformException) {
      return 'Code: ${e.code} | ${e.message ?? e.details ?? "Unknown error"}';
    }
    return e.toString();
  }

  /// Attempts to sign in to Google Play Games.
  static Future<bool> signIn() async {
    if (_authCompleter != null) {
      return _authCompleter!.future;
    }

    final completer = Completer<bool>();
    _authCompleter = completer;
    _lastAuthError = null;
    try {
      final res = await GamesServices.signIn();
      debugPrint('PlayGames signIn response: $res');

      final signedIn = await GamesServices.isSignedIn;
      if (!signedIn) {
        _lastAuthError = 'Sign-in finished (res: $res), but Play Games reports not authenticated (check SHA-1 & Testers in Play Console).';
      }
      completer.complete(signedIn);
      return signedIn;
    } catch (e) {
      _lastAuthError = _formatError(e);
      debugPrint('PlayGames signIn error: $_lastAuthError');
      completer.complete(false);
      return false;
    } finally {
      _authCompleter = null;
    }
  }

  /// Submits the player's best level score to the Play Games leaderboard silently.
  static Future<void> submitScore(int level) async {
    if (level <= 0) return;
    try {
      final signedIn = await isSignedIn();
      if (!signedIn) return;

      await GamesServices.submitScore(
        score: Score(
          androidLeaderboardID: _leaderboardId,
          value: level,
        ),
      );
      debugPrint('PlayGames score submitted successfully: Level $level');
    } catch (e) {
      debugPrint('PlayGames submitScore error: ${_formatError(e)}');
    }
  }

  /// Opens the official native Google Play Games leaderboard sheet.
  /// Returns [LeaderboardOpenResult] with opened status and exact error if failed.
  static Future<LeaderboardOpenResult> showLeaderboard() async {
    try {
      var signedIn = await isSignedIn();
      if (!signedIn) {
        signedIn = await signIn();
        if (!signedIn) {
          return LeaderboardOpenResult(
            opened: false,
            error: _lastAuthError ?? 'Play Games sign-in was cancelled or failed.',
          );
        }
      }

      try {
        await GamesServices.showLeaderboards(
          androidLeaderboardID: _leaderboardId,
        );
        return const LeaderboardOpenResult(opened: true);
      } catch (idError) {
        final firstError = _formatError(idError);
        debugPrint('PlayGames showLeaderboards with ID error: $firstError. Trying default view...');
        try {
          await GamesServices.showLeaderboards();
          return const LeaderboardOpenResult(opened: true);
        } catch (fallbackError) {
          return LeaderboardOpenResult(
            opened: false,
            error: 'ID error: $firstError\nFallback error: ${_formatError(fallbackError)}',
          );
        }
      }
    } catch (e) {
      return LeaderboardOpenResult(
        opened: false,
        error: _formatError(e),
      );
    }
  }
}
