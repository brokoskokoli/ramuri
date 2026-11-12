package io.github.brokoskokoli.ramuri

/** Seiteneffekte des [RecordingServiceController] (in Tests ersetzt). */
interface ServiceEffects<R> {
    /** `startForegroundService`; darf RuntimeException werfen. */
    fun startService(mode: RecordingMode)
    fun stopService()
    fun scheduleTimeout()
    fun cancelTimeout()
    fun success(result: R)
    fun error(result: R, code: String, detail: String?)
}

/**
 * Argumente von `result.error(code, message, details)` auf dem Kanal. Dart liest `details`
 * (MethodChannelRecordingService), daher steht das Detail in beiden Feldern: Nur Klassenname
 * bzw. Grund, keine Inhalte, keine Gesundheitsdaten.
 */
fun channelErrorArgs(code: String, detail: String?): Triple<String, String?, Any?> = Triple(code, detail, detail)

/**
 * Entscheidungen hinter dem Kanal `ramuri/recording_service` ohne Android-Objekte
 * (JVM-testbar): wann gestartet wird, wann ein Stopp vorgemerkt statt ausgeführt wird,
 * wie ein Timeout endet. Alles auf dem Hauptthread. [R] ist das Antwortobjekt des Kanals.
 */
class RecordingServiceController<R>(private val fx: ServiceEffects<R>) {
    /** Nach einem Prozessende `false`: Daran erkennt WP08 Teil B einen Lauf ohne Dienst. */
    @Volatile
    var running: Boolean = false
        private set
    private var pending: MutableList<R> = mutableListOf()

    /**
     * Stopp-Wunsch vor dem Vordergrund. Der Dienst wird nach `startForegroundService`
     * nie von außen beendet, bevor er `startForeground` erreicht hat (Absturz des
     * Prozesses); er liest den Wunsch in `onStartCommand` und beendet sich danach.
     */
    private var stopRequested = false

    val hasPending: Boolean get() = pending.isNotEmpty()

    fun start(
        result: R,
        fineLocationGranted: Boolean,
        mode: RecordingMode = RecordingMode.GPS,
        activityRecognitionGranted: Boolean = false,
    ) {
        if (running) {
            fx.success(result)
            return
        }
        // Vor startForegroundService: danach lässt sich ein Scheitern von
        // startForeground nicht mehr abfangen (siehe RecordingLifecycle.mayStart).
        if (RecordingLifecycle.mayStart(mode, fineLocationGranted, activityRecognitionGranted).isFailure) {
            if (mode == RecordingMode.TREADMILL) {
                // Eigener Grund, damit die Oberfläche das Recht erklären kann (FR-0195 entsprechend).
                fx.error(result, "start_denied", "activity_recognition")
            } else {
                fx.error(result, "start_failed", SecurityException::class.java.simpleName)
            }
            return
        }
        val first = pending.isEmpty()
        pending.add(result)
        if (!first) return
        stopRequested = false
        try {
            fx.startService(mode)
            fx.scheduleTimeout()
        } catch (e: RuntimeException) {
            failed(e)
        }
    }

    fun stop() {
        if (pending.isNotEmpty()) {
            // Dienst noch nicht im Vordergrund: nicht beenden, sondern vormerken.
            stopRequested = true
            failed(IllegalStateException("start_cancelled"))
        } else if (running) {
            // Vor stopService: Ein start im Fenster bis onDestroy meldet sonst Erfolg ohne Dienst.
            running = false
            fx.stopService()
        }
    }

    /** Timeout des Starts: Ein später doch gestarteter Dienst bliebe sonst ohne Dart-Gegenstück laufen. */
    fun onTimeout() {
        stopRequested = true
        failed(IllegalStateException("start_timeout"))
    }

    /** Liest und löscht den Stopp-Wunsch (aufgerufen in `onStartCommand`). */
    fun takeStopRequest(): Boolean {
        val r = stopRequested
        stopRequested = false
        return r
    }

    fun started() {
        running = true
        fx.cancelTimeout()
        val waiting = pending
        pending = mutableListOf()
        waiting.forEach { fx.success(it) }
    }

    fun failed(e: Throwable) {
        running = false
        fx.cancelTimeout()
        val waiting = pending
        pending = mutableListOf()
        waiting.forEach { fx.error(it, "start_failed", e.javaClass.simpleName) }
    }

    fun stopped() {
        running = false
    }
}
