package io.github.brokoskokoli.ramuri

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/** Was die Sprachausgabe tut (Android: TextToSpeech mit Audio-Fokus; Test: Liste). */
interface VoiceOutput {
    fun speak(text: String, languageTag: String?)
    fun stop()
}

/**
 * Sprachausgabe der geführten Einheit (WP24, Festlegung 9): eigener Kanal `ramuri/voice` auf der
 * Sprachausgabe des Systems (android.speech.tts.TextToSpeech), getrennt vom RecordingService. Kein Paket,
 * kein Netzcode der App, keine Texte in Logs. Fehler werden als Kanalfehler gemeldet; Dart behandelt sie
 * als folgenlos. Audio-Fokus „transient may duck“: laufende Musik wird leiser, nicht unterbrochen.
 */
object VoiceChannel {
    const val CHANNEL = "ramuri/voice"

    /** Spätestens nach dieser Zeit wird der Fokus freigegeben, auch wenn die Engine nie „fertig“ meldet. */
    const val FOCUS_TIMEOUT_MS = 20_000L

    /** Nur sprechbare Sprachkennung: leer oder `null` = Sprache des Systems. */
    fun localeFor(tag: String?): Locale? =
        if (tag.isNullOrBlank()) null else Locale.forLanguageTag(tag.replace('_', '-'))

    /** true, wenn [method] bekannt ist und ausgeführt wurde. */
    fun dispatch(method: String, text: String?, languageTag: String?, out: VoiceOutput): Boolean = when (method) {
        "speak" -> {
            if (text.isNullOrEmpty()) false else { out.speak(text, languageTag); true }
        }
        "stop" -> { out.stop(); true }
        else -> false
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        val out = AndroidVoice(context.applicationContext)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                if (dispatch(call.method, call.argument<String>("text"), call.argument<String>("language"), out)) {
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            } catch (e: Throwable) {
                result.error("voice_failed", null, null)
            }
        }
    }

    private class AndroidVoice(private val context: Context) : VoiceOutput {
        private val main = Handler(Looper.getMainLooper())
        private val audio = context.getSystemService(AudioManager::class.java)
        private val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        private var focus: AudioFocusRequest? = null
        private var tts: TextToSpeech? = null
        private var ready = false
        private var failed = false
        private var pending: Pair<String, String?>? = null
        private var counter = 0L
        private val release = Runnable { abandonFocus() }

        override fun speak(text: String, languageTag: String?) {
            main.post {
                if (failed) return@post
                val engine = tts
                if (engine == null) {
                    pending = text to languageTag
                    create()
                } else if (!ready) {
                    pending = text to languageTag
                } else {
                    say(engine, text, languageTag)
                }
            }
        }

        override fun stop() {
            main.post {
                pending = null
                tts?.stop()
                abandonFocus()
            }
        }

        private fun create() {
            tts = TextToSpeech(context) { status ->
                main.post {
                    if (status != TextToSpeech.SUCCESS) {
                        failed = true
                        tts?.shutdown()
                        tts = null
                        return@post
                    }
                    val engine = tts ?: return@post
                    engine.setAudioAttributes(attributes)
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) { main.post { abandonFocus() } }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) { main.post { abandonFocus() } }
                    })
                    ready = true
                    pending?.let { (t, l) -> pending = null; say(engine, t, l) }
                }
            }
        }

        private fun say(engine: TextToSpeech, text: String, languageTag: String?) {
            val locale = localeFor(languageTag)
            if (locale != null) {
                // Eine Stimme ohne Netzverbindung bevorzugen; sonst die Sprache setzen, wie das System sie liefert.
                val offline = engine.voices
                    ?.firstOrNull { it.locale.language == locale.language && !it.isNetworkConnectionRequired }
                if (offline != null) engine.voice = offline else engine.setLanguage(locale)
            }
            requestFocus()
            counter++
            val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "ramuri-voice-$counter")
            if (code != TextToSpeech.SUCCESS) abandonFocus()
            main.removeCallbacks(release)
            main.postDelayed(release, FOCUS_TIMEOUT_MS)
        }

        private fun requestFocus() {
            if (focus != null) return
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes)
                .build()
            audio?.requestAudioFocus(request)
            focus = request
        }

        private fun abandonFocus() {
            main.removeCallbacks(release)
            val request = focus ?: return
            focus = null
            audio?.abandonAudioFocusRequest(request)
        }
    }
}
