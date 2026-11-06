package io.github.brokoskokoli.running_app

import android.content.pm.ServiceInfo

/** Was [RecordingLifecycle] vom Wake Lock braucht (in Tests ersetzt). */
interface WakeLockHandle {
    val isHeld: Boolean
    fun acquire()
    fun release()
}

/**
 * Entscheidungen des Aufzeichnungsdienstes ohne Android-Objekte (JVM-testbar):
 * Typwahl und Wake Lock (ADR-0005 Punkt 2 und Konsequenz Wake Lock).
 *
 * Der Lock wird nur für die Laufdauer gehalten. Scheitert der Start an irgendeiner
 * Stelle, bleibt er nicht gehalten; stop und onDestroy geben ihn immer frei.
 */
class RecordingLifecycle(
    private val lock: WakeLockHandle,
    /** Ruft `startForeground` mit dem Typ auf; wirft, wenn das System ablehnt. */
    private val enterForeground: (type: Int) -> Unit,
) {
    var running: Boolean = false
        private set

    /** Ergebnis des Starts; bei Fehler ist weder Lock noch Zustand `running` übrig. */
    fun start(): Result<Unit> {
        if (running) return Result.success(Unit)
        return try {
            lock.acquire()
            enterForeground(startType())
            running = true
            Result.success(Unit)
        } catch (e: Throwable) {
            releaseQuietly()
            running = false
            Result.failure(e)
        }
    }

    /** Idempotent; gibt den Lock frei. */
    fun stop() {
        running = false
        releaseQuietly()
    }

    private fun releaseQuietly() {
        try {
            if (lock.isHeld) lock.release()
        } catch (_: RuntimeException) {
            // Ein Lock, den das System schon entzogen hat, ist bereits frei.
        }
    }

    companion object {
        /**
         * Typ beim Start: nur `location`. `connectedDevice` kommt mit dem
         * Pulssensor im Dienst und nur mit BLUETOOTH_CONNECT (WP08 Teil C).
         */
        fun startType(): Int = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
    }
}
