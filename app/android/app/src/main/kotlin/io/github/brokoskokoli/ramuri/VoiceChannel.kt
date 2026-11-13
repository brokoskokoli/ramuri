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
 * Reihenfolge der Ansagen (Review 1, M2): nichts geht verloren. Vor der Bereitschaft der Engine wartende
 * Ansagen stehen in einer Liste; gesprochen wird der Reihe nach (QUEUE_ADD). [onIdle] kommt erst, wenn die
 * letzte ausgegebene Ansage fertig ist (Fokus erst dann freigeben). Nur vom Hauptthread benutzen.
 */
class VoiceQueue(
    /** Gibt eine Ansage an die Engine; false = die Engine hat sie abgelehnt. */
    private val emit: (id: String, text: String, languageTag: String?) -> Boolean,
    private val onIdle: () -> Unit,
) {
    private val pending = mutableListOf<Pair<String, String?>>()
    private val outstanding = mutableSetOf<String>()
    private var ready = false
    private var counter = 0L

    val pendingCount: Int get() = pending.size
    val outstandingCount: Int get() = outstanding.size

    fun speak(text: String, languageTag: String?) {
        if (!ready) pending.add(text to languageTag) else out(text, languageTag)
    }

    fun markReady() {
        ready = true
        val waiting = pending.toList()
        pending.clear()
        waiting.forEach { (t, l) -> out(t, l) }
    }

    /** Engine meldet „fertig“ oder „Fehler“ für [id]. */
    fun finished(id: String) {
        if (outstanding.remove(id) && outstanding.isEmpty()) onIdle()
    }

    /** Alles Wartende und Laufende verwerfen (stop). */
    fun clear() {
        pending.clear()
        outstanding.clear()
    }

    private fun out(text: String, languageTag: String?) {
        val id = "ramuri-voice-${++counter}"
        outstanding.add(id)
        if (!emit(id, text, languageTag)) finished(id)
    }
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
        private var failed = false
        private val release = Runnable { abandonFocus() }
        private val queue = VoiceQueue(::emit) { abandonFocus() }

        override fun speak(text: String, languageTag: String?) {
            main.post {
                if (failed) return@post
                queue.speak(text, languageTag)
                if (tts == null) create()
            }
        }

        override fun stop() {
            main.post {
                queue.clear()
                tts?.stop()
                abandonFocus()
            }
        }

        private fun create() {
            tts = TextToSpeech(context) { status ->
                main.post {
                    if (status != TextToSpeech.SUCCESS) {
                        failed = true
                        queue.clear()
                        tts?.shutdown()
                        tts = null
                        return@post
                    }
                    val engine = tts ?: return@post
                    engine.setAudioAttributes(attributes)
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) { utteranceId?.let { main.post { queue.finished(it) } } }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) { utteranceId?.let { main.post { queue.finished(it) } } }
                    })
                    queue.markReady()
                }
            }
        }

        /** Eine Ansage an die Engine: hinten anhängen (QUEUE_ADD), nie eine laufende abschneiden. */
        private fun emit(id: String, text: String, languageTag: String?): Boolean {
            val engine = tts ?: return false
            val locale = localeFor(languageTag)
            if (locale != null) {
                // Eine Stimme ohne Netzverbindung bevorzugen; sonst die Sprache setzen, wie das System sie liefert.
                val offline = engine.voices
                    ?.firstOrNull { it.locale.language == locale.language && !it.isNetworkConnectionRequired }
                if (offline != null) engine.voice = offline else engine.setLanguage(locale)
            }
            requestFocus()
            main.removeCallbacks(release)
            main.postDelayed(release, FOCUS_TIMEOUT_MS)
            return engine.speak(text, TextToSpeech.QUEUE_ADD, null, id) == TextToSpeech.SUCCESS
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
