import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../reminders/morning_reminder_tile.dart';
import 'device_info.dart';
import 'morning_trend_logic.dart';
import 'resting_widgets.dart';

/// Seite „Morgenwerte“ (Design `morgen/Trend`): Reihe liegend/sitzend dieses
/// Handys, Ruhepuls und RMSSD der letzten 14 Tage aus den zählenden Messungen,
/// 7-Tage-Mittel gestrichelt, Markierungen und Opt-in nach K-1, Morgenfenster.
/// Ohne Sichtbarkeit ([morningMeasurementReachable]) zeigt sie nichts.
class MorningTrendScreen extends StatefulWidget {
  const MorningTrendScreen({
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
  State<MorningTrendScreen> createState() => _MorningTrendScreenState();
}

class _Data {
  const _Data({
    required this.developerMode,
    required this.measurements,
    required this.window,
    required this.optIn,
    required this.device,
  });

  final bool developerMode;
  final List<MorningMeasurement> measurements;
  final MorningWindow window;
  final bool optIn;
  final DeviceInfo device;
}

const int _days = 14;

class _MorningTrendScreenState extends State<MorningTrendScreen> {
  late Future<_Data?> _future = _load();
  RestingPosture _posture = RestingPosture.lying;
  bool _failed = false;

  Future<_Data?> _load() async {
    final session = widget.session;
    if (session is! MorningStorage) return null;
    final dev = await SettingsDeveloperModeStore(
      session.settings,
      widget.clock,
    ).read();
    // Ohne Sichtbarkeit erscheint nichts, auch nichts Gespeichertes.
    if (!morningMeasurementReachable(
      developerMode: dev,
      state: widget.validationState,
    )) {
      return null;
    }
    final visible = [
      for (final e in await (session as MorningStorage).morning.list()) e.value,
    ];
    return _Data(
      developerMode: dev,
      measurements: visible,
      window: await SettingsMorningWindowStore(
        session.settings,
        widget.clock,
      ).read(),
      optIn:
          await session.settings.get(SettingKeys.morningCameraRmssdOptIn) ==
          '1',
      device: await widget.device(),
    );
  }

  void _reload() => setState(() {
    _failed = false;
    _future = _load();
  });

  Future<void> _setOptIn(bool on) async {
    try {
      await widget.session.settings.set(
        SettingKeys.morningCameraRmssdOptIn,
        on ? '1' : '0',
        at: widget.clock.now(),
      );
      _reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pickWindow(MorningWindow current) async {
    final chosen = await showDialog<MorningWindow>(
      context: context,
      builder: (_) => _WindowDialog(initial: current),
    );
    if (chosen == null || chosen == current) return;
    try {
      await SettingsMorningWindowStore(
        widget.session.settings,
        widget.clock,
      ).set(chosen);
      _reload();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    return FutureBuilder<_Data?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final dev = data?.developerMode ?? false;
        return RestingPage(
          header: Row(
            children: [
              RestingRoundButton(
                key: const Key('measure_back'),
                icon: Icons.chevron_left,
                label: l10n.measureBack,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.morningValuesTitle,
                    style: RamuriType.of(context).valueSmall,
                  ),
                ),
              ),
              if (dev)
                Text(
                  l10n.morningDevActive,
                  key: const Key('morning_dev_hint'),
                  style: Theme.of(context).textTheme.labelSmall!
                      .copyWith(color: c.textMuted),
                ),
            ],
          ),
          sections: [
            if (snapshot.hasError)
              Text(
                l10n.morningLoadFailed,
                key: const Key('morning_trend_error'),
              )
            else if (data != null)
              ..._sections(context, data),
          ],
        );
      },
    );
  }

  List<Widget> _sections(BuildContext context, _Data d) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    final now = widget.clock.now();
    final offset = widget.clock.utcOffsetAt(now);
    final marks = morningTrendMarks(
      developerMode: d.developerMode,
      posture: _posture,
      optIn: d.optIn,
      state: widget.validationState,
    );
    List<MorningDayValue> values(double? Function(MorningMeasurement) pick) =>
        morningTrendValues(
          d.measurements,
          posture: _posture,
          manufacturer: d.device.manufacturer,
          model: d.device.model,
          nowUtc: now,
          utcOffset: offset,
          pick: pick,
          days: _days,
        );
    final hr = values((m) => roundRestingHr(m.restingHrBpm));
    final rm = values((m) => m.rmssdMs);
    final valid = {for (final e in hr) e.dayIndex}.length;
    final nf1 = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 1,
    );
    final nf0 = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 0,
    );
    return [
      RamuriSegmentedToggle<RestingPosture>(
        key: const Key('morning_posture'),
        expanded: true,
        style: RamuriSegmentedStyle.soft,
        semanticLabel: l10n.morningTitle,
        selected: _posture,
        onChanged: (p) => setState(() => _posture = p),
        segments: [
          RamuriSegment(
            value: RestingPosture.lying,
            label: l10n.measurePostureLying,
          ),
          RamuriSegment(
            value: RestingPosture.sitting,
            label: l10n.measurePostureSitting,
          ),
        ],
      ),
      Text(
        l10n.morningSeriesInfo(valid),
        key: const Key('morning_series_info'),
        style: theme.bodySmall!.copyWith(color: c.textMuted),
      ),
      if (hr.isEmpty)
        Text(l10n.morningEmpty, key: const Key('morning_trend_empty')),
      if (hr.isNotEmpty) ...[
        _TrendCard(
          cardKey: const Key('morning_hr_card'),
          title: l10n.morningRestingHr,
          values: hr,
          days: _days,
          minSpan: 6,
          format: nf1,
          muted: false,
          chartLabel: l10n.morningHrChart,
          meanNote: l10n.morningMeanNote,
          mark: marks.hrInaccurate ? l10n.morningMarkInaccurate : null,
          markKey: const Key('morning_hr_mark'),
          note: marks.hrInaccurate ? l10n.morningLockedNote : null,
        ),
        _TrendCard(
          cardKey: const Key('morning_rmssd_card'),
          title: l10n.morningRmssd,
          values: rm,
          days: _days,
          minSpan: 20,
          format: nf0,
          muted: marks.rmssdLocked,
          chartLabel: l10n.morningRmssdChart,
          meanNote: l10n.morningMeanNote,
          mark: morningMarkText(l10n, marks.rmssd),
          markKey: const Key('morning_rmssd_mark'),
          note: marks.rmssdLocked ? l10n.morningLockedNote : null,
          footer: marks.optInVisible
              ? SwitchListTile(
                  key: const Key('morning_optin'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.morningOptInTitle),
                  subtitle: Text(l10n.morningMarkOptIn),
                  value: d.optIn,
                  onChanged: _setOptIn,
                )
              : null,
        ),
      ],
      RamuriCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            const MorningReminderTile(key: Key('morning_reminder_slot')),
            ListTile(
              key: const Key('morning_window'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.morningWindowTitle),
              subtitle: Text(l10n.morningWindowNote),
              trailing: Text(
                l10n.morningWindowValue(d.window.startHour, d.window.endHour),
                key: const Key('morning_window_value'),
                style: theme.labelLarge,
              ),
              onTap: () => _pickWindow(d.window),
            ),
          ],
        ),
      ),
      if (_failed)
        Text(
          l10n.morningSettingFailed,
          key: const Key('morning_setting_failed'),
          style: theme.bodySmall!.copyWith(color: c.danger),
        ),
    ];
  }
}

/// Text der Markierung des Kamera-RMSSD; `null` ohne Markierung.
String? morningMarkText(AppLocalizations l10n, MorningRmssdMark m) =>
    switch (m) {
      MorningRmssdMark.none => null,
      MorningRmssdMark.notEnabled => l10n.morningMarkNotEnabled,
      MorningRmssdMark.optIn => l10n.morningMarkOptIn,
      MorningRmssdMark.optInSitting => l10n.morningMarkOptInSitting,
      MorningRmssdMark.inaccurate => l10n.morningMarkInaccurate,
      MorningRmssdMark.notChecked => l10n.morningMarkNotChecked,
    };

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.cardKey,
    required this.title,
    required this.values,
    required this.days,
    required this.minSpan,
    required this.format,
    required this.muted,
    required this.chartLabel,
    required this.meanNote,
    required this.mark,
    required this.markKey,
    this.note,
    this.footer,
  });

  final Key cardKey;
  final String title;
  final List<MorningDayValue> values;
  final int days;
  final double minSpan;
  final NumberFormat format;
  final bool muted;
  final String Function(String low, String high) chartLabel;
  final String Function(String value) meanNote;
  final String? mark;
  final Key markKey;
  final String? note;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final last = values.isEmpty ? null : values.last.value;
    final mean = morningTrendMean(values, fromDay: days - 7);
    final nums = [for (final v in values) v.value];
    final low = nums.isEmpty ? null : nums.reduce((a, b) => a < b ? a : b);
    final high = nums.isEmpty ? null : nums.reduce((a, b) => a > b ? a : b);
    return RamuriCard(
      key: cardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(title, style: theme.titleSmall)),
              Text(
                last == null ? '–' : format.format(last),
                key: Key('${(cardKey as ValueKey<String>).value}_last'),
                style: RamuriType.of(context).valueSmall
                    .copyWith(color: muted ? c.textMuted : null),
              ),
            ],
          ),
          if (mark != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.track,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    mark!,
                    key: markKey,
                    style: theme.labelSmall!.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (nums.isEmpty)
            Text('–', style: theme.bodySmall)
          else
            Semantics(
              container: true,
              image: true,
              excludeSemantics: true,
              label: chartLabel(format.format(low!), format.format(high!)),
              child: CustomPaint(
                key: Key('${(cardKey as ValueKey<String>).value}_chart'),
                size: const Size(double.infinity, 90),
                painter: _TrendPainter(
                  values: values,
                  mean: mean,
                  days: days,
                  minSpan: minSpan,
                  line: muted ? c.textSoft : c.action,
                  dashedLine: muted,
                  meanColor: c.outlineStrong,
                  dot: muted ? c.textSoft : c.ember,
                ),
              ),
            ),
          if (mean != null) ...[
            const SizedBox(height: 8),
            Text(
              note ?? meanNote(format.format(mean)),
              style: theme.bodySmall!.copyWith(color: c.textMuted),
            ),
          ],
          ?footer,
        ],
      ),
    );
  }
}

/// Zeichnet Verlauf (Tage ohne Wert bleiben Lücken, die Linie verbindet die
/// vorhandenen), das 7-Tage-Mittel gestrichelt und den letzten Punkt.
class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.mean,
    required this.days,
    required this.minSpan,
    required this.line,
    required this.dashedLine,
    required this.meanColor,
    required this.dot,
  });

  final List<MorningDayValue> values;
  final double? mean;
  final int days;
  final double minSpan;
  final Color line;
  final bool dashedLine;
  final Color meanColor;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final v in values) v.value, ?mean];
    var lo = all.reduce((a, b) => a < b ? a : b);
    var hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    const pad = 6.0;
    double x(int d) => pad + (size.width - 2 * pad) * d / (days - 1);
    double y(double v) =>
        pad + (size.height - 2 * pad) * (1 - (v - lo) / (hi - lo));
    if (mean != null) {
      _dashed(
        canvas,
        Offset(0, y(mean!)),
        Offset(size.width, y(mean!)),
        Paint()
          ..color = meanColor
          ..strokeWidth = 1.5,
        4,
      );
    }
    final paint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 1; i < values.length; i++) {
      final a = Offset(x(values[i - 1].dayIndex), y(values[i - 1].value));
      final b = Offset(x(values[i].dayIndex), y(values[i].value));
      if (dashedLine) {
        _dashed(canvas, a, b, paint, 5);
      } else {
        canvas.drawLine(a, b, paint);
      }
    }
    final last = values.last;
    canvas.drawCircle(
      Offset(x(last.dayIndex), y(last.value)),
      5,
      Paint()..color = dot,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p, double dash) {
    final len = (b - a).distance;
    if (len == 0) return;
    final dir = (b - a) / len;
    for (double s = 0; s < len; s += dash * 2) {
      canvas.drawLine(
        a + dir * s,
        a + dir * (s + dash < len ? s + dash : len),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values ||
      old.mean != mean ||
      old.line != line ||
      old.dashedLine != dashedLine;
}

class _WindowDialog extends StatefulWidget {
  const _WindowDialog({required this.initial});

  final MorningWindow initial;

  @override
  State<_WindowDialog> createState() => _WindowDialogState();
}

class _WindowDialogState extends State<_WindowDialog> {
  late int _start = widget.initial.startHour;
  late int _end = widget.initial.endHour;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final w = MorningWindow(_start, _end);
    return AlertDialog(
      title: Text(l10n.morningWindowTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HourField(
            key: const Key('morning_window_start'),
            label: l10n.morningWindowStart,
            value: _start,
            hours: [for (var h = 0; h < 24; h++) h],
            onChanged: (h) => setState(() => _start = h),
          ),
          _HourField(
            key: const Key('morning_window_end'),
            label: l10n.morningWindowEnd,
            value: _end,
            hours: [for (var h = 1; h <= 24; h++) h],
            onChanged: (h) => setState(() => _end = h),
          ),
          if (!w.isValid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.morningWindowInvalid,
                key: const Key('morning_window_invalid'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.morningWindowCancel),
        ),
        TextButton(
          key: const Key('morning_window_save'),
          onPressed: w.isValid ? () => Navigator.of(context).pop(w) : null,
          child: Text(l10n.morningWindowSave),
        ),
      ],
    );
  }
}

class _HourField extends StatelessWidget {
  const _HourField({
    super.key,
    required this.label,
    required this.value,
    required this.hours,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> hours;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final h in hours) DropdownMenuItem(value: h, child: Text('$h')),
    ],
    onChanged: (h) {
      if (h != null) onChanged(h);
    },
  );
}
