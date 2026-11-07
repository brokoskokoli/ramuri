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

/**
 * Ablauf einer Übergabe (Teilen oder Speichern), immer höchstens eine zugleich. Alle Aufrufe
 * auf dem Hauptthread.
 *
 * Teilen: Android meldet das gewählte Ziel über den IntentSender des Choosers ([chosen]) und
 * sonst nichts. Ein Abbruch zeigt sich nur daran, dass die Activity nach dem Menü wieder
 * vorne ist ([resumed] nach [paused]) und kein Ziel gewählt wurde. Wählt der Nutzer ein Ziel,
 * startet es über der Activity; sie kommt erst danach zurück, also nach der Meldung.
 */
class FileHandoffFlow<R>(private val answers: HandoffAnswers<R>) {
    private enum class Kind { SHARE, SAVE }

    private var pending: R? = null
    private var kind: Kind? = null
    private var left = false
    private var saveBytes: ByteArray? = null

    val busy: Boolean get() = pending != null

    /** `false` (und Fehler `busy`), wenn schon eine Übergabe läuft. */
    fun beginShare(result: R): Boolean = begin(result, Kind.SHARE, null)

    /** Hält [bytes] bis zur Antwort des Dokumentenziels. */
    fun beginSave(result: R, bytes: ByteArray): Boolean = begin(result, Kind.SAVE, bytes)

    private fun begin(result: R, k: Kind, bytes: ByteArray?): Boolean {
        if (pending != null) {
            answers.error(result, "busy", null)
            return false
        }
        pending = result
        kind = k
        left = false
        saveBytes = bytes
        return true
    }

    /** Die Activity ist vom Systemdialog verdeckt. */
    fun paused() {
        if (kind == Kind.SHARE) left = true
    }

    /** Ein Ziel im Teilen-Menü wurde gewählt. */
    fun chosen() {
        if (kind == Kind.SHARE) finish("completed")
    }

    /** Activity wieder vorne: nach dem Teilen-Menü ohne Wahl heißt das Abbruch. */
    fun resumed() {
        if (kind == Kind.SHARE && left) finish("cancelled")
    }

    /** Antwort des Dokumentenziels: `null` heißt abgebrochen, sonst schreibt [write] die Bytes. */
    fun <U> saveAnswered(uri: U?, write: (U, ByteArray) -> Unit) {
        if (kind != Kind.SAVE) return
        val bytes = saveBytes ?: return
        if (uri == null) {
            finish("cancelled")
            return
        }
        try {
            write(uri, bytes)
            finish("completed")
        } catch (e: Exception) {
            // Detail nur der Klassenname: keine Inhalte, keine Pfade.
            fail("write_failed", e.javaClass.simpleName)
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
        left = false
        saveBytes = null
    }
}
