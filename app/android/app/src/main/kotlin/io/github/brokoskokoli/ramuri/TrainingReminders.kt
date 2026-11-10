package io.github.brokoskokoli.ramuri

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lokale Erinnerungen vor geplanten Einheiten (FR-0174, WP22 Teil F). Kein Netz, keine
 * Bibliothek. Dart plant (Zeitpunkte und fertige Texte in der App-Sprache) und ersetzt
 * die Liste nach jeder Änderung; sie liegt in SharedPreferences (kein Backup,
 * allowBackup=false), damit [TrainingReminderReceiver] sie nach einem Neustart ohne Dart
 * neu planen kann. Ein Wecker zur Zeit, inexakt (setAndAllowWhileIdle, kein
 * SCHEDULE_EXACT_ALARM); beim Klingeln zeigt der Empfänger die fälligen und stellt den
 * nächsten.
 */
object TrainingReminders {
    const val CHANNEL = "ramuri/reminders"
    const val NOTIFICATION_CHANNEL_ID = "training_reminders"
    const val ACTION_FIRE = "io.github.brokoskokoli.ramuri.TRAINING_REMINDER"
    private const val PREFS = "training_reminders"
    private const val KEY_ITEMS = "items"
    private const val KEY_CHANNEL_NAME = "channel_name"
    private const val ALARM_REQUEST = 7001

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "permitted" -> result.success(permitted(app))
                    "replaceAll" -> {
                        val raw = call.argument<List<Map<String, Any?>>>("reminders") ?: emptyList()
                        replaceAll(app, call.argument<String>("channelName"), raw.map(::parse))
                        result.success(null)
                    }
                    "cancelAll" -> {
                        cancelAll(app)
                        result.success(null)
                    }
                    // Nur Debug-Build (main_debug.dart, E2E-Test): eine Erinnerung zusätzlich, gleicher Weg.
                    "debugAdd" -> if (!debuggable(app)) {
                        result.notImplemented()
                    } else {
                        val item = parse(call.argument<Map<String, Any?>>("reminder") ?: emptyMap())
                        replaceAll(app, call.argument<String>("channelName"), load(app) + item)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("failed", e.message, null)
            }
        }
    }

    /** Benachrichtigungen erlaubt (ab API 33 POST_NOTIFICATIONS, sonst Systemschalter). */
    fun permitted(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    private fun debuggable(context: Context): Boolean =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun parse(m: Map<String, Any?>): ReminderQueue.Item = ReminderQueue.Item(
        at = (m["at"] as Number).toLong(),
        title = m["title"] as String,
        body = m["body"] as String,
    )

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun load(context: Context): List<ReminderQueue.Item> {
        val raw = prefs(context).getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val a = JSONArray(raw)
            (0 until a.length()).map { i ->
                val o = a.getJSONObject(i)
                ReminderQueue.Item(o.getLong("at"), o.getString("title"), o.getString("body"))
            }
        } catch (e: org.json.JSONException) {
            emptyList()
        }
    }

    private fun save(context: Context, items: List<ReminderQueue.Item>, channelName: String?) {
        val a = JSONArray()
        for (i in items) a.put(JSONObject().put("at", i.at).put("title", i.title).put("body", i.body))
        val e = prefs(context).edit().putString(KEY_ITEMS, a.toString())
        if (!channelName.isNullOrBlank()) e.putString(KEY_CHANNEL_NAME, channelName)
        e.apply()
    }

    private fun replaceAll(context: Context, channelName: String?, items: List<ReminderQueue.Item>) {
        val split = ReminderQueue.split(items, System.currentTimeMillis())
        save(context, split.keep, channelName)
        if (!channelName.isNullOrBlank()) ensureChannel(context, channelName)
        schedule(context, split.next)
    }

    /** Storniert den Wecker, leert die Liste und entfernt gezeigte Erinnerungen ("Alles löschen"). */
    fun cancelAll(context: Context) {
        prefs(context).edit().clear().apply()
        schedule(context, null)
        val manager = context.getSystemService(NotificationManager::class.java)
        for (n in manager.activeNotifications) {
            if (n.notification.channelId == NOTIFICATION_CHANNEL_ID) manager.cancel(n.id)
        }
    }

    /** Wecker oder Neustart: fällige zeigen, abgelaufene verwerfen, nächsten Wecker stellen. */
    fun fire(context: Context) {
        val split = ReminderQueue.split(load(context), System.currentTimeMillis())
        save(context, split.keep, null)
        if (split.show.isNotEmpty() && permitted(context)) {
            val name = prefs(context).getString(KEY_CHANNEL_NAME, null)
            ensureChannel(context, name ?: context.getString(R.string.app_name))
            val manager = context.getSystemService(NotificationManager::class.java)
            for (item in split.show) manager.notify(ReminderQueue.notificationId(item), notification(context, item))
        }
        schedule(context, split.next)
    }

    private fun ensureChannel(context: Context, name: String) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(NOTIFICATION_CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    private fun notification(context: Context, item: ReminderQueue.Item): Notification {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ramuri)
            .setContentTitle(item.title)
            .setContentText(item.body)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .build()
    }

    /** Ein Wecker zur Zeit (gleiche PendingIntent-Kennung); null storniert ihn. */
    private fun schedule(context: Context, at: Long?) {
        val alarm = context.getSystemService(AlarmManager::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            Intent(context, TrainingReminderReceiver::class.java).setAction(ACTION_FIRE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        if (at == null) {
            alarm.cancel(pending)
        } else {
            // Inexakt; darf im Doze-Modus klingeln, braucht kein SCHEDULE_EXACT_ALARM.
            alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }
}
