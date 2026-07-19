import 'package:flutter/foundation.dart';
import 'audio_service.dart';

AudioService getAudioService() => StubAudioService();

class StubAudioService implements AudioService {
  @override
  void playTone(double frequency, double durationSeconds) {
    // Non-web platform mock implementation or standard print debug.
    debugPrint('StubAudioService: playTone($frequency, $durationSeconds)');
  }
}
