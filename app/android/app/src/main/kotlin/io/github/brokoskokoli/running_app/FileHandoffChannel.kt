package io.github.brokoskokoli.running_app

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * Kanal `running_app/file_handoff` (FR-0201, WP11): Datei teilen (`ACTION_SEND` über den
 * Chooser, FileProvider mit Leserecht nur für diese URI) oder über das System-Dokumentenziel
 * speichern (`ACTION_CREATE_DOCUMENT`, Inhalt direkt in die gelieferte URI, ohne Temp-Datei).
 * Der Inhalt kommt als `bytes` oder als `path` einer Datei, die Dart schon unter dem Ordner
 * aus `exportDirectory` angelegt hat (nur dort, [ExportFiles.resolve]). Hängt an der
 * Activity, weil beide Wege einen Systemdialog starten. Geschrieben wird auf dem
 * prozessweiten Thread [ExportFiles.io], nicht auf dem Hauptthread. Antworten: "completed",
 * "cancelled" oder ein Fehler mit Code; nichts davon enthält Inhalte oder Pfade.
 */
class FileHandoffChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val flow = FileHandoffFlow(object : HandoffAnswers<MethodChannel.Result> {
        override fun success(result: MethodChannel.Result, value: String) {
            unregisterChosen()
            result.success(value)
        }
        override fun error(result: MethodChannel.Result, code: String, detail: String?) {
            // "busy": Die laufende Übergabe braucht ihren Empfänger noch.
            if (code != "busy") unregisterChosen()
            result.error(code, detail, null)
        }
    }, object : HandoffThreads {
        override fun background(work: () -> Unit) {
            ExportFiles.io.execute(work)
        }
        override fun main(work: () -> Unit) {
            mainHandler.post(work)
        }
    })
    private var chosenReceiver: BroadcastReceiver? = null

    /** Nur im Vordergrund: Ein Systemdialog aus dem Hintergrund würde nie sichtbar, und ohne Pause/Rückkehr bliebe das Teilen offen. */
    private var foreground = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "exportDirectory" -> exportDirectory(result)
                "share", "save" -> {
                    val name = call.argument<String>("fileName")
                    val type = call.argument<String>("mimeType")
                    val source = source(call.argument<ByteArray>("bytes"), call.argument<String>("path"))
                    when {
                        name == null || type == null || source == null ||
                            !ExportFiles.isSafeName(name) || !ExportFiles.isMimeType(type) ->
                            result.error("bad_arguments", null, null)
                        !foreground -> result.error("not_foreground", null, null)
                        call.method == "share" -> share(result, name, type, source)
                        else -> save(result, name, type, source)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private val exportDir: File get() = File(activity.cacheDir, ExportFiles.DIR)

    /** Genau eine Quelle; ein Pfad nur, wenn er unter dem Exportordner liegt. */
    private fun source(bytes: ByteArray?, path: String?): HandoffSource? = when {
        bytes != null && path == null -> HandoffSource.Bytes(bytes)
        bytes == null && path != null -> ExportFiles.resolve(exportDir, path)?.let { HandoffSource.Path(it) }
        else -> null
    }

    /** Ordner, in den Dart große Dateien vor der Übergabe schreibt (absolut, kanonisch). */
    private fun exportDirectory(result: MethodChannel.Result) {
        val dir = exportDir
        if (!dir.isDirectory && !dir.mkdirs()) {
            result.error("no_directory", null, null)
            return
        }
        result.success(dir.canonicalPath)
    }

    private fun share(result: MethodChannel.Result, name: String, type: String, source: HandoffSource) {
        val dir = exportDir
        val write = when (source) {
            is HandoffSource.Bytes -> { -> ExportFiles.write(dir, name, source.bytes) }
            is HandoffSource.Path -> { -> ExportFiles.adopt(dir, source.file.path) }
        }
        flow.share(result, write = write) { file ->
            // Während des Schreibens kann die App nach hinten gegangen sein.
            if (!foreground) {
                flow.fail("not_foreground", null)
                return@share
            }
            val uri = FileProvider.getUriForFile(activity, ExportFiles.authority(activity.packageName), file)
            val spec = HandoffIntents.send(type)
            val send = Intent(spec.action).apply {
                setType(spec.mimeType)
                putExtra(Intent.EXTRA_STREAM, uri)
                // Die Freigabe gilt über ClipData auch durch den Chooser hindurch.
                clipData = ClipData.newRawUri(name, uri)
                addFlags(spec.flags)
            }
            activity.startActivity(Intent.createChooser(send, null, chosenSender()))
        }
    }

    /** Der Chooser meldet die Wahl eines Ziels per Broadcast an diesen nicht exportierten Empfänger. */
    private fun chosenSender(): android.content.IntentSender {
        unregisterChosen()
        val action = "${activity.packageName}.FILE_SHARE_CHOSEN"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) = flow.chosen()
        }
        ContextCompat.registerReceiver(activity, receiver, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED)
        chosenReceiver = receiver
        val intent = Intent(action).setPackage(activity.packageName)
        return PendingIntent.getBroadcast(
            activity,
            SHARE_REQUEST,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        ).intentSender
    }

    private fun unregisterChosen() {
        chosenReceiver?.let { activity.unregisterReceiver(it) }
        chosenReceiver = null
    }

    private fun save(result: MethodChannel.Result, name: String, type: String, source: HandoffSource) {
        if (!flow.beginSave(result, source)) return
        val spec = HandoffIntents.createDocument(name, type)
        val intent = Intent(spec.action).apply {
            spec.categories.forEach { addCategory(it) }
            setType(spec.mimeType)
            putExtra(Intent.EXTRA_TITLE, spec.title)
        }
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, SAVE_REQUEST)
        } catch (e: Exception) {
            flow.fail("save_failed", e.javaClass.simpleName)
        }
    }

    /** Aus MainActivity.onActivityResult; `true`, wenn die Antwort hierher gehört. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_REQUEST) return false
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        val resolver = activity.contentResolver
        val owned = flow.saveAnswered(uri) { target: Uri, source ->
            try {
                val out = resolver.openOutputStream(target, "wt") ?: throw IOException("no_stream")
                out.use { o ->
                    when (source) {
                        is HandoffSource.Bytes -> o.write(source.bytes)
                        is HandoffSource.Path -> source.file.inputStream().use { it.copyTo(o) }
                    }
                }
            } catch (e: Exception) {
                // Halb geschriebenes Dokument nicht liegen lassen.
                runCatching { DocumentsContract.deleteDocument(resolver, target) }
                throw e
            }
        }
        // Kein Speichern offen (Activity neu erzeugt, Prozess im Dokumentenziel beendet): Das
        // System hat das Dokument schon leer angelegt, Dart hat schon eine Antwort. Entfernen.
        if (!owned && uri != null) {
            ExportFiles.io.execute { runCatching { DocumentsContract.deleteDocument(resolver, uri) } }
        }
        return true
    }

    fun onPause() {
        foreground = false
        flow.paused()
    }

    fun onResume() {
        foreground = true
        flow.resumed()
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        flow.detached()
        unregisterChosen()
        // Laufendes Schreiben endet noch auf dem prozessweiten Thread; seine Antwort verfällt
        // im Ablauf (Generation). Der Thread bleibt für die nächste Activity.
    }

    companion object {
        const val CHANNEL = "running_app/file_handoff"
        private const val SHARE_REQUEST = 6101
        private const val SAVE_REQUEST = 6102
    }
}
