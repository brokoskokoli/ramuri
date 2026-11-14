package io.github.brokoskokoli.ramuri

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

/**
 * Tägliche Erinnerung an die Morgenmessung (WP33 Teil D). Eigener Wecker (inexakt, kein
 * SCHEDULE_EXACT_ALARM) und eigener Kanal, Text ohne Werte. Bewusst OHNE eigenen Speicher
 * (kein SharedPreferences) und OHNE Neuplanung nach Neustart: Zeit und Texte stecken nur als
 * Extras im Wecker-Intent, den das System beim Neustart verwirft; die App plant die Erinnerung
 * beim Öffnen aus der verschlüsselten Datenbank neu. Damit gibt es keine neue SEC-0009-Ausnahme;
 * [TrainingReminderReceiver] ruft [fire] nur für [ACTION_FIRE] auf, nie für Neustart oder Update.
 */
object MorningReminder {
    const val NOTIFICATION_CHANNEL_ID = "morning_reminders"
    const val ACTION_FIRE = "io.github.brokoskokoli.ramuri.MORNING_REMINDER"
    const val EXTRA_OPEN = "ramuri_open"
    const val TARGET_MORNING = "morning"
    private const val ALARM_REQUEST = 7002
    private const val NOTIFICATION_ID = 7002

    /** Was das Tippen auf die Benachrichtigung verlangt hat; wird mit dem Lesen gelöscht. */
    @Volatile
    private var launchTarget: String? = null

    /** Von der Activity beim Start und bei neuem Intent. */
    fun onActivityIntent(intent: Intent?) {
        if (intent?.getStringExtra(EXTRA_OPEN) == TARGET_MORNING) {
            launchTarget = TARGET_MORNING
            intent.removeExtra(EXTRA_OPEN)
        }
    }

    fun takeLaunchTarget(): String? {
        val t = launchTarget
        launchTarget = null
        return t
    }

    fun schedule(context: Context, at: Long, channelName: String, title: String, body: String) {
        val pending = pending(context, at, channelName, title, body)
        // Inexakt; darf im Doze-Modus klingeln.
        context.getSystemService(AlarmManager::class.java)
            .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(pending(context, 0, "", "", ""))
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    /** Wecker: zeigen und den nächsten Tag stellen (gleiche Uhrzeit, Ortszeit). */
    fun fire(context: Context, intent: Intent) {
        val at = intent.getLongExtra("at", 0L)
        val channelName = intent.getStringExtra("channelName") ?: return
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: return
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.areNotificationsEnabled()) {
            manager.createNotificationChannel(
                NotificationChannel(NOTIFICATION_CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_DEFAULT),
            )
            val open = PendingIntent.getActivity(
                context,
                ALARM_REQUEST,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra(EXTRA_OPEN, TARGET_MORNING),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            manager.notify(
                NOTIFICATION_ID,
                Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
                    .setSmallIcon(R.drawable.ic_stat_ramuri)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .setCategory(Notification.CATEGORY_REMINDER)
                    .build(),
            )
        }
        schedule(context, nextDay(at), channelName, title, body)
    }

    /** Dieselbe Ortszeit am Folgetag (Sommerzeit-fest). */
    fun nextDay(at: Long): Long = Calendar.getInstance().apply {
        timeInMillis = at
        add(Calendar.DAY_OF_YEAR, 1)
    }.timeInMillis

    private fun pending(context: Context, at: Long, channelName: String, title: String, body: String) =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            Intent(context, TrainingReminderReceiver::class.java)
                .setAction(ACTION_FIRE)
                .putExtra("at", at)
                .putExtra("channelName", channelName)
                .putExtra("title", title)
                .putExtra("body", body),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
}
