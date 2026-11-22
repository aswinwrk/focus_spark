package com.focusspark.focus_spark

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.focusspark.focus_spark/audio"
        private const val SAMPLE_RATE = 44100
        private const val CHUNK_SIZE = 2048
    }

    private val ambientSessionId = AtomicInteger(0)
    @Volatile
    private var currentAmbientTrack: AudioTrack? = null
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
        ambientSessionId.incrementAndGet()
        synchronized(ambientLock) {
            try {
                currentAmbientTrack?.let { track ->
                    if (track.playState == AudioTrack.PLAYSTATE_PLAYING) {
                        track.pause()
                        track.flush()
                        track.stop()
                    }
                    track.release()
                }
            } catch (e: Exception) {
                android.util.Log.e("FocusSpark", "Error stopping ambient track: ${e.message}")
            } finally {
                currentAmbientTrack = null
            }
        }
    }

    private fun startNativeAmbientMusic() {
        // Stop any currently running instance first
        stopNativeAmbientMusic()
        val mySession = ambientSessionId.incrementAndGet()

        Thread {
            // Calm Meditative Zen Ambient Pad Chords (Cmaj9 -> Fmaj7 -> Am9 -> G6/9)
            val chords = arrayOf(
                doubleArrayOf(130.81, 196.00, 246.94, 293.66, 329.63), // Cmaj9
                doubleArrayOf(174.61, 261.63, 329.63, 440.00),         // Fmaj7
                doubleArrayOf(110.00, 164.81, 196.00, 261.63, 293.66), // Am9
                doubleArrayOf(98.00, 146.83, 196.00, 246.94, 293.66)   // G6/9
            )

            val minBufSize = AudioTrack.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val track = AudioTrack.Builder()
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
                .setBufferSizeInBytes(max(minBufSize * 4, CHUNK_SIZE * 4))
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build()

            synchronized(ambientLock) {
                if (mySession != ambientSessionId.get()) {
                    track.release()
                    return@Thread
                }
                currentAmbientTrack = track
            }

            val buffer = ShortArray(CHUNK_SIZE)
            val chordDurationSamples = (SAMPLE_RATE * 4.5).toLong() // 4.5 seconds per chord
            val crossfadeSamples = (SAMPLE_RATE * 1.0).toLong()     // 1.0 second crossfade
            val maxAmplitude = Short.MAX_VALUE * 0.045               // Gentle 4.5% volume
            var totalSampleIdx = 0L

            // Track phases for continuous smooth waveforms
            var phasesA = DoubleArray(5)
            var phasesB = DoubleArray(5)

            try {
                track.play()

                while (mySession == ambientSessionId.get()) {
                    for (i in 0 until CHUNK_SIZE) {
                        val currentChordIdx = ((totalSampleIdx / chordDurationSamples) % chords.size).toInt()
                        val nextChordIdx = (currentChordIdx + 1) % chords.size
                        val sampleInChord = totalSampleIdx % chordDurationSamples

                        val chordA = chords[currentChordIdx]
                        val chordB = chords[nextChordIdx]

                        // Resize phase arrays if chord note count differs
                        if (phasesA.size < chordA.size) phasesA = DoubleArray(chordA.size)
                        if (phasesB.size < chordB.size) phasesB = DoubleArray(chordB.size)

                        var sampleA = 0.0
                        for (n in chordA.indices) {
                            phasesA[n] += 2.0 * PI * chordA[n] / SAMPLE_RATE
                            if (phasesA[n] >= 2.0 * PI) phasesA[n] -= 2.0 * PI
                            // Warm sine wave with subtle octave overtone
                            sampleA += sin(phasesA[n]) + 0.15 * sin(2.0 * phasesA[n])
                        }
                        sampleA /= chordA.size

                        var sampleB = 0.0
                        for (n in chordB.indices) {
                            phasesB[n] += 2.0 * PI * chordB[n] / SAMPLE_RATE
                            if (phasesB[n] >= 2.0 * PI) phasesB[n] -= 2.0 * PI
                            sampleB += sin(phasesB[n]) + 0.15 * sin(2.0 * phasesB[n])
                        }
                        sampleB /= chordB.size

                        // Smooth crossfade between chords at the end of each chord
                        val crossfadeStart = chordDurationSamples - crossfadeSamples
                        val finalSample: Double = if (sampleInChord >= crossfadeStart) {
                            val progress = (sampleInChord - crossfadeStart).toDouble() / crossfadeSamples.toDouble()
                            val weightB = 0.5 * (1.0 - cos(PI * progress))
                            val weightA = 1.0 - weightB
                            (sampleA * weightA) + (sampleB * weightB)
                        } else {
                            sampleA
                        }

                        // Gentle LFO breathing modulation (~0.12 Hz)
                        val lfo = 0.88 + 0.12 * sin(2.0 * PI * 0.12 * totalSampleIdx / SAMPLE_RATE)
                        val scaled = (finalSample * maxAmplitude * lfo).toInt()
                        buffer[i] = scaled.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()

                        totalSampleIdx++
                    }

                    if (mySession != ambientSessionId.get()) break
                    track.write(buffer, 0, CHUNK_SIZE)
                }
            } catch (e: Exception) {
                // Thread interrupted or stopped
            } finally {
                synchronized(ambientLock) {
                    if (currentAmbientTrack === track) {
                        try {
                            track.stop()
                            track.release()
                        } catch (_: Exception) {}
                        currentAmbientTrack = null
                    }
                }
            }
        }.apply {
            isDaemon = true
            name = "ZenAmbientMusicThread-$mySession"
            start()
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
