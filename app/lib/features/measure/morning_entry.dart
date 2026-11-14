import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'device_info.dart';
import 'morning_launcher.dart';
import 'morning_measure_controller.dart';
import 'morning_result_view.dart';
import 'resting_measure_launcher.dart';

/// Was die Einstiege (Karte auf Heute, Eintrag im Profil) wissen müssen.
class MorningEntryState {
  const MorningEntryState({
    required this.developerMode,
    required this.measurements,
  });

  /// Entwicklermodus an (nur für den unauffälligen Hinweis).
  final bool developerMode;
  final List<MorningMeasurement> measurements;
}

/// Lädt Entwicklermodus und Messungen; `null`, wenn die Morgenmessung nicht
/// erreichbar ist ([morningMeasurementReachable]: Entwicklermodus oder lnRMSSD
/// liegend „bestanden“), kein Speicher für Morgenmessungen da ist oder das
/// Laden scheitert (dann fehlt der Einstieg still).
Future<MorningEntryState?> loadMorningEntry({
  required StorageSession session,
  required Clock clock,
  Map<ValidationQuantity, ValidationState> validationState = ppgValidationState,
}) async {
  if (session is! MorningStorage) return null;
  try {
    final dev = await SettingsDeveloperModeStore(
      session.settings,
      clock,
    ).read();
    if (!morningMeasurementReachable(
      developerMode: dev,
      state: validationState,
    )) {
      return null;
    }
    return MorningEntryState(
      developerMode: dev,
      measurements: [
        for (final e in await (session as MorningStorage).morning.list())
          e.value,
      ],
    );
  } catch (_) {
    return null;
  }
}

/// Öffnet die Morgenmessung über der aktuellen Seite; mit der Kamera aus dem
/// [PpgCameraScope]. Ohne Kamera passiert nichts (es gibt dann auch keinen
/// Einstieg).
Future<void> openMorningMeasurement(
  BuildContext context, {
  required StorageSession session,
  required Clock clock,
  Map<ValidationQuantity, ValidationState> validationState = ppgValidationState,
  DeviceInfoReader device = readDeviceInfo,
  MorningMeasureHooks hooks = const MorningMeasureHooks(),
}) async {
  final camera = PpgCameraScope.maybeOf(context);
  if (camera == null || session is! MorningStorage) return;
  final evaluate = PpgCameraScope.evaluateOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MorningMeasureHost(
        camera: camera,
        store: (session as MorningStorage).morning,
        settings: session.settings,
        clock: clock,
        evaluate: evaluate,
        device: device,
        hooks: hooks,
        validationState: validationState,
      ),
    ),
  );
}

/// Karte „Morgenmessung“ auf Heute (Design `morgen/Heute`): offen mit „Jetzt
/// messen“, oder die heutige Messung mit Ruhepuls und RMSSD. Erscheint nur,
/// wenn die Morgenmessung erreichbar ist und eine Kamera da ist; sonst
/// nichts. Im Entwicklermodus steht ein unauffälliger Hinweis darin.
class MorningCard extends StatefulWidget {
  const MorningCard({
    super.key,
    required this.session,
    required this.clock,
    this.validationState = ppgValidationState,
    this.device = readDeviceInfo,
  });

  final StorageSession session;
  final Clock clock;
  final Map<ValidationQuantity, ValidationState> validationState;
  final DeviceInfoReader device;

  @override
  State<MorningCard> createState() => _MorningCardState();
}

class _MorningCardState extends State<MorningCard> {
  late Future<MorningEntryState?> _future = _load();

  Future<MorningEntryState?> _load() => loadMorningEntry(
    session: widget.session,
    clock: widget.clock,
    validationState: widget.validationState,
  );

  Future<void> _open() async {
    await openMorningMeasurement(
      context,
      session: widget.session,
      clock: widget.clock,
      validationState: widget.validationState,
      device: widget.device,
    );
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    if (PpgCameraScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<MorningEntryState?>(
      future: _future,
      builder: (context, snapshot) {
        final st = snapshot.data;
        if (st == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _build(context, st),
        );
      },
    );
  }

  Widget _build(BuildContext context, MorningEntryState st) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    final now = widget.clock.now();
    final offset = widget.clock.utcOffsetAt(now);
    final today = st.measurements.where(
      (m) => !morningRepeatAllowed([m], nowUtc: now, utcOffset: offset),
    );
    final done = today.isEmpty ? null : today.first;
    return RamuriCard(
      key: const Key('morning_card'),
      tone: RamuriCardTone.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(l10n.morningTitle, style: theme.titleMedium),
          ),
          const SizedBox(height: 6),
          if (done == null) ...[
            Text(
              l10n.morningCardOpen,
              key: const Key('morning_card_open'),
              style: theme.bodyMedium,
            ),
            const SizedBox(height: 12),
            RamuriPrimaryButton(
              key: const Key('morning_card_start'),
              label: l10n.morningCardStart,
              onPressed: _open,
            ),
          ] else ...[
            Text(
              morningWhenLabel(l10n, locale, done),
              key: const Key('morning_card_when'),
              style: theme.labelMedium!.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: l10n.morningRestingHr,
                    value: morningHrText(locale, done.restingHrBpm),
                    valueKey: const Key('morning_card_hr'),
                  ),
                ),
                Expanded(
                  child: _Figure(
                    label: l10n.morningRmssd,
                    value: done.rmssdMs == null
                        ? '–'
                        : done.rmssdMs!.round().toString(),
                    valueKey: const Key('morning_card_rmssd'),
                  ),
                ),
              ],
            ),
          ],
          if (st.developerMode) ...[
            const SizedBox(height: 10),
            Text(
              l10n.morningDevActive,
              key: const Key('morning_dev_hint'),
              style: theme.labelSmall!.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelSmall),
        Text(value, key: valueKey, style: t.headlineMedium),
      ],
    );
  }
}

/// Eintrag „Morgenmessung“ in der Übersicht hinter dem Profil-Symbol; nur
/// unter denselben Bedingungen wie die Karte auf Heute.
class MorningTile extends StatefulWidget {
  const MorningTile({
    super.key,
    required this.session,
    required this.clock,
    this.enabled = true,
    this.validationState = ppgValidationState,
    this.device = readDeviceInfo,
  });

  final StorageSession session;
  final Clock clock;
  final bool enabled;
  final Map<ValidationQuantity, ValidationState> validationState;
  final DeviceInfoReader device;

  @override
  State<MorningTile> createState() => _MorningTileState();
}

class _MorningTileState extends State<MorningTile> {
  late final Future<MorningEntryState?> _future = loadMorningEntry(
    session: widget.session,
    clock: widget.clock,
    validationState: widget.validationState,
  );

  @override
  Widget build(BuildContext context) {
    if (PpgCameraScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<MorningEntryState?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.data == null) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return ListTile(
          key: const Key('overview_morning'),
          leading: const Icon(Icons.wb_twilight_rounded),
          title: Text(l10n.morningTitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          enabled: widget.enabled,
          onTap: widget.enabled
              ? () => openMorningMeasurement(
                  context,
                  session: widget.session,
                  clock: widget.clock,
                  validationState: widget.validationState,
                  device: widget.device,
                )
              : null,
        );
      },
    );
  }
}
