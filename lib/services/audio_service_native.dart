import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'audio_service.dart';

AudioService getAudioService() => NativeAudioService();

/// Native audio service using a Flutter MethodChannel to invoke the
/// Kotlin AudioTrack sine wave synthesizer on Android.
/// On other non-web platforms (desktop), tones are silently skipped.
class NativeAudioService implements AudioService {
  static const MethodChannel _channel =
      MethodChannel('com.focusspark.focus_spark/audio');

  @override
  void playTone(double frequency, double durationSeconds) {
    _playAsync(frequency, durationSeconds);
  }

  @override
  void startAmbientMusic() {
    _invokeChannel('startAmbientMusic');
  }

  @override
  void stopAmbientMusic() {
    _invokeChannel('stopAmbientMusic');
  }

  @override
  void vibrate({int durationMs = 40}) {
    _invokeChannel('vibrate', {'durationMs': durationMs});
  }

  Future<void> _invokeChannel(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      debugPrint('NativeAudioService: no native plugin for $method on this platform.');
    } catch (e) {
      debugPrint('NativeAudioService: $method error: $e');
    }
  }

  Future<void> _playAsync(double frequency, double durationSeconds) async {
    _invokeChannel('playTone', {
      'frequency': frequency,
      'duration': durationSeconds,
    });
  }
}
