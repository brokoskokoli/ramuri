package io.github.brokoskokoli.running_app

import android.content.Intent

/** Wirkungen auf den Kanal; die Entscheidungen liegen in [FileHandoffFlow]. */
interface HandoffAnswers<R> {
    fun success(result: R, value: String)
    fun error(result: R, code: String, detail: String?)
}

/** Beschreibung eines Intents ohne Android-Klassen (testbar auf der JVM). */
data class IntentSpec(
    val action: String,
    val mimeType: String,
    val flags: Int,
    val categories: List<String> = emptyList(),
    val title: String? = null,
)

object HandoffIntents {
    /** Teilen: nur Leserecht auf genau diese URI, kein Schreib- oder Dauerrecht. */
    fun send(mimeType: String) = IntentSpec(
        action = Intent.ACTION_SEND,
        mimeType = mimeType,
        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION,
    )

    /** Speichern: Das System-Dokumentenziel liefert eine URI, in die die App schreibt. */
    fun createDocument(fileName: String, mimeType: String) = IntentSpec(
        action = Intent.ACTION_CREATE_DOCUMENT,
        mimeType = mimeType,
        flags = 0,
        categories = listOf(Intent.CATEGORY_OPENABLE),
        title = fileName,
    )
}

/** Wo der Ablauf arbeitet: Schreiben im Hintergrund, Entscheidungen auf dem Hauptthread. */
interface HandoffThreads {
    fun background(work: () -> Unit)
    fun main(work: () -> Unit)
}

/**
 * Ablauf einer Übergabe (Teilen oder Speichern), immer höchstens eine zugleich. Alle Aufrufe
 * auf dem Hauptthread; nur das Schreiben der Bytes läuft über [HandoffThreads.background],
 * das Ergebnis kommt über [HandoffThreads.main] zurück.
 *
 * Teilen: Android meldet das gewählte Ziel über den IntentSender des Choosers ([chosen]) und
 * sonst nichts. Ein Abbruch zeigt sich nur daran, dass die Activity nach dem Menü wieder
 * vorne ist ([resumed] nach [paused]) und kein Ziel gewählt wurde. Wählt der Nutzer ein Ziel,
 * startet es über der Activity; sie kommt erst danach zurück, also nach der Meldung.
 */
class FileHandoffFlow<R>(
    private val answers: HandoffAnswers<R>,
    private val threads: HandoffThreads,
) {
    private enum class Kind { SHARE, SAVE }

    private var pending: R? = null
    private var kind: Kind? = null
    private var launched = false
    private var left = false
    private var saveBytes: ByteArray? = null

    /** Zählt Übergaben; eine Hintergrundantwort einer schon beendeten Übergabe verfällt. */
    private var generation = 0

    val busy: Boolean get() = pending != null

    /**
     * Teilen: [write] legt die Datei im Hintergrund an, [launch] startet danach auf dem
     * Hauptthread das Teilen-Menü. `false` (und Fehler `busy`), wenn schon eine Übergabe läuft.
     */
    fun <F> share(result: R, write: () -> F, launch: (F) -> Unit): Boolean {
        if (!begin(result, Kind.SHARE, null)) return false
        val token = generation
        threads.background {
            val written = runCatching(write)
            threads.main {
                if (token != generation) return@main
                written.fold(
                    onSuccess = { file ->
                        try {
                            launched = true
                            launch(file)
                        } catch (e: Exception) {
                            fail("share_failed", e.javaClass.simpleName)
                        }
                    },
                    // Detail nur der Klassenname: keine Inhalte, keine Pfade.
                    onFailure = { e -> fail("share_failed", e.javaClass.simpleName) },
                )
            }
        }
        return true
    }

    /** Hält [bytes] bis zur Antwort des Dokumentenziels. */
    fun beginSave(result: R, bytes: ByteArray): Boolean = begin(result, Kind.SAVE, bytes)

    private fun begin(result: R, k: Kind, bytes: ByteArray?): Boolean {
        if (pending != null) {
            answers.error(result, "busy", null)
            return false
        }
        generation++
        pending = result
        kind = k
        launched = false
        left = false
        saveBytes = bytes
        return true
    }

    /** Die Activity ist vom Systemdialog verdeckt (beim Teilen erst nach dem Start des Menüs). */
    fun paused() {
        if (kind == Kind.SHARE && launched) left = true
    }

    /** Ein Ziel im Teilen-Menü wurde gewählt. */
    fun chosen() {
        if (kind == Kind.SHARE && launched) finish("completed")
    }

    /** Activity wieder vorne: nach dem Teilen-Menü ohne Wahl heißt das Abbruch. */
    fun resumed() {
        if (kind == Kind.SHARE && left) finish("cancelled")
    }

    /**
     * Antwort des Dokumentenziels: `null` heißt abgebrochen, sonst schreibt [write] die Bytes
     * im Hintergrund; die Antwort an Dart folgt auf dem Hauptthread.
     */
    fun <U> saveAnswered(uri: U?, write: (U, ByteArray) -> Unit) {
        if (kind != Kind.SAVE) return
        val bytes = saveBytes ?: return
        saveBytes = null
        if (uri == null) {
            finish("cancelled")
            return
        }
        val token = generation
        threads.background {
            val written = runCatching { write(uri, bytes) }
            threads.main {
                if (token != generation) return@main
                written.fold(
                    onSuccess = { finish("completed") },
                    // Detail nur der Klassenname: keine Inhalte, keine Pfade.
                    onFailure = { e -> fail("write_failed", e.javaClass.simpleName) },
                )
            }
        }
    }

    /** Start des Systemdialogs oder Vorbereitung gescheitert. */
    fun fail(code: String, detail: String?) {
        val r = pending ?: return
        reset()
        answers.error(r, code, detail)
    }

    /** Activity weg: offene Übergabe beenden, damit Dart nicht hängt. */
    fun detached() = fail("detached", null)

    private fun finish(value: String) {
        val r = pending ?: return
        reset()
        answers.success(r, value)
    }

    private fun reset() {
        pending = null
        kind = null
        launched = false
        left = false
        saveBytes = null
        generation++
    }
}
