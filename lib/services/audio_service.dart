import 'audio_service_native.dart'
    if (dart.library.js_interop) 'audio_service_web.dart';

abstract class AudioService {
  static AudioService? _instance;

  static AudioService get instance {
    _instance ??= getAudioService();
    return _instance!;
  }

  /// Play a synthesizer chime tone with a specified frequency and duration (in seconds).
  void playTone(double frequency, double durationSeconds);

  /// Start ambient background music pad.
  void startAmbientMusic();

  /// Stop ambient background music pad.
  void stopAmbientMusic();
}
