package io.github.brokoskokoli.ramuri

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.Locale

/** Was die Sprachausgabe tut (Android: TextToSpeech, Wiedergabe im App-Prozess, Audio-Fokus; Test: Liste). */
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

/** Spielt eine fertige Audiodatei ab; [onEnd] (true = ohne Fehler) kommt genau einmal, nach [stop] nicht mehr. */
interface FilePlayer {
    fun play(file: File, onEnd: (ok: Boolean) -> Unit)
    fun stop()
}

/**
 * Wiedergabe im App-Prozess (Android 17, Hintergrund-Audio-Hardening): die Engine schreibt jede Ansage in eine
 * Datei, die App spielt sie der Reihe nach selbst ab. Gespielt wird in der Reihenfolge von [begin], auch wenn
 * die Dateien in anderer Reihenfolge fertig werden. Jede Datei wird nach Wiedergabe, Fehler, [abort] oder
 * [clear] gelöscht. [onFinished] kommt je Ansage genau einmal (nicht für [abort] und [clear]).
 * Nur vom Hauptthread benutzen.
 */
class SynthesisPlayback(
    private val player: FilePlayer,
    private val delete: (File) -> Unit,
    private val onFinished: (id: String) -> Unit,
) {
    private class Item(val id: String, val file: File) { var ready = false; var failed = false }

    private val items = mutableListOf<Item>()
    private var playing: Item? = null

    val count: Int get() = items.size

    /** Eine Ansage wird synthetisiert; die Datei [file] gehört ab jetzt dieser Klasse. */
    fun begin(id: String, file: File) { items.add(Item(id, file)) }

    /** Die Synthese konnte nicht gestartet werden: Datei weg, kein [onFinished]. */
    fun abort(id: String) {
        val item = items.firstOrNull { it.id == id } ?: return
        items.remove(item)
        delete(item.file)
    }

    /** Die Engine meldet „Datei fertig“ ([ok]) oder „Fehler“ für [id]. */
    fun synthesized(id: String, ok: Boolean) {
        val item = items.firstOrNull { it.id == id } ?: return
        item.ready = true
        item.failed = !ok
        advance()
    }

    /** Alles verwerfen (stop): Wiedergabe anhalten, alle Dateien löschen. */
    fun clear() {
        playing = null
        player.stop()
        items.forEach { delete(it.file) }
        items.clear()
    }

    private fun advance() {
        while (playing == null) {
            val head = items.firstOrNull() ?: return
            if (!head.ready) return
            if (head.failed) { finish(head); continue }
            playing = head
            player.play(head.file) { _ -> if (playing === head) finish(head) }
        }
    }

    private fun finish(item: Item) {
        items.remove(item)
        if (playing === item) playing = null
        delete(item.file)
        onFinished(item.id)
        advance()
    }
}

/** Reste früherer Läufe (Absturz, Prozessende vor dem Löschen) aus [dir] entfernen; gibt die Anzahl zurück. */
fun deleteStaleVoiceFiles(dir: File): Int =
    dir.listFiles { f -> f.name.startsWith(VoiceChannel.FILE_PREFIX) }?.count { it.delete() } ?: 0

/**
 * Sprachausgabe der geführten Einheit (WP24, Festlegung 9): eigener Kanal `ramuri/voice` auf der
 * Sprachausgabe des Systems (android.speech.tts.TextToSpeech, synthesizeToFile; abgespielt wird im App-Prozess,
 * damit das Hintergrund-Audio-Hardening ab Android 17 die Ansage nicht stummschaltet), getrennt vom RecordingService. Kein Paket,
 * kein Netzcode der App, keine Texte in Logs. Fehler werden als Kanalfehler gemeldet; Dart behandelt sie
 * als folgenlos. Audio-Fokus „transient may duck“: laufende Musik wird leiser, nicht unterbrochen.
 */
object VoiceChannel {
    const val CHANNEL = "ramuri/voice"

    /** Dateiname der Zwischendateien im App-Cache (Gesundheitsdaten: nur kurz, danach gelöscht). */
    const val FILE_PREFIX = "ramuri-voice-"

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
        private val playback = SynthesisPlayback(MediaFilePlayer(attributes), { it.delete() }) { id -> queue.finished(id) }

        init { deleteStaleVoiceFiles(context.cacheDir) }

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
                playback.clear()
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
                        playback.clear()
                        tts?.shutdown()
                        tts = null
                        return@post
                    }
                    val engine = tts ?: return@post
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) { utteranceId?.let { main.post { playback.synthesized(it, true) } } }
                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) { utteranceId?.let { main.post { playback.synthesized(it, false) } } }
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
            val file = File(context.cacheDir, "$FILE_PREFIX$id.wav")
            playback.begin(id, file)
            val started = try {
                engine.synthesizeToFile(text, Bundle(), file, id) == TextToSpeech.SUCCESS
            } catch (e: Throwable) {
                false
            }
            // Bei false meldet VoiceQueue die Ansage selbst als fertig; hier nur die Datei räumen.
            if (!started) playback.abort(id)
            return started
        }

        /** Abspielen im App-Prozess mit denselben AudioAttributes wie zuvor; kein Text, keine Pfade im Log. */
        private class MediaFilePlayer(private val attributes: AudioAttributes) : FilePlayer {
            private var player: MediaPlayer? = null

            override fun play(file: File, onEnd: (ok: Boolean) -> Unit) {
                var done = false
                fun end(ok: Boolean) {
                    if (done) return
                    done = true
                    release()
                    onEnd(ok)
                }
                try {
                    val p = MediaPlayer()
                    player = p
                    p.setAudioAttributes(attributes)
                    FileInputStream(file).use { p.setDataSource(it.fd) }
                    p.setOnCompletionListener { end(true) }
                    p.setOnErrorListener { _, _, _ -> end(false); true }
                    p.setOnPreparedListener { it.start() }
                    p.prepareAsync()
                } catch (e: Throwable) {
                    end(false)
                }
            }

            override fun stop() = release()

            private fun release() {
                val p = player ?: return
                player = null
                try { p.setOnCompletionListener(null); p.setOnErrorListener(null); p.release() } catch (e: Throwable) {}
            }
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
