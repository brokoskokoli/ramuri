import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'profile_messages.dart';

/// Eingabeformular für das Profil (FR-0002): alle Felder leer lassbar, Prüfung
/// und Speichern über [ProfileService] aus `core`. Die HFmax-Zeile zeigt, ob
/// der Wert eingegeben oder nur eine Schätzung ist (FR-0003 bis FR-0005,
/// CON-0009).
class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.service,
    required this.clock,
    required this.onSaved,
  });

  final ProfileService service;
  final Clock clock;

  /// Nach erfolgreichem Speichern (auch mit Hinweisen).
  final void Function(ProfileValidation validation) onSaved;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _birthYear = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _resting = TextEditingController();
  final _max = TextEditingController();
  final _weekly = TextEditingController();
  final _usual = TextEditingController();
  int _days = 0;
  bool _loaded = false;
  bool _loadFailed = false;
  bool _saving = false;
  ProfileValidation? _validation;
  final Set<TextEditingController> _unreadable = {};
  String? _banner;
  String? _savedNote;

  List<TextEditingController> get _all => [
    _birthYear,
    _weight,
    _height,
    _resting,
    _max,
    _weekly,
    _usual,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(_changed);
    }
    _load();
  }

  Future<void> _load() async {
    final ProfileRecord p;
    try {
      p = await widget.service.load();
    } on StorageException {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _birthYear.text = p.birthYear?.toString() ?? '';
      _weight.text = _formatDecimal(p.bodyWeightKg);
      _height.text = _formatDecimal(
        p.bodyHeightMeters == null ? null : p.bodyHeightMeters! * 100,
      );
      _resting.text = p.restingHeartRateBpm?.toString() ?? '';
      _max.text = p.maxHeartRateBpm?.toString() ?? '';
      _weekly.text = p.weeklyRunMinutes?.toString() ?? '';
      _usual.text = p.usualTrainingMinutes?.toString() ?? '';
      _days = p.trainingDaysMask ?? 0;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (_loaded && mounted) setState(() {});
  }

  /// Ganze Zahlen ohne Nachkomma, sonst höchstens zwei Stellen.
  static String _formatDecimal(double? v) {
    if (v == null) return '';
    final rounded = double.parse(v.toStringAsFixed(2));
    return rounded == rounded.roundToDouble()
        ? rounded.toInt().toString()
        : rounded.toString();
  }

  /// `null` bei leerem Feld; ein Text, der keine Zahl ist, kommt in [bad].
  int? _int(TextEditingController c, List<TextEditingController> bad) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) bad.add(c);
    return v;
  }

  double? _double(TextEditingController c, List<TextEditingController> bad) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) bad.add(c);
    return v;
  }

  ProfileRecord _record(List<TextEditingController> bad) {
    final height = _double(_height, bad);
    return ProfileRecord(
      birthYear: _int(_birthYear, bad),
      bodyWeightKg: _double(_weight, bad),
      bodyHeightMeters: height == null ? null : height / 100,
      restingHeartRateBpm: _int(_resting, bad),
      maxHeartRateBpm: _int(_max, bad),
      weeklyRunMinutes: _int(_weekly, bad),
      trainingDaysMask: _days == 0 ? null : _days,
      usualTrainingMinutes: _int(_usual, bad),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final bad = <TextEditingController>[];
    final record = _record(bad);
    if (bad.isNotEmpty) {
      setState(() {
        _unreadable
          ..clear()
          ..addAll(bad);
        _validation = null;
        _banner = l10n.profileCheckInput;
        _savedNote = null;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await widget.service.save(record);
      if (!mounted) return;
      setState(() {
        _unreadable.clear();
        _validation = result.validation;
        _banner = result.saved ? null : l10n.profileCheckInput;
        // Gespeichert mit Hinweisen: bleibt stehen, die Snackbar allein verfliegt.
        _savedNote = result.saved && result.validation.hints.isNotEmpty
            ? l10n.profileSavedCheckHints
            : null;
      });
      if (result.saved) widget.onSaved(result.validation);
    } on StorageException {
      if (mounted) {
        setState(() {
          _banner = l10n.profileSaveFailed;
          _savedNote = null;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Bei abgelehntem Feld nur die Ablehnungen: Hinweise zu Werten, die nicht
  /// gespeichert werden, wären irreführend.
  String? _issueText(ProfileField field, AppLocalizations l10n) {
    final all = _validation?.issues ?? const <ProfileIssue>[];
    final issues = _isRejected(field) ? _validation!.rejections : all;
    final texts = issues
        .where((i) => i.field == field)
        .map((i) => profileIssueText(l10n, i))
        .toList();
    return texts.isEmpty ? null : texts.join('\n');
  }

  bool _isRejected(ProfileField field) =>
      _validation?.rejections.any((i) => i.field == field) ?? false;

  Widget _field(
    String key,
    TextEditingController controller,
    String label,
    AppLocalizations l10n, {
    ProfileField? field,
    bool decimal = false,
  }) {
    final issue = field == null ? null : _issueText(field, l10n);
    final unreadable = _unreadable.contains(controller);
    final rejected = unreadable || (field != null && _isRejected(field));
    final errorMessage = unreadable
        ? l10n.profileNotANumber
        : (rejected ? issue : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key(key),
        controller: controller,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          // Ablehnung als Fehler, Hinweis nur als Hilfetext (gespeichert).
          // Als Widget statt errorText: errorText kürzt bei null Zeilen mit
          // "..." und bei fester Zeilenzahl irgendwann ebenfalls; die Meldung
          // muss auch bei großer Schrift vollständig lesbar bleiben.
          error: errorMessage == null
              ? null
              : Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
          // Hinweis wie der Fehler als Widget ohne Zeilengrenze: "Bitte prüfen."
          // am Ende darf bei großer Schrift nicht fehlen.
          helper: rejected || issue == null ? null : Text(issue),
        ),
      ),
    );
  }

  /// Aktuelle Auflösung der HFmax aus dem Formularstand (nur Anzeige).
  Widget _heartRateInfo(AppLocalizations l10n) {
    final bad = <TextEditingController>[];
    final record = _record(bad);
    final resolved = resolveHeartRate(
      record,
      currentYear: widget.clock.now().year,
    );
    final theme = Theme.of(context);
    final max = resolved.basis.maxBpm;
    final lines = <Widget>[
      switch (resolved.maxSource) {
        MaxHeartRateSource.entered => Text(
          l10n.hrEntered(max!),
          key: const Key('hr_info'),
        ),
        MaxHeartRateSource.estimated => Text(
          l10n.hrEstimated(max!),
          key: const Key('hr_info'),
        ),
        MaxHeartRateSource.missing => Text(
          l10n.hrMissing,
          key: const Key('hr_info'),
        ),
      },
      if (resolved.maxSource == MaxHeartRateSource.estimated)
        Text(l10n.hrEstimatedNote, key: const Key('hr_estimated_note')),
      if (resolved.maxSource != MaxHeartRateSource.missing &&
          resolved.askForInputOrCheck)
        Text(l10n.hrDependentUnavailable, key: const Key('hr_unavailable')),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in lines)
              Padding(padding: const EdgeInsets.only(bottom: 4), child: w),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_loadFailed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.profileLoadFailed, key: const Key('profile_load_failed')),
          TextButton(
            key: const Key('profile_load_retry'),
            onPressed: () {
              setState(() => _loadFailed = false);
              _load();
            },
            child: Text(l10n.notOpenableRetry),
          ),
        ],
      );
    }
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final dayNames = [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          'profile_birthYear',
          _birthYear,
          l10n.profileBirthYear,
          l10n,
          field: ProfileField.birthYear,
        ),
        _field(
          'profile_weight',
          _weight,
          l10n.profileWeight,
          l10n,
          field: ProfileField.bodyWeight,
          decimal: true,
        ),
        _field(
          'profile_height',
          _height,
          l10n.profileHeight,
          l10n,
          field: ProfileField.bodyHeight,
          decimal: true,
        ),
        _field(
          'profile_resting',
          _resting,
          l10n.profileRestingHr,
          l10n,
          field: ProfileField.restingHeartRate,
        ),
        _field(
          'profile_max',
          _max,
          l10n.profileMaxHr,
          l10n,
          field: ProfileField.maxHeartRate,
        ),
        _heartRateInfo(l10n),
        _field('profile_weekly', _weekly, l10n.profileWeeklyMinutes, l10n),
        Text(
          l10n.profileTrainingDays,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < 7; i++)
              FilterChip(
                key: Key('profile_day_$i'),
                label: Text(dayNames[i]),
                selected: _days & (1 << i) != 0,
                onSelected: (on) => setState(
                  () => _days = on ? _days | (1 << i) : _days & ~(1 << i),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _field('profile_usual', _usual, l10n.profileUsualMinutes, l10n),
        if (_savedNote != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_savedNote!, key: const Key('profile_saved_note')),
          ),
        if (_banner != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _banner!,
              key: const Key('profile_banner'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          key: const Key('profile_save'),
          onPressed: _saving ? null : _save,
          child: Text(l10n.profileSave),
        ),
      ],
    );
  }
}
