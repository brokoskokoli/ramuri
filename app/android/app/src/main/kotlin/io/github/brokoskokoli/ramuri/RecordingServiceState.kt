package io.github.brokoskokoli.ramuri

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Prozessweiter Stand des Dienstes und sein Kanal `ramuri/recording_service`
 * (start, stop, isRunning). Alles läuft auf dem Hauptthread. Nach einem
 * Prozessende ist [running] falsch, also `false`: Daran erkennt WP08 Teil B einen
 * Lauf ohne Dienst.
 */
object RecordingServiceState {
    const val CHANNEL = "ramuri/recording_service"
    private const val START_TIMEOUT_MS = 5000L

    private val handler = Handler(Looper.getMainLooper())
    private val timeout: Runnable = Runnable { controller.onTimeout() }
    private var appContext: Context? = null
    private var service: RecordingService? = null

    /** Wirkungen auf Android; die Entscheidungen liegen in [RecordingServiceController]. */
    private val effects = object : ServiceEffects<MethodChannel.Result> {
        override fun startService() {
            val c = appContext ?: throw IllegalStateException("no_context")
            c.startForegroundService(Intent(c, RecordingService::class.java))
        }
        override fun stopService() {
            val c = appContext ?: return
            c.stopService(Intent(c, RecordingService::class.java))
        }
        override fun scheduleTimeout() { handler.postDelayed(timeout, START_TIMEOUT_MS) }
        override fun cancelTimeout() { handler.removeCallbacks(timeout) }
        override fun success(result: MethodChannel.Result) = result.success(null)
        // Detail nur der Klassenname: keine Inhalte, keine Gesundheitsdaten.
        override fun error(result: MethodChannel.Result, code: String, detail: String?) = result.error(code, detail, null)
    }
    private val controller: RecordingServiceController<MethodChannel.Result> = RecordingServiceController(effects)

    val running: Boolean get() = controller.running

    fun attach(s: RecordingService) { service = s }
    fun detach(s: RecordingService) { if (service === s) service = null }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isRunning" -> result.success(running)
                // Sensor im Lauf verbunden: Typ connectedDevice nachziehen, wenn BLUETOOTH_CONNECT da ist.
                "updateType" -> result.success(service?.retype() ?: false)
                "start" -> controller.start(
                    result,
                    context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
                        PackageManager.PERMISSION_GRANTED,
                )
                "stop" -> {
                    controller.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun takeStopRequest(): Boolean = controller.takeStopRequest()
    fun started() = controller.started()
    fun failed(e: Throwable) = controller.failed(e)
    fun stopped() = controller.stopped()
}
