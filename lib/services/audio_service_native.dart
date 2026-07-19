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

  Future<void> _playAsync(double frequency, double durationSeconds) async {
    try {
      await _channel.invokeMethod<void>('playTone', {
        'frequency': frequency,
        'duration': durationSeconds,
      });
    } on MissingPluginException {
      // Running on a platform without the native implementation (desktop/test)
      debugPrint('NativeAudioService: no native plugin on this platform.');
    } catch (e) {
      debugPrint('NativeAudioService: playTone($frequency) error: $e');
    }
  }
}
