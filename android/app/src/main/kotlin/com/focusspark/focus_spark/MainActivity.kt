package com.focusspark.focus_spark

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.focusspark.focus_spark/audio"
        private const val SAMPLE_RATE = 44100
    }

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
                    }.start()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Generates a sine wave PCM buffer and plays it via AudioTrack.
     * Runs on a background thread — never blocks the UI.
     * Applies a 5ms Hann fade-in/out envelope to eliminate clicking artifacts.
     */
    private fun playTone(frequency: Double, durationSeconds: Double) {
        val numSamples = (SAMPLE_RATE * durationSeconds).toInt().coerceAtLeast(1)
        val fadeLen    = (SAMPLE_RATE * 0.005).toInt()   // 5 ms fade window
        val buffer     = ShortArray(numSamples)
        val amplitude  = Short.MAX_VALUE * 0.55           // 55% volume

        for (i in 0 until numSamples) {
            // Pure sine wave
            val sample = amplitude * sin(2.0 * PI * frequency * i / SAMPLE_RATE)
            // Apply Hann fade-in at start
            val fadeIn  = if (i < fadeLen) 0.5 * (1 - cos(PI * i / fadeLen)) else 1.0
            // Apply Hann fade-out at end
            val fadeOut = if (i >= numSamples - fadeLen)
                0.5 * (1 - cos(PI * (numSamples - i) / fadeLen)) else 1.0
            buffer[i] = (sample * fadeIn * fadeOut).toInt().toShort()
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
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
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
            // Wait for playback to finish before releasing
            val playbackMs = (durationSeconds * 1000).toLong() + 20L
            Thread.sleep(playbackMs)
        } finally {
            audioTrack.stop()
            audioTrack.release()
        }
    }
}
