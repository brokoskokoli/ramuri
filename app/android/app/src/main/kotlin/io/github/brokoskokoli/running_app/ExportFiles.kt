package io.github.brokoskokoli.running_app

import java.io.File

/**
 * Exportdateien zum Teilen (FR-0201, WP11). Sie liegen in `cacheDir/exports/`: Der Cache ist
 * vom Backup ausgenommen (data_extraction_rules.xml), und nur dieser Ordner ist über den
 * FileProvider freigegeben (res/xml/file_paths.xml). Gelöscht wird beim Prozessstart und vor
 * jedem neuen Teilen, nicht direkt nach dem Teilen-Menü: Der Empfänger liest die Datei oft
 * erst später.
 */
object ExportFiles {
    const val DIR = "exports"
    const val MAX_NAME_LENGTH = 255

    /** Wie `isSafeExportFileName` in core (file_handoff.dart). */
    private val SAFE_NAME = Regex("^[A-Za-z0-9-][A-Za-z0-9._-]*$")
    private val MIME_TYPE = Regex("^[a-z0-9.+-]+/[a-z0-9.+-]+$")

    /** Kein Pfadtrenner, kein `.`/`..`, keine versteckte Datei. */
    fun isSafeName(name: String): Boolean = name.length <= MAX_NAME_LENGTH && SAFE_NAME.matches(name)

    fun isMimeType(type: String): Boolean = MIME_TYPE.matches(type)

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
}
