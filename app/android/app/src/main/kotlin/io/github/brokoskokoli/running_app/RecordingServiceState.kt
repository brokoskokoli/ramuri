package io.github.brokoskokoli.running_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Prozessweiter Stand des Dienstes und sein Kanal `running_app/recording_service`
 * (start, stop, isRunning). Alles läuft auf dem Hauptthread. Nach einem
 * Prozessende ist [running] falsch, also `false`: Daran erkennt WP08 Teil B einen
 * Lauf ohne Dienst.
 */
object RecordingServiceState {
    const val CHANNEL = "running_app/recording_service"
    private const val START_TIMEOUT_MS = 5000L

    @Volatile
    var running: Boolean = false
        private set
    private var pending: MutableList<MethodChannel.Result> = mutableListOf()
    private val handler = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var service: RecordingService? = null

    fun attach(s: RecordingService) { service = s }
    fun detach(s: RecordingService) { if (service === s) service = null }
    /**
     * Stopp-Wunsch vor dem Vordergrund. Der Dienst wird nach `startForegroundService`
     * nie von außen beendet, bevor er `startForeground` erreicht hat (Absturz des
     * Prozesses); er liest den Wunsch in `onStartCommand` und beendet sich danach.
     */
    private var stopRequested = false
    private val timeout = Runnable {
        // Ein später doch gestarteter Dienst bliebe sonst ohne Dart-Gegenstück laufen.
        stopRequested = true
        failed(IllegalStateException("start_timeout"))
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRunning" -> result.success(running)
                // Sensor im Lauf verbunden: Typ connectedDevice nachziehen, wenn BLUETOOTH_CONNECT da ist.
                "updateType" -> result.success(service?.retype() ?: false)
                "start" -> start(context, result)
                "stop" -> {
                    stop(context)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start(context: Context, result: MethodChannel.Result) {
        if (running) {
            result.success(null)
            return
        }
        // Vor startForegroundService: danach lässt sich ein Scheitern von
        // startForeground nicht mehr abfangen (siehe RecordingLifecycle.mayStart).
        val allowed = RecordingLifecycle.mayStart(
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                PackageManager.PERMISSION_GRANTED,
        )
        if (allowed.isFailure) {
            result.error("start_failed", allowed.exceptionOrNull()?.javaClass?.simpleName, null)
            return
        }
        val first = pending.isEmpty()
        pending.add(result)
        if (!first) return
        stopRequested = false
        try {
            context.startForegroundService(Intent(context, RecordingService::class.java))
            handler.postDelayed(timeout, START_TIMEOUT_MS)
        } catch (e: RuntimeException) {
            failed(e)
        }
    }

    private fun stop(context: Context) {
        if (pending.isNotEmpty()) {
            // Dienst noch nicht im Vordergrund: nicht beenden, sondern vormerken.
            stopRequested = true
            failed(IllegalStateException("start_cancelled"))
        } else if (running) {
            context.stopService(Intent(context, RecordingService::class.java))
        }
    }

    /** Liest und löscht den Stopp-Wunsch (aufgerufen in `onStartCommand`). */
    fun takeStopRequest(): Boolean {
        val r = stopRequested
        stopRequested = false
        return r
    }

    fun started() {
        running = true
        handler.removeCallbacks(timeout)
        val waiting = pending
        pending = mutableListOf()
        waiting.forEach { it.success(null) }
    }

    fun failed(e: Throwable) {
        running = false
        handler.removeCallbacks(timeout)
        val waiting = pending
        pending = mutableListOf()
        // Nur der Klassenname: keine Inhalte, keine Gesundheitsdaten.
        waiting.forEach { it.error("start_failed", e.javaClass.simpleName, null) }
    }

    fun stopped() {
        running = false
    }
}
