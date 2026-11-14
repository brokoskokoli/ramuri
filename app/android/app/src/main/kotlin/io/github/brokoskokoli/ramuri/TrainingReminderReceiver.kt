package io.github.brokoskokoli.ramuri

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Wecker der Erinnerungen und Neuplanung nach Geräteneustart oder App-Update (die das
 * System die Wecker vergessen lassen). Nicht exportiert; Systembroadcasts kommen trotzdem an.
 */
class TrainingReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            TrainingReminders.ACTION_FIRE,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> TrainingReminders.fire(context)
            // Nur der Wecker der Morgen-Erinnerung, nie der Neustart (keine SEC-0009-Ausnahme).
            MorningReminder.ACTION_FIRE -> MorningReminder.fire(context, intent)
        }
    }
}
