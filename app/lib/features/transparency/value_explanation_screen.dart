import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/ramuri_type.dart';
import '../../ui/section_heading.dart';
import '../settings/unit_format.dart';
import '../statistics/fitness_section.dart' show reasonText;
import 'quality_text.dart';

/// Schlüssel für die Quellen eines Laufs (SEC-0005); kein gespeicherter Wert.
const String runSourcesKey = 'run_sources';

/// Schlüssel der Einordnung (kein gespeicherter Wert, aus den Läufen gerechnet).
const String classificationKey = 'classification';

/// Öffnet die Erklärung eines Werts (FR-0059): [runId] für Laufwerte, [day] für
/// Tageswerte. Die Einordnung und die Quellen eines Laufs haben eigene Schlüssel
/// ([classificationKey] mit [classification], [runSourcesKey] mit [runId]).
Future<void> showValueExplanation(
  BuildContext context,
  StorageSession session, {
  required String valueKey,
  int? runId,
  String? day,
  RunClassification? classification,
  UnitFormatter? formatter,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ValueExplanationScreen(
      session: session,
      valueKey: valueKey,
      runId: runId,
      day: day,
      classification: classification,
      formatter: formatter,
    ),
  ),
);

/// Tippziel „Wie entsteht dieser Wert?“ für Zusammenfassung, Detail und
/// Statistik.
class ExplainButton extends StatelessWidget {
  const ExplainButton({
    super.key,
    required this.id,
    required this.onPressed,
    this.label,
  });

  /// Schlüssel der Schaltfläche (nicht des umgebenden Streifens).
  final String id;

  final VoidCallback onPressed;
  final String? label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: TextButton(
      key: Key(id),
      onPressed: onPressed,
      child: Text(label ?? AppLocalizations.of(context).statExplain),
    ),
  );
}

enum _Kind { vo2Run, vo2LongTerm, efficiency, zones, trimp, other }

_Kind _kindOf(String key) {
  if (key == vo2maxRunValueKey) return _Kind.vo2Run;
  if (key == vo2maxLongTermValueKey) return _Kind.vo2LongTerm;
  if (key == aerobicEfficiencyValueKey) return _Kind.efficiency;
  if (key == trimpRunValueKey) return _Kind.trimp;
  if (key.startsWith('zone_time_')) return _Kind.zones;
  return _Kind.other;
}

/// Erklärung eines Werts aus den gespeicherten Angaben: die sechs Fragen aus
/// FR-0059, die Quellen (SEC-0005), bei fehlendem Wert der Grund (ACC-06) und
/// der Hinweis auf fehlende Profilwerte (FR-0055).
class ValueExplanationScreen extends StatefulWidget {
  const ValueExplanationScreen({
    super.key,
    required this.session,
    required this.valueKey,
    this.runId,
    this.day,
    this.classification,
    this.formatter,
  });

  final StorageSession session;
  final String valueKey;
  final int? runId;
  final String? day;
  final RunClassification? classification;
  final UnitFormatter? formatter;

  @override
  State<ValueExplanationScreen> createState() => _ValueExplanationScreenState();
}

class _ValueExplanationScreenState extends State<ValueExplanationScreen> {
  late final Future<ValueExplanation?> _future = _load();

  Future<ValueExplanation?> _load() async {
    if (widget.valueKey == classificationKey) return null;
    final service = ValueExplanationService(session: widget.session);
    if (widget.valueKey == runSourcesKey) {
      return service.loadSources(widget.runId!);
    }
    return service.load(widget.valueKey, runId: widget.runId, day: widget.day);
  }

  String _title(AppLocalizations l10n) => switch (_kindOf(widget.valueKey)) {
    _Kind.vo2Run => l10n.statVo2Run,
    _Kind.vo2LongTerm => l10n.statVo2Current,
    _Kind.efficiency => l10n.statEfficiency,
    _Kind.trimp => l10n.sumTrimp,
    _Kind.zones => l10n.sumZones,
    _Kind.other =>
      widget.valueKey == classificationKey
          ? l10n.sumClassification
          : l10n.explSourcesTitle,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.explTitle)),
      body: FutureBuilder<ValueExplanation?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Text(l10n.explLoading, key: const Key('expl_loading')),
            );
          }
          final data = snapshot.data;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                key: const Key('expl_body'),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      _title(l10n),
                      key: const Key('expl_value_title'),
                      style: RamuriType.of(context).pageTitle,
                    ),
                  ),
                  ..._cards(_content(context, l10n, data)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Gruppiert die Inhalte wie Fortschritt: jede [Heading] steht über einer
  /// eigenen Karte mit den folgenden Angaben; Inhalt ohne Überschrift
  /// (Hinweise, Fehler) steht in einer Karte davor.
  List<Widget> _cards(List<Widget> content) {
    final out = <Widget>[];
    Widget? heading;
    var body = <Widget>[];
    void flush() {
      if (heading == null && body.isEmpty) return;
      if (heading != null) out.add(heading!);
      if (body.isNotEmpty) {
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: RamuriCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: body,
              ),
            ),
          ),
        );
      }
      heading = null;
      body = <Widget>[];
    }

    for (final w in content) {
      if (w is Heading) {
        flush();
        heading = w;
      } else {
        body.add(w);
      }
    }
    flush();
    return out;
  }

  List<Widget> _content(
    BuildContext context,
    AppLocalizations l10n,
    ValueExplanation? data,
  ) {
    if (widget.valueKey == classificationKey) {
      return _classification(l10n);
    }
    if (data == null || data.failed) {
      return [Text(l10n.explLoadFailed, key: const Key('expl_failed'))];
    }
    if (widget.valueKey == runSourcesKey) {
      return [
        ..._sources(l10n, data, key: 'expl_sources'),
        ..._gapNote(l10n, data),
      ];
    }
    final value = data.value;
    if (value == null) {
      return [Text(l10n.explNotStored, key: const Key('expl_not_stored'))];
    }
    final kind = _kindOf(widget.valueKey);
    final material = MaterialLocalizations.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    String num(double v) {
      final t = v.toStringAsFixed(1);
      return german ? t.replaceAll('.', ',') : t;
    }

    String date(DateTime t) => material.formatMediumDate(t.toLocal());
    final estimate =
        kind == _Kind.vo2Run ||
        kind == _Kind.vo2LongTerm ||
        kind == _Kind.efficiency;
    final from = value.dataFrom;
    final to = value.dataTo;
    final dayText = widget.day;
    final asOfDay = dayText == null ? null : DateTime.tryParse(dayText);
    final out = <Widget>[];
    final missing = value.value == null;
    if (estimate && !missing) {
      out.add(
        Text(
          l10n.explEstimateBadge,
          key: const Key('expl_estimate'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
    }
    if (value.value == null) {
      final reason = value.unavailableReason;
      out
        ..add(Heading(l10n.explReasonHeading))
        ..add(
          Text(
            reason == null ? l10n.runUnavailable : reasonText(l10n, reason),
            key: const Key('expl_reason'),
          ),
        );
      if (reason == UnavailableReason.noHeartRate ||
          reason == UnavailableReason.insufficientCoverage) {
        out.add(Text(l10n.explNeedsHeartRate, key: const Key('expl_needs_hr')));
      }
    }
    final gaps = data.profileGaps;
    if (gaps.isNotEmpty) {
      final fields = [
        if (gaps.contains(ProfileGap.maxHeartRate)) l10n.explGapMax,
        if (gaps.contains(ProfileGap.restingHeartRate)) l10n.explGapRest,
      ].join(', ');
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            l10n.explProfileHint(fields),
            key: const Key('expl_profile_hint'),
          ),
        ),
      );
    }

    // 1 Daten
    out.add(Heading(missing ? l10n.explQ1None : l10n.explQ1));
    out.addAll(_sources(l10n, data, key: 'expl_a1_sources'));
    out.addAll(_gapNote(l10n, data));
    if (widget.runId != null) {
      out.add(
        Text(
          data.sources.any((s) => s.kind == ExplainedSourceKind.heartRateDevice)
              ? l10n.explDataBasisGpsHr
              : l10n.explDataBasisGps,
          key: const Key('expl_data_basis'),
        ),
      );
    }
    out.addAll(_basis(l10n, value));
    // 2 Alter
    out.add(Heading(l10n.explQ2));
    out.add(
      Text(
        [
          missing
              ? l10n.explAgeAttempt(date(value.computedAt))
              : from != null && to != null
              ? l10n.explAge(date(from), date(to), date(value.computedAt))
              : l10n.explAgeNoRange(date(value.computedAt)),
          // Tageswert: der Tag, auf den sich „bis zum Stand“ (Anzahl) bezieht.
          if (!missing && asOfDay != null)
            l10n.explAsOf(
              asOfDateText(
                Localizations.localeOf(context).languageCode,
                asOfDay,
              ),
            ),
        ].join('\n'),
        key: const Key('expl_a2'),
      ),
    );
    // 3 Messungen
    out.add(Heading(l10n.explQ3));
    final count = value.measurementCount;
    out.add(
      Text(switch (kind) {
        _Kind.vo2LongTerm => l10n.explCountRuns(count),
        _Kind.zones || _Kind.trimp => l10n.explCountValues(count),
        _ => l10n.explCountSections(count),
      }, key: const Key('expl_a3')),
    );
    if (value.sections.isNotEmpty) {
      out.add(
        Text(
          l10n.explSectionsHeading,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      );
      final start = value.dataFrom;
      for (final s in value.sections) {
        final offset = start == null
            ? 0
            : s.start.difference(start).inMinutes.clamp(0, 1 << 30);
        final minutes = s.duration.inMinutes.toString();
        final used = s.estimate != null && s.weight > 0;
        out.add(
          Text(
            used
                ? l10n.explSectionUsed('$offset', minutes, num(s.weight))
                : l10n.explSectionNotUsed('$offset', minutes),
          ),
        );
      }
    }
    // 4 Methode
    out.add(Heading(l10n.explQ4));
    out.add(
      Text(
        l10n.explMethod(
          value.method,
          value.methodVersion,
          value.parameterVersion,
        ),
        key: const Key('expl_a4'),
      ),
    );
    // 5 Verlässlichkeit
    out.add(Heading(l10n.explQ5));
    out.add(
      Text(qualityStageText(l10n, value.quality), key: const Key('expl_a5')),
    );
    out.add(Text(l10n.explQualityNote, key: const Key('expl_a5_note')));
    // 6 gemessen oder geschätzt
    out.add(Heading(l10n.explQ6));
    out.add(
      Text(switch (kind) {
        _ when missing => l10n.explKindNone,
        _Kind.vo2Run => l10n.explKindVo2Run,
        _Kind.vo2LongTerm => l10n.explKindVo2LongTerm,
        _Kind.efficiency => l10n.explKindEfficiency,
        _Kind.zones => l10n.explKindZones,
        _Kind.trimp => l10n.explKindTrimp,
        _Kind.other => '',
      }, key: const Key('expl_a6')),
    );
    return out;
  }

  List<Widget> _basis(AppLocalizations l10n, ComputedValue value) {
    final kind = _kindOf(widget.valueKey);
    final b = value.heartRateBasis;
    if (b == null) {
      return kind == _Kind.vo2Run || kind == _Kind.zones || kind == _Kind.trimp
          ? [Text(l10n.explBasisUnknown, key: const Key('expl_basis_unknown'))]
          : const [];
    }
    final max = b.usableMaxBpm;
    final rest = b.usableRestingBpm;
    return [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          l10n.explBasisHeading,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      Text(
        max == null
            ? l10n.explBasisMissingMax
            : (b.maxIsEstimated
                  ? l10n.explBasisMaxEstimated(max)
                  : l10n.explBasisMax(max)),
        key: const Key('expl_basis_max'),
      ),
      Text(
        rest == null ? l10n.explBasisMissingRest : l10n.explBasisRest(rest),
        key: const Key('expl_basis_rest'),
      ),
    ];
  }

  List<Widget> _sources(
    AppLocalizations l10n,
    ValueExplanation data, {
    required String key,
  }) {
    if (data.sources.isEmpty) {
      return [Text(l10n.explSourcesNone, key: Key('${key}_none'))];
    }
    return [
      Column(
        key: Key(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eine Kennung kann mehrfach vorkommen (Gerät A, B, A): Index im Key.
          for (var i = 0; i < data.sources.length; i++)
            Text(
              _sourceText(l10n, data.sources[i]),
              key: Key('expl_source_${i}_${data.sources[i].id}'),
            ),
        ],
      ),
    ];
  }

  /// Nur wo eine Zahl der Werte steht, auf die der Hinweis verweist.
  List<Widget> _gapNote(AppLocalizations l10n, ValueExplanation data) =>
      data.sources.any(
        (s) => s.kind == ExplainedSourceKind.heartRateDevice && s.count != null,
      )
      ? [Text(l10n.explSourceGapNote, key: const Key('expl_gap_note'))]
      : const [];

  String _sourceText(AppLocalizations l10n, ExplainedSource s) {
    final label = switch (s.kind) {
      ExplainedSourceKind.gps => l10n.explSourceGps,
      ExplainedSourceKind.unknown => l10n.explSourceUnknown(s.id),
      ExplainedSourceKind.heartRateDevice =>
        s.deleted
            ? l10n.explSourceDeviceDeleted(s.id)
            : (s.name == null || s.name!.trim().isEmpty
                  ? l10n.explSourceDeviceUnnamed(s.id)
                  : l10n.explSourceDevice(s.name!, s.id)),
    };
    final count = s.count;
    return count == null ? label : '$label, ${l10n.explSourceValues(count)}';
  }

  List<Widget> _classification(AppLocalizations l10n) {
    final c = widget.classification;
    if (c == null || !c.isAvailable) {
      return [Text(l10n.explClassNone, key: const Key('expl_class_none'))];
    }
    final reference = widget.formatter?.pace(c.referenceSecondsPerKm) ?? '';
    return [
      Heading(l10n.explQ1),
      Text(
        l10n.explClassData(c.comparedRuns, reference),
        key: const Key('expl_class_data'),
      ),
      Heading(l10n.explQ4),
      Text(l10n.explClassMethod, key: const Key('expl_class_method')),
      Heading(l10n.explQ5),
      Text(l10n.explClassReliability, key: const Key('expl_class_reliability')),
    ];
  }
}

/// Überschrift eines Abschnitts, für Vorleser als Überschrift ausgezeichnet.
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: SectionHeading(text),
  );
}
