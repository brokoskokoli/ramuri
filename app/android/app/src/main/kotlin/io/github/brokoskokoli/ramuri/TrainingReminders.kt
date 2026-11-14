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
 * Bibliothek. Dart plant (Zeitpunkte, Art-Schlüssel und die Texte je Art in der App-Sprache)
 * und ersetzt die Liste nach jeder Änderung; sie liegt in SharedPreferences (kein Backup,
 * allowBackup=false), damit [TrainingReminderReceiver] sie nach einem Neustart ohne Dart
 * neu planen kann. Bewusste Ausnahme zu SEC-0009, minimiert: je Erinnerung nur Zeitpunkt
 * und Art-Schlüssel ([ReminderQueue.encode]), dazu die planunabhängigen Texte je Art. Ein Wecker zur Zeit, inexakt (setAndAllowWhileIdle, kein
 * SCHEDULE_EXACT_ALARM); beim Klingeln zeigt der Empfänger die fälligen und stellt den
 * nächsten.
 */
object TrainingReminders {
    const val CHANNEL = "ramuri/reminders"
    const val NOTIFICATION_CHANNEL_ID = "training_reminders"
    const val ACTION_FIRE = "io.github.brokoskokoli.ramuri.TRAINING_REMINDER"
    private const val PREFS = "training_reminders"
    private const val KEY_ITEMS = "due"
    private const val KEY_LABELS = "labels"
    private const val ALARM_REQUEST = 7001

    fun register(messenger: BinaryMessenger, context: Context) {
        val app = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "permitted" -> result.success(permitted(app))
                    "replaceAll" -> {
                        val raw = call.argument<List<Map<String, Any?>>>("reminders") ?: emptyList()
                        replaceAll(app, call.argument<Map<String, Any?>>("labels"), raw.map(::parse))
                        result.success(null)
                    }
                    // Morgen-Erinnerung (WP33 Teil D): eigener Wecker und Kanal, ohne Speicher.
                    "scheduleMorning" -> {
                        MorningReminder.schedule(
                            app,
                            (call.argument<Number>("at") ?: 0).toLong(),
                            call.argument<String>("channelName") ?: "",
                            call.argument<String>("title") ?: "",
                            call.argument<String>("body") ?: "",
                        )
                        result.success(null)
                    }
                    "cancelMorning" -> {
                        MorningReminder.cancel(app)
                        result.success(null)
                    }
                    "takeLaunchTarget" -> result.success(MorningReminder.takeLaunchTarget())
                    "cancelAll" -> {
                        cancelAll(app)
                        result.success(null)
                    }
                    // Nur Debug-Build (main_debug.dart, E2E-Test): eine Erinnerung zusätzlich, gleicher Weg.
                    "debugAdd" -> if (!debuggable(app)) {
                        result.notImplemented()
                    } else {
                        val item = parse(call.argument<Map<String, Any?>>("reminder") ?: emptyMap())
                        replaceAll(app, call.argument<Map<String, Any?>>("labels"), load(app) + item)
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
        kind = m["kind"] as String,
    )

    /** Texte der App-Sprache: Kanalname, Titel und Text je Art-Schlüssel. */
    private class Labels(val channelName: String?, val title: String?, val bodies: Map<String, String>)

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun load(context: Context): List<ReminderQueue.Item> =
        ReminderQueue.decode(prefs(context).getString(KEY_ITEMS, null))

    private fun loadLabels(context: Context): Labels {
        val raw = prefs(context).getString(KEY_LABELS, null) ?: return Labels(null, null, emptyMap())
        return try {
            val o = JSONObject(raw)
            val b = o.optJSONObject("bodies")
            val bodies = b?.keys()?.asSequence()?.associateWith { b.getString(it) } ?: emptyMap()
            Labels(o.optString("channelName").ifBlank { null }, o.optString("title").ifBlank { null }, bodies)
        } catch (e: org.json.JSONException) {
            Labels(null, null, emptyMap())
        }
    }

    private fun save(context: Context, items: List<ReminderQueue.Item>, labels: Map<String, Any?>?) {
        val e = prefs(context).edit().putString(KEY_ITEMS, ReminderQueue.encode(items))
        if (labels != null) {
            val bodies = JSONObject()
            (labels["bodies"] as? Map<*, *>)?.forEach { (k, v) -> if (k is String && v is String) bodies.put(k, v) }
            e.putString(
                KEY_LABELS,
                JSONObject()
                    .put("channelName", labels["channelName"] as? String ?: "")
                    .put("title", labels["title"] as? String ?: "")
                    .put("bodies", bodies)
                    .toString(),
            )
        }
        e.apply()
    }

    private fun replaceAll(context: Context, labels: Map<String, Any?>?, items: List<ReminderQueue.Item>) {
        val split = ReminderQueue.split(items, System.currentTimeMillis())
        save(context, split.keep, labels)
        val channelName = labels?.get("channelName") as? String
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
            val labels = loadLabels(context)
            ensureChannel(context, labels.channelName ?: context.getString(R.string.app_name))
            val manager = context.getSystemService(NotificationManager::class.java)
            for (item in split.show) {
                manager.notify(ReminderQueue.notificationId(item), notification(context, item, labels))
            }
        }
        schedule(context, split.next)
    }

    private fun ensureChannel(context: Context, name: String) {
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(NOTIFICATION_CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT),
        )
    }

    private fun notification(context: Context, item: ReminderQueue.Item, labels: Labels): Notification {
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_ramuri)
            .setContentTitle(labels.title ?: context.getString(R.string.app_name))
            .setContentText(labels.bodies[item.kind])
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
