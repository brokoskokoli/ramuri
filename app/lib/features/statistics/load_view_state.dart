import 'package:core/core.dart';

/// Stand des Belastungsstands für die Oberfläche.
enum LoadPhase { loading, ready, failed }

/// Wie sicher der persönliche Faktor ist (PAR-086, PAR-087).
enum LoadFactorStatus {
  /// Kein Faktor: Voraussetzungen fehlen. Betroffene Einheiten sind
  /// unbewertet.
  missing,

  /// Faktor da, aber unter 20 Läufen: „noch wenig gesichert“.
  tentative,

  /// Faktor aus 20 Läufen.
  secured,

  /// Ein einmal angewandter Faktor gilt weiter, obwohl die Mindestanzahl
  /// PAR-086 im 180-Tage-Fenster aktuell nicht erfüllt ist; bleibt
  /// gekennzeichnet (Festlegung WP19).
  unsupported,

  /// Das Profil ist nicht anwendbar (Ruhepuls oder Koeffizienten fehlen);
  /// es gibt weder TRIMP noch Faktor.
  profileNotApplicable,
}

/// Ausgabe des Belastungsstands für die Karte „Belastung“ auf Fortschritt
/// (WP19). Reine Daten und Ableitungen, ohne Text und ohne Wertung (PAR-072,
/// FR-0101): Verlauf, aktueller ATL/CTL/TSB, Vorläufigkeit, Kennzeichen,
/// Grundlage (Profil, Faktor, Datenstand).
class LoadViewState {
  const LoadViewState._(this.phase, this.report);

  const LoadViewState.loading() : this._(LoadPhase.loading, null);
  const LoadViewState.failed() : this._(LoadPhase.failed, null);
  const LoadViewState.ready(TrainingLoadReport report)
    : this._(LoadPhase.ready, report);

  final LoadPhase phase;
  final TrainingLoadReport? report;

  /// Alle Tage des Verlaufs bis [seriesEnd]; ältester zuerst.
  List<LoadDay> get days => report?.series.days ?? const [];

  /// Der letzte Tag der Reihe mit ATL/CTL/TSB; `null`, solange es keinen
  /// bewerteten Tag gibt (keine Aussage, FR-0104).
  LoadDay? get current {
    final c = report?.series.summary.current;
    return c != null && c.hasValues ? c : null;
  }

  bool get hasStatement => current != null;

  /// ATL ist vorläufig (PAR-088, FR-0103).
  bool get atlProvisional => current?.atlProvisional ?? false;

  /// CTL und TSB sind vorläufig, mit den Gründen (PAR-089, PAR-090).
  Set<LoadProvisionalReason> get ctlProvisionalReasons =>
      current?.ctlProvisionalReasons ?? const {};

  /// TSB% nur, wenn die Schwellen nicht gesperrt sind; sonst `null` (PAR-073).
  double? get tsbPercentMean7 {
    final c = current;
    if (c == null || c.tsbThresholdsLocked) return null;
    return c.tsbPercentMean7;
  }

  /// Tage mit mindestens einer unbewerteten Einheit (ATL/CTL unverändert).
  List<DateTime> get unratedDays => [
    for (final d in days)
      if (d.flags.contains(LoadDayFlag.unrated)) d.day,
  ];

  /// Tage mit umgerechneter Last (sRPE mit Faktor).
  List<DateTime> get convertedDays => [
    for (final d in days)
      if (d.flags.contains(LoadDayFlag.converted)) d.day,
  ];

  LoadProfile? get profile => report?.profile;
  bool get profileApplicable => report?.profileApplicable ?? true;

  LoadFactorStatus get factorStatus {
    final r = report;
    if (r == null) return LoadFactorStatus.missing;
    if (!r.profileApplicable) return LoadFactorStatus.profileNotApplicable;
    if (r.factor.value == null) return LoadFactorStatus.missing;
    if (r.factor.unsupported) return LoadFactorStatus.unsupported;
    return r.factor.tentative
        ? LoadFactorStatus.tentative
        : LoadFactorStatus.secured;
  }

  double? get factor => report?.factor.value;
  int get factorRunCount => report?.factor.runCount ?? 0;

  /// Ein neuer Faktor wartet auf die Bestätigung in der Neuberechnung.
  bool get factorOffered => report?.factor.offered != null;

  /// Datenstand: Tag der letzten erfassten Einheit.
  DateTime? get dataThrough => report?.series.summary.lastUnitDay;

  /// Letzter Tag der Reihe (bei leerem heutigen Tag gestern).
  DateTime? get seriesEnd => report?.seriesEnd;
  bool get todayEmpty => report?.todayEmpty ?? false;

  DateTime? get calculatedAt => report?.calculatedAt;
}
