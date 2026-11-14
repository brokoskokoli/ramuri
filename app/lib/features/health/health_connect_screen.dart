import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'health_connect_controller.dart';

/// Texte einer Datenart (Name, Hinweis, Mehrzahl, Zusatz im Löschdialog).
class HealthKindTexts {
  const HealthKindTexts(this.label, this.hint, this.plural, this.extra);
  final String label;
  final String hint;
  final String plural;
  final String extra;

  static HealthKindTexts of(AppLocalizations l, HealthDataKind kind) =>
      switch (kind) {
        HealthDataKind.exercise => HealthKindTexts(
          l.healthExerciseLabel,
          l.healthExerciseHint,
          l.healthExercisePlural,
          l.healthExerciseExtra,
        ),
        HealthDataKind.heartRate => HealthKindTexts(
          l.healthHeartRateLabel,
          l.healthHeartRateHint,
          l.healthHeartRatePlural,
          l.healthHeartRateExtra,
        ),
        HealthDataKind.restingHeartRate => HealthKindTexts(
          l.healthRestingHeartRateLabel,
          l.healthRestingHeartRateHint,
          l.healthRestingHeartRatePlural,
          l.healthRestingHeartRateExtra,
        ),
        HealthDataKind.hrvRmssd => HealthKindTexts(
          l.healthHrvLabel,
          l.healthHrvHint,
          l.healthHrvPlural,
          l.healthHrvExtra,
        ),
        HealthDataKind.sleep => HealthKindTexts(
          l.healthSleepLabel,
          l.healthSleepHint,
          l.healthSleepPlural,
          l.healthSleepExtra,
        ),
        HealthDataKind.vo2Max => HealthKindTexts(
          l.healthVo2MaxLabel,
          l.healthVo2MaxHint,
          l.healthVo2MaxPlural,
          l.healthVo2MaxExtra,
        ),
      };
}

/// Seite „Gesundheitsdaten aus Health Connect“ (WP32 Teil C2): Einwilligung je Datenart, „Weiter zu Health Connect“,
/// letzter Abruf, Widerruf mit Löschfrage; ohne Health Connect der Zustand „nicht verfügbar“ (FR-0022, SEC-0007).
class HealthConnectScreen extends StatefulWidget {
  const HealthConnectScreen({super.key, required this.controller});

  final HealthConnectController controller;

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends State<HealthConnectScreen> {
  HealthConnectController get c => widget.controller;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    unawaited(_reload());
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    await c.load();
    if (mounted) await _askOpenQuestions();
  }

  /// Fragt der Reihe nach alle offenen Löschfragen (Recht fehlt oder Antwort stand aus).
  Future<void> _askOpenQuestions() async {
    if (_asking) return;
    _asking = true;
    try {
      for (final kind in List.of(c.questions)) {
        if (!mounted) return;
        await _ask(kind, fromSwitch: false);
      }
    } finally {
      _asking = false;
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Löschdialog der Art. [fromSwitch]: „Abbrechen“ schaltet wieder ein; sonst bleibt die Frage offen.
  Future<void> _ask(HealthDataKind kind, {required bool fromSwitch}) async {
    final l10n = AppLocalizations.of(context);
    final texts = HealthKindTexts.of(l10n, kind);
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('health_delete_dialog'),
        title: Text(l10n.healthDeleteTitle(texts.label)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.healthDeleteQuestion(texts.plural),
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(l10n.healthDeleteBody(texts.plural, texts.extra)),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('health_delete_keep'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.healthDeleteKeep),
          ),
          FilledButton(
            key: const Key('health_delete_confirm'),
            style: ramuriDangerFilledStyle(context),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.healthDeleteConfirm),
          ),
          TextButton(
            key: const Key('health_delete_cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.healthDeleteCancel),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == null) {
      if (fromSwitch) await _guard(() => c.cancelDisable(kind));
      return;
    }
    final ok = await _guard(
      () => c.answerDeleteQuestion(kind, delete: choice),
      failed: choice ? l10n.healthDeleteFailed : null,
    );
    if (ok && mounted) {
      _snack(
        choice
            ? l10n.healthDeletedSnack(texts.plural)
            : l10n.healthKeptSnack(texts.plural),
      );
    }
  }

  Future<bool> _guard(Future<void> Function() action, {String? failed}) async {
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) {
        _snack(failed ?? AppLocalizations.of(context).healthSaveFailed);
      }
      return false;
    }
  }

  Future<void> _toggle(HealthDataKind kind, bool on) async {
    if (on) {
      await _guard(() => c.enable(kind));
      return;
    }
    if (!await _guard(() => c.disable(kind)) || !mounted) return;
    await _ask(kind, fromSwitch: true);
  }

  Future<void> _fetch() async {
    final l10n = AppLocalizations.of(context);
    HealthImportResult result;
    try {
      result = await c.fetchNow();
    } catch (_) {
      if (mounted) _snack(l10n.healthFetchPartial);
      return;
    }
    if (!mounted) return;
    _snack(switch (result.status) {
      HealthImportStatus.unavailable => l10n.healthFetchUnavailable,
      HealthImportStatus.alreadyRunning => l10n.healthFetchBusy,
      HealthImportStatus.throttled => l10n.healthFetchDone,
      HealthImportStatus.done =>
        result.kinds.values.any((k) => k.status == HealthKindStatus.failed)
            ? l10n.healthFetchPartial
            : result.kinds.values.any(
                (k) =>
                    k.status == HealthKindStatus.imported ||
                    k.status == HealthKindStatus.permissionMissing,
              )
            ? l10n.healthFetchDone
            : l10n.healthFetchNothing,
    });
    await _askOpenQuestions();
  }

  String _lastText(AppLocalizations l10n) {
    final last = c.lastImport;
    if (last == null) return l10n.healthLastNever;
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale).format(last);
    final now = c.clock.now().toLocal();
    final sameDay =
        last.year == now.year && last.month == now.month && last.day == now.day;
    return sameDay
        ? l10n.healthLastToday(time)
        : l10n.healthLastOn(DateFormat.yMMMd(locale).format(last), time);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.healthTitle)),
      body: !c.loaded
          ? const Center(child: CircularProgressIndicator())
          : c.sdk == HealthSdkStatus.available
          ? _main(context, l10n)
          : _unavailable(context, l10n),
    );
  }

  Widget _info(BuildContext context, String title, String body) {
    final colors = RamuriColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_rounded, size: 20, color: colors.action),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _work(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(
          Icons.check_rounded,
          size: 20,
          color: RamuriColors.of(context).action,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );

  Widget _main(BuildContext context, AppLocalizations l10n) {
    final colors = RamuriColors.of(context);
    final theme = Theme.of(context);
    final count = c.enabled.length;
    final missing = c.enabled.any((k) => !c.permitted.contains(k));
    return ListView(
      key: const Key('health_main'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        RamuriCard(
          child: Column(
            children: [
              _info(
                context,
                l10n.healthInfoReadOnlyTitle,
                l10n.healthInfoReadOnlyBody,
              ),
              _info(
                context,
                l10n.healthInfoForegroundTitle,
                l10n.healthInfoForegroundBody,
              ),
              _info(
                context,
                l10n.healthInfoLocalTitle,
                l10n.healthInfoLocalBody,
              ),
              _info(
                context,
                l10n.healthInfoRevokeTitle,
                l10n.healthInfoRevokeBody,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionHeading(l10n.healthKindsHeading, eyebrow: true),
        const SizedBox(height: 8),
        RamuriCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              for (final kind in HealthDataKind.values)
                SwitchListTile(
                  key: Key('health_switch_${kind.key}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    HealthKindTexts.of(l10n, kind).label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    HealthKindTexts.of(l10n, kind).hint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  value: c.enabled.contains(kind),
                  onChanged: (v) => _toggle(kind, v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        RamuriPrimaryButton(
          key: const Key('health_continue'),
          label: l10n.healthContinue,
          onPressed: count == 0 ? null : () => c.requestRights(),
        ),
        const SizedBox(height: 8),
        Text(
          count == 0
              ? l10n.healthContinueNone
              : missing
              ? '${l10n.healthRightsMissing} ${l10n.healthContinueHint(count)}'
              : l10n.healthContinueHint(count),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 20),
        RamuriCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.healthLastLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _lastText(l10n),
                      key: const Key('health_last'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              RamuriSecondaryButton(
                key: const Key('health_fetch'),
                icon: Icons.refresh_rounded,
                label: l10n.healthFetchNow,
                onPressed: c.fetching ? null : _fetch,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _unavailable(BuildContext context, AppLocalizations l10n) {
    final colors = RamuriColors.of(context);
    final theme = Theme.of(context);
    final install = c.sdk == HealthSdkStatus.updateRequired;
    final works = [
      l10n.healthWorks1,
      l10n.healthWorks2,
      l10n.healthWorks3,
      l10n.healthWorks4,
    ];
    return ListView(
      key: Key(
        install
            ? 'health_unavailable_install'
            : 'health_unavailable_unsupported',
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        RamuriCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.heart_broken_outlined,
                size: 32,
                color: colors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                install
                    ? l10n.healthUnavailableInstallTitle
                    : l10n.healthUnavailableUnsupportedTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                install
                    ? l10n.healthUnavailableInstallBody
                    : l10n.healthUnavailableUnsupportedBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        RamuriCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.healthWorksTitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final w in works) _work(context, w),
            ],
          ),
        ),
        const SizedBox(height: 24),
        RamuriSecondaryButton(
          key: const Key('health_without'),
          label: l10n.healthWithout,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
