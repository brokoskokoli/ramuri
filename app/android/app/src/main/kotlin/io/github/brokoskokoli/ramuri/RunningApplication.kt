package io.github.brokoskokoli.ramuri

import android.app.Application
import android.location.LocationManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Hält die eine FlutterEngine des Prozesses (ADR-0005 Punkt 1). Die Aufzeichnung läuft
 * darin weiter, auch wenn die Activity weg ist. Prozessweite Kanäle hängen hier an der
 * Engine; Kanäle, die eine Activity brauchen (Berechtigungen), bleiben in MainActivity.
 */
class RunningApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // FR-0201: Exportdateien eines früheren Teilens aufräumen (ExportFiles); Fehler ändern nichts am Start.
        ExportFiles.clear(java.io.File(cacheDir, ExportFiles.DIR))
        // WP12: Kopie einer geöffneten Archivdatei (Chiffretext) eines früheren Laufs entfernen.
        ExportFiles.clear(java.io.File(cacheDir, ExportFiles.IMPORT_DIR))
        // Registriert die generierten Plugins selbst (automaticallyRegisterPlugins).
        val engine = FlutterEngine(this)
        registerProcessChannels(engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    private fun registerProcessChannels(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        // ADR-0003 Punkt 3: Die Datenbank liegt in getNoBackupFilesDir(), das immer vom Backup ausgenommen ist.
        MethodChannel(messenger, "ramuri/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getNoBackupFilesDir" -> result.success(noBackupFilesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        // ADR-0005 Punkt 4: GPS_PROVIDER ohne Play-Dienste.
        EventChannel(messenger, "ramuri/location_stream")
            .setStreamHandler(GpsStreamHandler(getSystemService(LocationManager::class.java)))
        RecordingServiceState.register(messenger, this)
        // FR-0202: Schrittsensor des Telefons, ohne Activity erreichbar.
        StepSensor.register(messenger, this)
        // ADR-0011: Kamera für das Kamera-PPG; das Recht fragt MainActivity erst beim Messbeginn.
        PpgCamera.register(messenger, this)
        // WP27: Ton oder Vibration am Ende der Ruhephase.
        RestingSignal.register(messenger, this)
        // FR-0174: Erinnerungen vor geplanten Einheiten, ohne Activity erreichbar.
        TrainingReminders.register(messenger, this)
    }

    companion object {
        const val ENGINE_ID = "main"
    }
}
