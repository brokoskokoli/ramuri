import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'reminder_controller.dart';

/// Schalter „Erinnerung am Morgen“ auf der Seite Morgenwerte (WP33 Teil D,
/// Design `morgen/Trend`): freiwillig, Uhrzeit wählbar (Antippen der Zeile),
/// Hinweis zum Neustart. Ohne Controller (Tests ohne Erinnerungen) leer.
class MorningReminderTile extends StatelessWidget {
  const MorningReminderTile({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ReminderScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final m = controller.morning;
    final on = controller.morningActive;
    final material = MaterialLocalizations.of(context);
    final time = material.formatTimeOfDay(
      TimeOfDay(hour: m.minuteOfDay ~/ 60, minute: m.minuteOfDay % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('morning_reminder_switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.morningReminderSwitch),
          subtitle: Text(
            on ? l10n.morningReminderOn(time) : l10n.morningReminderOff,
            key: const Key('morning_reminder_text'),
          ),
          value: on,
          onChanged: controller.loaded
              ? (v) => _guard(context, () => controller.setMorningEnabled(v))
              : null,
        ),
        if (controller.denied)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.reminderDenied,
              key: const Key('morning_reminder_denied'),
            ),
          ),
        ListTile(
          key: const Key('morning_reminder_time'),
          contentPadding: EdgeInsets.zero,
          enabled: on,
          title: Text(l10n.morningReminderTimeTitle),
          trailing: Text(time),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: m.minuteOfDay ~/ 60,
                minute: m.minuteOfDay % 60,
              ),
            );
            if (picked == null || !context.mounted) return;
            await _guard(
              context,
              () => controller.setMorningTime(picked.hour * 60 + picked.minute),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.morningReminderNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  static Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).settingsSaveFailed;
    try {
      await action();
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }
}
