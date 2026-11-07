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
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Kanal `running_app/file_handoff` (FR-0201, WP11): Datei teilen (`ACTION_SEND` über den
 * Chooser, FileProvider mit Leserecht nur für diese URI) oder über das System-Dokumentenziel
 * speichern (`ACTION_CREATE_DOCUMENT`, Bytes direkt in die gelieferte URI, ohne Temp-Datei).
 * Hängt an der Activity, weil beide Wege einen Systemdialog starten. Die Bytes schreibt ein
 * eigener Hintergrundthread, nicht der Hauptthread. Antworten: "completed",
 * "cancelled" oder ein Fehler mit Code; nichts davon enthält Inhalte oder Pfade.
 */
class FileHandoffChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
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
            io.execute(work)
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
            val name = call.argument<String>("fileName")
            val type = call.argument<String>("mimeType")
            val bytes = call.argument<ByteArray>("bytes")
            when (call.method) {
                "share", "save" -> when {
                    name == null || type == null || bytes == null ||
                        !ExportFiles.isSafeName(name) || !ExportFiles.isMimeType(type) ->
                        result.error("bad_arguments", null, null)
                    !foreground -> result.error("not_foreground", null, null)
                    call.method == "share" -> share(result, name, type, bytes)
                    else -> save(result, name, type, bytes)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun share(result: MethodChannel.Result, name: String, type: String, bytes: ByteArray) {
        val dir = File(activity.cacheDir, ExportFiles.DIR)
        flow.share(result, write = { ExportFiles.write(dir, name, bytes) }) { file ->
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

    private fun save(result: MethodChannel.Result, name: String, type: String, bytes: ByteArray) {
        if (!flow.beginSave(result, bytes)) return
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
        flow.saveAnswered(uri) { target: Uri, bytes ->
            try {
                val out = activity.contentResolver.openOutputStream(target, "wt") ?: throw IOException("no_stream")
                out.use { it.write(bytes) }
            } catch (e: Exception) {
                // Halb geschriebenes Dokument nicht liegen lassen.
                runCatching { DocumentsContract.deleteDocument(activity.contentResolver, target) }
                throw e
            }
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
        // Laufendes Schreiben endet noch; seine Antwort verfällt im Ablauf (Generation).
        io.shutdown()
    }

    companion object {
        const val CHANNEL = "running_app/file_handoff"
        private const val SHARE_REQUEST = 6101
        private const val SAVE_REQUEST = 6102
    }
}
