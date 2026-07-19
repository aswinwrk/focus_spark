import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'audio_service.dart';

@JS('window.playSparkTone')
external void _playSparkTone(double frequency, double duration);

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
}
