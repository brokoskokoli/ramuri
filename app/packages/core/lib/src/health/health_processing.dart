import 'health_parameters.dart';
import 'health_types.dart';

const _version = 1;

/// Aufbereitung von Health-Connect-Daten, reine Funktionen (WP32 Teil D).
class HealthProcessing {
  const HealthProcessing([this.params = const HealthParameters.v4()]);

  final HealthParameters params;

  HealthMethod _m(String name) =>
      HealthMethod(name, _version, params.parameterVersion);

  /// Hauptschlafphase (PAR-164). Je Quelle zählt deren längste Sitzung, die
  /// in den letzten 16 h geendet hat (nicht in der Zukunft) und mindestens
  /// 3 h dauert (Grenzen einschließlich). Mehrere Quellen: Quellen mit
  /// Schlafphasen vor Quellen ohne, darunter die längste. Gleich lang:
  /// die später beendete, dann die mit dem kleineren Namen.
  SleepSession? mainSleep(Iterable<SleepSession> sessions, DateTime now) {
    final oldest = now.subtract(params.mainSleepMaxAge);
    final best = <String, SleepSession>{};
    for (final s in sessions) {
      if (s.end.isAfter(now) || s.end.isBefore(oldest)) {
        continue;
      }
      if (s.duration < params.mainSleepMinDuration) {
        continue;
      }
      final cur = best[s.origin];
      if (cur == null || _longer(s, cur)) best[s.origin] = s;
    }
    SleepSession? pick;
    for (final s in best.values) {
      if (pick == null || _betterSource(s, pick)) pick = s;
    }
    return pick;
  }

  bool _longer(SleepSession a, SleepSession b) {
    final c = a.duration.compareTo(b.duration);
    if (c != 0) return c > 0;
    return a.end.isAfter(b.end);
  }

  bool _betterSource(SleepSession a, SleepSession b) {
    if (a.hasStages != b.hasStages) return a.hasStages;
    final c = a.duration.compareTo(b.duration);
    if (c != 0) return c > 0;
    if (a.end != b.end) return a.end.isAfter(b.end);
    return a.origin.compareTo(b.origin) < 0;
  }

  /// Schlafzeit und Effizienz (PAR-166). Phasen werden auf die Sitzung
  /// zugeschnitten; die Abdeckung zählt alle Phasen (auch „wach“) als
  /// Vereinigung der Zeitspannen. Unter 90 % oder ohne Phasen: Dauer ist die
  /// Sitzungsdauer, geschätzt, ohne Effizienz.
  SleepSummary sleepSummary(SleepSession s) {
    final total = s.duration;
    final spans = <(DateTime, DateTime)>[];
    var sleepMs = 0;
    for (final st in s.stages) {
      final a = st.start.isBefore(s.start) ? s.start : st.start;
      final b = st.end.isAfter(s.end) ? s.end : st.end;
      if (!b.isAfter(a)) continue;
      spans.add((a, b));
      if (st.kind.countsAsSleep) sleepMs += b.difference(a).inMilliseconds;
    }
    spans.sort((x, y) => x.$1.compareTo(y.$1));
    var covered = 0;
    DateTime? curStart;
    DateTime? curEnd;
    for (final (a, b) in spans) {
      if (curEnd == null || a.isAfter(curEnd)) {
        if (curStart != null) {
          covered += curEnd!.difference(curStart).inMilliseconds;
        }
        curStart = a;
        curEnd = b;
      } else if (b.isAfter(curEnd)) {
        curEnd = b;
      }
    }
    if (curStart != null) {
      covered += curEnd!.difference(curStart).inMilliseconds;
    }

    final totalMs = total.inMilliseconds;
    final estimate =
        totalMs <= 0 ||
        spans.isEmpty ||
        covered < params.sleepCoverageMinShare * totalMs;
    if (estimate) {
      return SleepSummary(
        method: _m('sleep-summary'),
        origin: s.origin,
        sessionDuration: total,
        sleepDuration: total,
        isEstimate: true,
        efficiencyPercent: null,
      );
    }
    // Überlappende Schlafphasen könnten die Sitzung überschreiten.
    final clamped = sleepMs > totalMs ? totalMs : sleepMs;
    return SleepSummary(
      method: _m('sleep-summary'),
      origin: s.origin,
      sessionDuration: total,
      sleepDuration: Duration(milliseconds: clamped),
      isEstimate: false,
      efficiencyPercent: clamped * 100 / totalMs,
    );
  }

  /// Teilskala der Effizienz (PAR-166), 0 bis 80.
  double efficiencyScore(double e) {
    final lo = params.efficiencyLowerKnee;
    if (e < lo) {
      final v =
          params.efficiencyScoreAtLowerKnee -
          params.efficiencySlopeBelow * (lo - e);
      return v < 0 ? 0 : v;
    }
    if (e < params.efficiencyUpperKnee) {
      return params.efficiencyScoreAtLowerKnee + (e - lo);
    }
    return params.efficiencyScoreCap;
  }

  /// HRV-Tageswert je Quell-App (PAR-160). Ohne Hauptschlafphase [main] gibt
  /// es nichts. Gültig: 1–200 ms. Median der Einträge der Quelle von
  /// Beginn bis Ende der Hauptschlafphase (Grenzen einschließlich); gibt es
  /// dort keinen, der Median der Einträge in den 60 min danach (Ende
  /// ausgeschlossen, 60 min einschließlich), markiert als Rückfall.
  Map<String, HealthDailyValue> hrvDaily(
    Iterable<HealthSample> samples,
    SleepSession? main,
  ) {
    if (main == null) return const {};
    final byOrigin = _byOrigin(samples, params.rmssdMinMs, params.rmssdMaxMs);
    final fallbackEnd = main.end.add(params.hrvFallbackWindow);
    final out = <String, HealthDailyValue>{};
    byOrigin.forEach((origin, list) {
      final inSleep = list
          .where(
            (x) => !x.time.isBefore(main.start) && !x.time.isAfter(main.end),
          )
          .toList();
      var fallback = false;
      var use = inSleep;
      if (use.isEmpty) {
        use = list
            .where(
              (x) => x.time.isAfter(main.end) && !x.time.isAfter(fallbackEnd),
            )
            .toList();
        fallback = true;
      }
      if (use.isEmpty) return;
      out[origin] = HealthDailyValue(
        method: _m('hrv-rmssd-night'),
        origin: origin,
        value: _median(use.map((x) => x.value).toList()),
        sampleCount: use.length,
        isFallback: fallback,
      );
    });
    return out;
  }

  /// Ruhepuls-Tageswert je Quell-App: Median der gültigen Einträge
  /// (PAR-017: 30–120 bpm, Grenzen gültig) im halboffenen Zeitraum
  /// [from, to). Der Median ist eine Lesart, PAR nennt keine Aggregation.
  Map<String, HealthDailyValue> restingHeartRateDaily(
    Iterable<HealthSample> samples,
    DateTime from,
    DateTime to,
  ) {
    final inRange = samples.where(
      (x) => !x.time.isBefore(from) && x.time.isBefore(to),
    );
    final out = <String, HealthDailyValue>{};
    _byOrigin(
      inRange,
      params.restingHeartRateMinBpm,
      params.restingHeartRateMaxBpm,
    ).forEach((origin, list) {
      out[origin] = HealthDailyValue(
        method: _m('resting-hr-day'),
        origin: origin,
        value: _median(list.map((x) => x.value).toList()),
        sampleCount: list.length,
        isFallback: false,
      );
    });
    return out;
  }

  /// Quell-App nach PAR-189: die mit den meisten gültigen Einträgen (Wert
  /// zwischen [min] und [max] einschließlich). Gleichstand: der kleinere
  /// Name. Null, wenn keine Quelle gültige Einträge hat. Die Werte der
  /// anderen gehen nicht ein.
  String? selectSource(
    Iterable<HealthSample> samples, {
    required double min,
    required double max,
  }) {
    String? best;
    var bestN = 0;
    _byOrigin(samples, min, max).forEach((origin, list) {
      final n = list.length;
      if (n > bestN ||
          (n == bestN && best != null && origin.compareTo(best!) < 0)) {
        best = origin;
        bestN = n;
      }
    });
    return best;
  }

  /// [selectSource] mit dem Bereich 1–200 ms (PAR-160).
  String? selectHrvSource(Iterable<HealthSample> samples) =>
      selectSource(samples, min: params.rmssdMinMs, max: params.rmssdMaxMs);

  /// [selectSource] mit dem Bereich PAR-017.
  String? selectRestingHeartRateSource(Iterable<HealthSample> samples) =>
      selectSource(
        samples,
        min: params.restingHeartRateMinBpm,
        max: params.restingHeartRateMaxBpm,
      );

  Map<String, List<HealthSample>> _byOrigin(
    Iterable<HealthSample> samples,
    double min,
    double max,
  ) {
    final m = <String, List<HealthSample>>{};
    for (final s in samples) {
      if (s.value.isNaN || s.value < min || s.value > max) continue;
      (m[s.origin] ??= []).add(s);
    }
    return m;
  }

  double _median(List<double> v) {
    v.sort();
    final n = v.length;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }
}
