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
    /** Aktueller Stand von BLUETOOTH_CONNECT; entscheidet über `connectedDevice` (ADR-0005 Punkt 2). */
    private val bluetoothConnectGranted: () -> Boolean = { false },
    /** Beendet den Dienst (`stopSelf`); nur nach `startForeground` oder nach dessen Scheitern. */
    private val stopSelf: () -> Unit = {},
    /** Ruft `startForeground` mit dem Typ auf; wirft, wenn das System ablehnt. */
    private val enterForeground: (type: Int) -> Unit,
) {
    var running: Boolean = false
        private set

    /** Typ des letzten erfolgreichen `startForeground`; null, solange der Dienst nicht im Vordergrund ist. */
    var currentType: Int? = null
        private set

    /** Ergebnis des Starts; bei Fehler ist weder Lock noch Zustand `running` übrig. */
    fun start(): Result<Unit> {
        if (running) return Result.success(Unit)
        return try {
            lock.acquire()
            val type = startType(bluetoothConnectGranted())
            enterForeground(type)
            currentType = type
            running = true
            Result.success(Unit)
        } catch (e: Throwable) {
            releaseQuietly()
            running = false
            currentType = null
            Result.failure(e)
        }
    }

    /**
     * Zieht den Typ nach, wenn BLUETOOTH_CONNECT erst nach dem Start erteilt wurde
     * (Sensor wird im Lauf eingerichtet): `startForeground` erneut mit dem vollen Typ.
     * Wirft das System, bleibt der alte Typ bestehen und der Dienst läuft weiter.
     * Gibt zurück, ob der Typ jetzt `connectedDevice` enthält.
     */
    fun retype(): Boolean {
        val old = currentType ?: return false
        val wanted = startType(bluetoothConnectGranted())
        if (wanted == old) return hasConnectedDevice(old)
        return try {
            enterForeground(wanted)
            currentType = wanted
            hasConnectedDevice(wanted)
        } catch (_: Throwable) {
            false
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
        currentType = null
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
         * Darf der Dienst gestartet werden? Ohne Standortrecht wirft `startForeground`
         * mit Typ `location` eine SecurityException, und weil `startForegroundService`
         * dann schon gelaufen ist, kann das System den Prozess beenden. Deshalb wird
         * vor `startForegroundService` geprüft und sonst gar nicht gestartet.
         */
        fun mayStart(fineLocationGranted: Boolean): Result<Unit> =
            if (fineLocationGranted) Result.success(Unit)
            else Result.failure(SecurityException("location_denied"))

        /** ADR-0005 Punkt 6: kein Neustart durch das System. */
        const val START_MODE: Int = Service.START_NOT_STICKY

        /**
         * Diensttyp (ADR-0005 Punkt 2): immer `location`, `connectedDevice` nur mit
         * BLUETOOTH_CONNECT. Ohne das Recht wirft `startForeground` mit diesem Typ
         * eine SecurityException (Android 14), deshalb dann gar nicht nennen.
         */
        fun startType(bluetoothConnectGranted: Boolean): Int =
            if (bluetoothConnectGranted) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            }

        fun hasConnectedDevice(type: Int): Boolean =
            type and ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE != 0
    }
}
