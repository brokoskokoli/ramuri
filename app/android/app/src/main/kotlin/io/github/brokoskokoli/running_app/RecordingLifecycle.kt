package io.github.brokoskokoli.running_app

import android.app.Service
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
    /** Beendet den Dienst (`stopSelf`); nur nach `startForeground` oder nach dessen Scheitern. */
    private val stopSelf: () -> Unit = {},
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

    /**
     * Ablauf von `onStartCommand`. Nach `startForegroundService` muss der Dienst
     * zuerst `startForeground` rufen; wird er davor beendet, stürzt der Prozess ab
     * (ActiveServices.bringDownServiceLocked: SERVICE_FOREGROUND_CRASH_MSG), und
     * der Lauf ginge mit. Deshalb beendet er sich nie vor dem Vordergrund:
     * Eine Stopp-Anfrage ([stopRequested]) wird erst danach ausgeführt.
     * Scheitert `startForeground` selbst, bleibt nur `stopSelf`; der Lock ist dann frei.
     */
    fun onStartCommand(stopRequested: Boolean): Result<Unit> {
        val outcome = start()
        if (outcome.isFailure) {
            stopSelf()
            return outcome
        }
        if (stopRequested) {
            stop()
            stopSelf()
            return Result.failure(IllegalStateException("start_cancelled"))
        }
        return outcome
    }

    /** `onDestroy` des Dienstes: Lock immer frei. */
    fun onDestroy() = stop()

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
        /** ADR-0005 Punkt 6: kein Neustart durch das System. */
        const val START_MODE: Int = Service.START_NOT_STICKY

        /**
         * Typ beim Start: nur `location`. `connectedDevice` kommt mit dem
         * Pulssensor im Dienst und nur mit BLUETOOTH_CONNECT (WP08 Teil C).
         */
        fun startType(): Int = ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
    }
}
