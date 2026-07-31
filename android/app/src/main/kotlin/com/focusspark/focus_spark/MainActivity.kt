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

    @Volatile
    private var isAmbientPlaying = false
    private var ambientThread: Thread? = null

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
                "startAmbientMusic" -> {
                    startNativeAmbientMusic()
                    result.success(null)
                }
                "stopAmbientMusic" -> {
                    stopNativeAmbientMusic()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startNativeAmbientMusic() {
        if (isAmbientPlaying) return
        isAmbientPlaying = true

        ambientThread = Thread {
            // Upbeat Dual-Harmony Arcade Electro Melody (142 BPM)
            val melodyNotes = doubleArrayOf(
                // Bar 1: C Major
                523.25, 659.25, 783.99, 1046.50, 783.99, 659.25, 783.99, 1046.50,
                // Bar 2: G Major
                392.00, 493.88, 587.33, 783.99, 587.33, 493.88, 587.33, 783.99,
                // Bar 3: A Minor
                440.00, 523.25, 659.25, 880.00, 659.25, 523.25, 659.25, 880.00,
                // Bar 4: F Major
                349.23, 440.00, 523.25, 698.46, 523.25, 440.00, 523.25, 698.46
            )

            val harmonyNotes = doubleArrayOf(
                // Bar 1
                329.63, 392.00, 523.25, 659.25, 523.25, 392.00, 523.25, 659.25,
                // Bar 2
                246.94, 293.66, 392.00, 493.88, 392.00, 293.66, 392.00, 493.88,
                // Bar 3
                261.63, 329.63, 440.00, 523.25, 440.00, 329.63, 440.00, 523.25,
                // Bar 4
                220.00, 261.63, 349.23, 440.00, 349.23, 261.63, 349.23, 440.00
            )

            val bassNotes = doubleArrayOf(
                130.81, 0.0, 130.81, 0.0, 130.81, 0.0, 130.81, 0.0,
                98.00,  0.0, 98.00,  0.0, 98.00,  0.0, 98.00,  0.0,
                110.00, 0.0, 110.00, 0.0, 110.00, 0.0, 110.00, 0.0,
                87.31,  0.0, 87.31,  0.0, 87.31,  0.0, 87.31,  0.0
            )

            var stepIdx = 0
            val stepDurationMs = 210L

            while (isAmbientPlaying) {
                val leadFreq = melodyNotes[stepIdx]
                val harmFreq = harmonyNotes[stepIdx]
                val bassFreq = bassNotes[stepIdx]

                playDualTone(leadFreq, harmFreq, bassFreq, 0.18)
                stepIdx = (stepIdx + 1) % melodyNotes.size

                try {
                    Thread.sleep(stepDurationMs)
                } catch (e: InterruptedException) {
                    break
                }
            }
        }.apply { start() }
    }

    private fun stopNativeAmbientMusic() {
        isAmbientPlaying = false
        ambientThread?.interrupt()
        ambientThread = null
    }

    private fun playDualTone(leadFreq: Double, harmFreq: Double, bassFreq: Double, durationSeconds: Double) {
        val numSamples = (SAMPLE_RATE * durationSeconds).toInt().coerceAtLeast(1)
        val fadeLen = (SAMPLE_RATE * 0.005).toInt()
        val buffer = ShortArray(numSamples)
        val amplitude = Short.MAX_VALUE * 0.12

        for (i in 0 until numSamples) {
            var sample = amplitude * sin(2.0 * PI * leadFreq * i / SAMPLE_RATE)
            if (harmFreq > 0) {
                sample += amplitude * 0.6 * sin(2.0 * PI * harmFreq * i / SAMPLE_RATE)
            }
            if (bassFreq > 0) {
                sample += amplitude * 0.8 * sin(2.0 * PI * bassFreq * i / SAMPLE_RATE)
            }

            val fadeIn = if (i < fadeLen) 0.5 * (1 - cos(PI * i / fadeLen)) else 1.0
            val fadeOut = if (i >= numSamples - fadeLen) 0.5 * (1 - cos(PI * (numSamples - i) / fadeLen)) else 1.0

            buffer[i] = (sample * fadeIn * fadeOut).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
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
        } catch (e: Exception) {
            // Ignore temporary audio track exceptions
        } finally {
            Thread {
                try {
                    Thread.sleep((durationSeconds * 1000).toLong() + 20L)
                    audioTrack.stop()
                    audioTrack.release()
                } catch (e: Exception) {}
            }.start()
        }
    }

    private fun playTone(frequency: Double, durationSeconds: Double) {
        val numSamples = (SAMPLE_RATE * durationSeconds).toInt().coerceAtLeast(1)
        val fadeLen    = (SAMPLE_RATE * 0.005).toInt()   // 5 ms fade window
        val buffer     = ShortArray(numSamples)
        val amplitude  = Short.MAX_VALUE * 0.55           // 55% volume

        for (i in 0 until numSamples) {
            val sample = amplitude * sin(2.0 * PI * frequency * i / SAMPLE_RATE)
            val fadeIn  = if (i < fadeLen) 0.5 * (1 - cos(PI * i / fadeLen)) else 1.0
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
            val playbackMs = (durationSeconds * 1000).toLong() + 20L
            Thread.sleep(playbackMs)
        } finally {
            audioTrack.stop()
            audioTrack.release()
        }
    }
}
