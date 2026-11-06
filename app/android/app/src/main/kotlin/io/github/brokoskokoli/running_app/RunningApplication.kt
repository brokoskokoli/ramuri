package io.github.brokoskokoli.running_app

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
        // Registriert die generierten Plugins selbst (automaticallyRegisterPlugins).
        val engine = FlutterEngine(this)
        registerProcessChannels(engine)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    private fun registerProcessChannels(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        // ADR-0003 Punkt 3: Die Datenbank liegt in getNoBackupFilesDir(), das immer vom Backup ausgenommen ist.
        MethodChannel(messenger, "running_app/storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "getNoBackupFilesDir" -> result.success(noBackupFilesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
        // ADR-0005 Punkt 4: GPS_PROVIDER ohne Play-Dienste.
        EventChannel(messenger, "running_app/location_stream")
            .setStreamHandler(GpsStreamHandler(getSystemService(LocationManager::class.java)))
        RecordingServiceState.register(messenger, this)
        // FR-0202: Schrittsensor des Telefons, ohne Activity erreichbar.
        StepSensor.register(messenger, this)
    }

    companion object {
        const val ENGINE_ID = "main"
    }
}
