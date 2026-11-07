package io.github.brokoskokoli.running_app

import android.content.Intent
import java.io.File

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

    /** Öffnen: Das System liefert eine lesbare URI; die App kopiert den Inhalt als Strom. */
    fun openDocument() = IntentSpec(
        action = Intent.ACTION_OPEN_DOCUMENT,
        mimeType = "*/*",
        flags = 0,
        categories = listOf(Intent.CATEGORY_OPENABLE),
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

/** Inhalt einer Übergabe: Bytes aus dem Kanal oder eine Datei, die schon im Exportordner liegt. */
sealed interface HandoffSource {
    class Bytes(val bytes: ByteArray) : HandoffSource

    /** Geprüft über [ExportFiles.resolve]; wird beim Speichern gestreamt, nie ganz geladen. */
    class Path(val file: File) : HandoffSource
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
    private enum class Kind { SHARE, SAVE, PICK }

    private var pending: R? = null
    private var kind: Kind? = null
    private var launched = false
    private var left = false
    private var saveSource: HandoffSource? = null
    private var pickAnswered = false

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

    /** Hält [source] bis zur Antwort des Dokumentenziels. */
    fun beginSave(result: R, source: HandoffSource): Boolean = begin(result, Kind.SAVE, source)

    fun beginSave(result: R, bytes: ByteArray): Boolean = beginSave(result, HandoffSource.Bytes(bytes))

    private fun begin(result: R, k: Kind, source: HandoffSource?): Boolean {
        if (pending != null) {
            answers.error(result, "busy", null)
            return false
        }
        generation++
        pending = result
        kind = k
        launched = false
        left = false
        saveSource = source
        pickAnswered = false
        return true
    }

    /** Die Activity ist vom Systemdialog verdeckt (beim Teilen erst nach dem Start des Menüs). */
    fun paused() {
        if (kind == Kind.SHARE && launched) left = true
    }

    /**
     * Ein Ziel im Teilen-Menü wurde gewählt. Bekannte Unschärfe: Android meldet die Wahl
     * asynchron. Schließt das Ziel sofort (oder bei der Aktion „Kopieren“ ab Android 14), kann
     * [resumed] vorher ankommen; dann heißt das Ergebnis „cancelled“, obwohl geteilt wurde.
     */
    fun chosen() {
        if (kind == Kind.SHARE && launched) finish("completed")
    }

    /** Activity wieder vorne: nach dem Teilen-Menü ohne Wahl heißt das Abbruch. */
    fun resumed() {
        if (kind == Kind.SHARE && left) finish("cancelled")
    }

    /**
     * Antwort des Dokumentenziels: `null` heißt abgebrochen, sonst schreibt [write] den Inhalt
     * im Hintergrund; die Antwort an Dart folgt auf dem Hauptthread. `false`, wenn kein
     * Speichern offen ist (Activity neu erzeugt, Übergabe schon beendet): Dann gehört ein vom
     * System schon angelegtes Dokument niemandem, und der Aufrufer entfernt es.
     */
    fun <U> saveAnswered(uri: U?, write: (U, HandoffSource) -> Unit): Boolean {
        if (kind != Kind.SAVE) return false
        // Schon beantwortet, das Schreiben läuft: Das Dokument gehört dieser Übergabe.
        val source = saveSource ?: return true
        saveSource = null
        if (uri == null) {
            finish("cancelled")
            return true
        }
        val token = generation
        threads.background {
            val written = runCatching { write(uri, source) }
            threads.main {
                if (token != generation) return@main
                written.fold(
                    onSuccess = { finish("completed") },
                    // Detail nur der Klassenname: keine Inhalte, keine Pfade.
                    onFailure = { e -> fail("write_failed", e.javaClass.simpleName) },
                )
            }
        }
        return true
    }

    /** Datei öffnen (Reimport): Der Aufrufer startet danach den Dialog. */
    fun beginPick(result: R): Boolean = begin(result, Kind.PICK, null)

    /**
     * Antwort des Dokumentendialogs: `null` heißt abgebrochen, sonst kopiert [copy] im
     * Hintergrund und liefert den Pfad der Kopie, der als Antwort an Dart geht. `false`, wenn
     * kein Öffnen offen ist; das System legt beim Öffnen nichts an, es gibt nichts zu entfernen.
     */
    fun <U> pickAnswered(uri: U?, copy: (U) -> String): Boolean {
        if (kind != Kind.PICK) return false
        // Doppelte Antwort, während das Kopieren läuft: gehört noch zu diesem Öffnen.
        if (pickAnswered) return true
        pickAnswered = true
        if (uri == null) {
            finish("cancelled")
            return true
        }
        val token = generation
        threads.background {
            val copied = runCatching { copy(uri) }
            threads.main {
                if (token != generation) return@main
                copied.fold(
                    onSuccess = { path -> finish(path) },
                    // Detail nur der Klassenname: keine Inhalte, keine Pfade.
                    onFailure = { e -> fail("read_failed", e.javaClass.simpleName) },
                )
            }
        }
        return true
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
        saveSource = null
        pickAnswered = false
        generation++
    }
}
