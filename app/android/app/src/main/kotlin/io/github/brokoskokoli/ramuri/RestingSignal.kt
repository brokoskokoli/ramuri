package io.github.brokoskokoli.ramuri

import android.content.Context
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Was am Ende der Ruhephase ausgegeben wird (Android: Benachrichtigungston, Vibrator; Test: Liste). */
interface RestingSignalOutput {
    fun tone()
    fun vibrate()
}

/**
 * Signal am Ende der Ruhephase der Ruhepuls-Messung (WP27): ein kurzer Ton auf dem Benachrichtigungskanal
 * oder ein einmaliges Vibrationsmuster. Flutters SystemSound ist auf Android wirkungslos und die Haptik hängt an
 * der Berührungsfeedback-Einstellung. Ohne neue Abhängigkeit; das Recht VIBRATE ist ein normales Recht.
 * Dart: SystemRestingSignal; Fehler dort sind folgenlos.
 */
object RestingSignal {
    const val RESTING_SIGNAL_CHANNEL = "ramuri/resting_signal"

    /** Wartezeit, bis Ton und Vibration vorbei sind (ms): Muster 0-250-150-250. */
    private const val TONE_MS = 400
    private val PATTERN = longArrayOf(0, 250, 150, 250)

    /** true, wenn [method] bekannt ist und ausgeführt wurde. */
    fun dispatch(method: String, out: RestingSignalOutput): Boolean = when (method) {
        "tone" -> { out.tone(); true }
        "vibrate" -> { out.vibrate(); true }
        else -> false
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val out = AndroidOutput(context)
        MethodChannel(messenger, RESTING_SIGNAL_CHANNEL).setMethodCallHandler { call, result ->
            try {
                if (dispatch(call.method, out)) result.success(null) else result.notImplemented()
            } catch (e: Throwable) {
                result.error("signal_failed", null, null)
            }
        }
    }

    private class AndroidOutput(private val context: Context) : RestingSignalOutput {
        private val main = Handler(Looper.getMainLooper())

        override fun tone() {
            val gen = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80)
            gen.startTone(ToneGenerator.TONE_PROP_BEEP2, TONE_MS)
            // Der Generator hält Systemressourcen: nach dem Ton freigeben.
            main.postDelayed({ gen.release() }, TONE_MS + 200L)
        }

        override fun vibrate() {
            val v = context.getSystemService(VibratorManager::class.java)?.defaultVibrator ?: return
            if (v.hasVibrator()) v.vibrate(VibrationEffect.createWaveform(PATTERN, -1))
        }
    }
}
