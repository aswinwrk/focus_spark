import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'audio_service.dart';

@JS('window.playSparkTone')
external void _playSparkTone(double frequency, double duration);

@JS('window.startAmbientMusic')
external void _startAmbientMusicJS();

@JS('window.stopAmbientMusic')
external void _stopAmbientMusicJS();

AudioService getAudioService() => WebAudioService();

class WebAudioService implements AudioService {
  @override
  void playTone(double frequency, double durationSeconds) {
    try {
      _playSparkTone(frequency, durationSeconds);
    } catch (e) {
      debugPrint('WebAudioService playTone error: $e');
    }
  }

  @override
  void startAmbientMusic() {
    try {
      _startAmbientMusicJS();
    } catch (e) {
      debugPrint('WebAudioService startAmbientMusic error: $e');
    }
  }

  @override
  void stopAmbientMusic() {
    try {
      _stopAmbientMusicJS();
    } catch (e) {
      debugPrint('WebAudioService stopAmbientMusic error: $e');
    }
  }

  @override
  void vibrate({int durationMs = 40}) {
    // Vibration is handled by HapticFeedback on Web if supported by browser navigator.vibrate
  }
}
