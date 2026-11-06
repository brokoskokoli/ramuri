package io.github.brokoskokoli.running_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.PowerManager

/**
 * Foreground Service der Aufzeichnung (ADR-0005 Punkt 2). Dünn: Er hält nur
 * Prozess, Benachrichtigung und Wake Lock; die Sitzung läuft in Dart in der
 * Engine der Application. Kein Neustart (START_NOT_STICKY, ADR-0005 Punkt 6).
 * Ohne POST_NOTIFICATIONS läuft der Dienst, die Benachrichtigung ist nur nicht sichtbar.
 */
class RecordingService : Service() {
    private var lifecycle: RecordingLifecycle? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val lc = lifecycle ?: RecordingLifecycle(
            PowerLock(this),
            { stopSelf() },
            { type -> startForeground(NOTIFICATION_ID, notification(), type) },
        ).also { lifecycle = it }
        val outcome = lc.onStartCommand(RecordingServiceState.takeStopRequest())
        outcome.onSuccess { RecordingServiceState.started() }
        outcome.onFailure { RecordingServiceState.failed(it) }
        return RecordingLifecycle.START_MODE
    }

    override fun onDestroy() {
        lifecycle?.onDestroy()
        lifecycle = null
        RecordingServiceState.stopped()
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.recording_channel_name), NotificationManager.IMPORTANCE_LOW),
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.recording_notification_title))
            .setContentText(getString(R.string.recording_notification_text))
            .setContentIntent(open)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    private class PowerLock(context: Context) : WakeLockHandle {
        // Ohne Zähler: ein release gibt den Lock frei. Kein Zeitlimit: Der Lauf bestimmt die Dauer.
        @Suppress("WakelockTimeout")
        private val lock = context.getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "running_app:recording")
            .apply { setReferenceCounted(false) }

        override val isHeld: Boolean get() = lock.isHeld
        @Suppress("WakelockTimeout")
        override fun acquire() = lock.acquire()
        override fun release() = lock.release()
    }

    companion object {
        const val CHANNEL_ID = "recording"
        const val NOTIFICATION_ID = 1
    }
}
