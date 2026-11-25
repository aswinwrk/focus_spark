package com.focusspark.focus_spark

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.focusspark.focus_spark/audio"
        private const val SAMPLE_RATE = 44100
        private const val CHUNK_SIZE = 2048
    }

    @Volatile
    private var ambientMediaPlayer: MediaPlayer? = null
    @Volatile
    private var currentAmbientVolume = 0.50f
    private val ambientLock = Any()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "playTone" -> {
                    val frequency = (call.argument<Any>("frequency") as? Number)?.toDouble() ?: 440.0
                    val duration  = (call.argument<Any>("duration")  as? Number)?.toDouble() ?: 0.2
                    Thread {
                        playTone(frequency, duration)
                    }.apply {
                        isDaemon = true
                        start()
                    }
                    result.success(null)
                }
                "startAmbientMusic" -> {
                    startNativeAmbientMusic()
                    result.success(null)
                }
                "stopAmbientMusic" -> {
                    stopNativeAmbientMusic()
                    result.success(null)
                }
                "setAmbientVolume" -> {
                    val volume = (call.argument<Any>("volume") as? Number)?.toFloat() ?: 0.50f
                    setNativeAmbientVolume(volume)
                    result.success(null)
                }
                "vibrate" -> {
                    val durationMs = (call.argument<Any>("durationMs") as? Number)?.toLong() ?: 40L
                    triggerNativeVibration(durationMs)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        stopNativeAmbientMusic()
        super.onPause()
    }

    override fun onDestroy() {
        stopNativeAmbientMusic()
        super.onDestroy()
    }

    private fun triggerNativeVibration(durationMs: Long) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            if (!vibrator.hasVibrator()) return

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val effect = VibrationEffect.createOneShot(durationMs, 255)
                vibrator.vibrate(effect, audioAttributes)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(durationMs)
            }
        } catch (e: Exception) {
            android.util.Log.e("FocusSpark", "Native vibration error: ${e.message}")
        }
    }

    private fun stopNativeAmbientMusic() {
        synchronized(ambientLock) {
            try {
                ambientMediaPlayer?.let { player ->
                    if (player.isPlaying) {
                        player.stop()
                    }
                    player.release()
                }
            } catch (e: Exception) {
                android.util.Log.e("FocusSpark", "Error stopping native ambient music: ${e.message}")
            } finally {
                ambientMediaPlayer = null
            }
        }
    }

    private fun setNativeAmbientVolume(volume: Float) {
        synchronized(ambientLock) {
            currentAmbientVolume = volume.coerceIn(0.0f, 1.0f)
            try {
                ambientMediaPlayer?.setVolume(currentAmbientVolume, currentAmbientVolume)
            } catch (e: Exception) {
                android.util.Log.e("FocusSpark", "Error setting ambient volume: ${e.message}")
            }
        }
    }

    private fun startNativeAmbientMusic() {
        stopNativeAmbientMusic()
        synchronized(ambientLock) {
            try {
                val player = MediaPlayer.create(this, R.raw.brain_reboot_music)
                if (player != null) {
                    player.setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_GAME)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
                    )
                    player.isLooping = true
                    player.setVolume(currentAmbientVolume, currentAmbientVolume)
                    player.start()
                    ambientMediaPlayer = player
                } else {
                    android.util.Log.e("FocusSpark", "Failed to load R.raw.brain_reboot_music")
                }
            } catch (e: Exception) {
                android.util.Log.e("FocusSpark", "Error starting native ambient music: ${e.message}")
            }
        }
    }

    private fun playTone(frequency: Double, durationSeconds: Double) {
        val numSamples = (SAMPLE_RATE * durationSeconds).toInt().coerceAtLeast(1)
        val fadeLen    = (SAMPLE_RATE * 0.005).toInt()   // 5 ms fade window
        val buffer     = ShortArray(numSamples)
        val amplitude  = Short.MAX_VALUE * 0.50           // 50% volume

        for (i in 0 until numSamples) {
            val fundamental = sin(2.0 * PI * frequency * i / SAMPLE_RATE)
            val harmonic = 0.25 * sin(4.0 * PI * frequency * i / SAMPLE_RATE)
            val octaveSpark = 0.10 * sin(8.0 * PI * frequency * i / SAMPLE_RATE)
            val rawSample = amplitude * (fundamental + harmonic + octaveSpark)

            val fadeIn  = if (i < fadeLen) 0.5 * (1 - cos(PI * i / fadeLen)) else 1.0
            val fadeOut = if (i >= numSamples - fadeLen)
                0.5 * (1 - cos(PI * (numSamples - i) / fadeLen)) else 1.0

            buffer[i] = (rawSample * fadeIn * fadeOut).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }

        val minBufSize = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        val bufSizeBytes = (numSamples * 2).coerceAtLeast(minBufSize)

        val audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build()
            )
            .setBufferSizeInBytes(bufSizeBytes)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        try {
            audioTrack.write(buffer, 0, numSamples)
            audioTrack.play()
            val playbackMs = (durationSeconds * 1000).toLong() + 20L
            Thread.sleep(playbackMs)
        } finally {
            try {
                audioTrack.stop()
                audioTrack.release()
            } catch (_: Exception) {}
        }
    }
}
