import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/section_heading.dart';
import 'reminder_controller.dart';

/// Einstellungen der Erinnerungen (FR-0174): Schalter, Trainingszeit und
/// Vorlauf. Die Berechtigung fragt erst das Einschalten; abgelehnt bleibt der
/// Schalter aus und der Abschnitt erklärt es.
class ReminderSection extends StatelessWidget {
  const ReminderSection({super.key, required this.controller});

  final ReminderController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = controller.settings;
    final active = controller.active;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: s.hour, minute: s.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(l10n.reminderSection),
        const SizedBox(height: 12),
        RamuriCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('reminder_switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.reminderSwitch),
                value: active,
                onChanged: controller.loaded
                    ? (on) => _guard(context, () => controller.setEnabled(on))
                    : null,
              ),
              if (controller.denied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l10n.reminderDenied,
                    key: const Key('reminder_denied'),
                  ),
                ),
              ListTile(
                key: const Key('reminder_time'),
                contentPadding: EdgeInsets.zero,
                enabled: active,
                title: Text(l10n.reminderTime),
                trailing: Text(time),
                onTap: () => _pickTime(context, s),
              ),
              const SizedBox(height: 4),
              Text(l10n.reminderLead),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                key: const Key('reminder_lead'),
                segments: [
                  for (final m in ReminderSettings.leadOptions)
                    ButtonSegment(
                      value: m,
                      label: Text(l10n.reminderLeadOption(m)),
                    ),
                ],
                selected: {s.leadMinutes},
                onSelectionChanged: active
                    ? (v) => _guard(context, () => controller.setLead(v.first))
                    : null,
              ),
              const SizedBox(height: 12),
              Text(l10n.reminderNote),
              if (controller.debugAdd != null) ...[
                const SizedBox(height: 8),
                // Nur Debug-Einstieg (main_debug.dart), für den E2E-Test.
                TextButton(
                  key: const Key('reminder_debug_fire'),
                  onPressed: controller.debugFireSoon,
                  child: const Text('Debug: reminder in 10 s'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickTime(BuildContext context, ReminderSettings s) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
    );
    if (picked == null || !context.mounted) return;
    await _guard(
      context,
      () => controller.setTime(picked.hour * 60 + picked.minute),
    );
  }

  Future<void> _guard(
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
