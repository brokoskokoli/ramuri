package io.github.brokoskokoli.running_app

import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Exportdateien zum Teilen (FR-0201, WP11). Sie liegen in `cacheDir/exports/`: Der Cache ist
 * vom Backup ausgenommen (data_extraction_rules.xml), und nur dieser Ordner ist über den
 * FileProvider freigegeben (res/xml/file_paths.xml). Gelöscht wird beim Prozessstart und vor
 * jedem neuen Teilen, nicht direkt nach dem Teilen-Menü: Der Empfänger liest die Datei oft
 * erst später.
 *
 * Eine Datei kommt entweder als Bytes über den Kanal ([write]) oder liegt schon unter dem
 * Ordner, weil Dart sie dort geschrieben hat ([resolve], [adopt]); dann gehen nur Name und
 * Pfad über den Kanal.
 */
object ExportFiles {
    const val DIR = "exports"
    const val MAX_NAME_LENGTH = 255

    /** Ordner für die Kopie einer geöffneten Datei (Reimport, WP12); nicht im FileProvider freigegeben. */
    const val IMPORT_DIR = "imports"

    /** Fester Name: Der Name der Quelle (Content-URI) fließt nie in einen Pfad. */
    const val IMPORT_NAME = "archive.bin"

    /** Wie `isSafeExportFileName` in core (file_handoff.dart). */
    private val SAFE_NAME = Regex("^[A-Za-z0-9-][A-Za-z0-9._-]*$")
    private val MIME_TYPE = Regex("^[a-z0-9.+-]+/[a-z0-9.+-]+$")

    /** Kein Pfadtrenner, kein `.`/`..`, keine versteckte Datei. */
    fun isSafeName(name: String): Boolean = name.length <= MAX_NAME_LENGTH && SAFE_NAME.matches(name)

    fun isMimeType(type: String): Boolean = MIME_TYPE.matches(type)

    /**
     * Ein Thread für den ganzen Prozess: Alle Schreib- und Aufräumaufträge in [DIR] laufen
     * nacheinander, auch über einen Neuaufbau der Activity hinweg. Sonst könnte das Aufräumen
     * eines noch laufenden Auftrags der alten Activity die Datei des neuen löschen.
     */
    val io: ExecutorService by lazy { Executors.newSingleThreadExecutor() }

    /**
     * Quelle einer Übergabe: genau eins von [bytes] oder [path]. Ein Pfad gilt nur, wenn er
     * nach [resolve] unter [dir] liegt und die Datei selbst [fileName] heißt (Name, den der
     * Nutzer sieht, gleich dem Namen auf der Platte); sonst `null`.
     */
    fun source(dir: File, fileName: String, bytes: ByteArray?, path: String?): HandoffSource? = when {
        bytes != null && path == null -> HandoffSource.Bytes(bytes)
        bytes == null && path != null ->
            resolve(dir, path)?.takeIf { it.name == fileName }?.let { HandoffSource.Path(it) }
        else -> null
    }

    /**
     * Öffnen einer Datei (WP12): leert [dir], legt es bei Bedarf an und kopiert [input] als
     * Strom nach [dir]/[IMPORT_NAME]; kein Zwischenpuffer im Speicher. Bei jedem Fehler wird
     * die Teilkopie entfernt und der Fehler weitergereicht. Liefert den kanonischen Pfad.
     */
    fun importInto(dir: File, input: java.io.InputStream): File {
        clear(dir)
        if (!dir.isDirectory && !dir.mkdirs()) throw IOException("mkdirs")
        val file = File(dir, IMPORT_NAME)
        try {
            input.use { i -> file.outputStream().use { o -> i.copyTo(o) } }
        } catch (e: Exception) {
            file.delete()
            throw e
        }
        return file.canonicalFile
    }

    /** Authority des FileProviders im Manifest (`${applicationId}.exports`). */
    fun authority(packageName: String): String = "$packageName.$DIR"

    /** Löscht alles in [dir]; der Ordner selbst bleibt. Liefert, ob danach nichts mehr darin liegt. */
    fun clear(dir: File): Boolean {
        dir.listFiles()?.forEach { it.deleteRecursively() }
        return dir.listFiles().isNullOrEmpty()
    }

    /**
     * Räumt [dir] auf und legt darin genau eine Datei [name] mit [bytes] an. Wirft
     * [IllegalArgumentException] bei unsicherem Namen und [java.io.IOException] bei Schreibfehlern.
     */
    fun write(dir: File, name: String, bytes: ByteArray): File {
        require(isSafeName(name)) { "unsafe_name" }
        clear(dir)
        if (!dir.isDirectory && !dir.mkdirs()) throw java.io.IOException("mkdirs")
        val file = File(dir, name)
        // Zweite Sicherung neben isSafeName: Die Datei liegt direkt im Exportordner.
        require(file.canonicalFile.parentFile == dir.canonicalFile) { "unsafe_name" }
        file.writeBytes(bytes)
        return file
    }

    /**
     * Die reguläre Datei [path] (absolut), wenn sie nach Auflösen von `..` und symbolischen
     * Links echt unterhalb von [dir] liegt; sonst `null`. Prüft nur, schreibt nichts.
     */
    fun resolve(dir: File, path: String): File? {
        val given = File(path)
        if (!given.isAbsolute) return null
        val base = try {
            dir.canonicalFile
        } catch (e: IOException) {
            return null
        }
        val file = try {
            given.canonicalFile
        } catch (e: IOException) {
            return null
        }
        if (!file.path.startsWith(base.path + File.separator)) return null
        return if (file.isFile) file else null
    }

    /**
     * Teilen einer Datei, die schon unter [dir] liegt: prüft [path] wie [resolve] und räumt
     * alles andere in [dir] auf; nur der oberste Eintrag, der die Datei enthält, bleibt.
     * Wirft [IllegalArgumentException], wenn [path] nicht zulässig ist.
     */
    fun adopt(dir: File, path: String): File {
        val file = resolve(dir, path) ?: throw IllegalArgumentException("unsafe_path")
        val base = dir.canonicalFile
        var top = file
        while (top.parentFile != base) top = top.parentFile
        base.listFiles()?.forEach { if (it != top) it.deleteRecursively() }
        return file
    }
}
