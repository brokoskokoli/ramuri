import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../recalculation/recalculation_controller.dart';
import 'fitness_section.dart' show fitnessNumber;
import 'load_controller.dart';
import 'load_view_state.dart';

/// Karte „Belastung“ auf Fortschritt (WP19, FR-0097 bis FR-0104).
///
/// Zeigt den Verlauf von ATL und CTL in einem Diagramm mit einer Skala, die
/// aktuellen Werte, TSB ohne Wertung, die Vorläufigkeit und die Grundlage
/// (Profil, Faktor, Datenstand). Es gibt kein Band „zu wenig / gut / viel“,
/// keinen „empfohlenen Bereich“ und keine Aussage zu Erholung, Risiko oder
/// Fitness aus diesen Zahlen (PAR-072, PAR-174, FR-0101). Der CTL heißt
/// „langfristiges Belastungsniveau“ (FR-0100). Ohne bewertete Einheit steht
/// keine Zahl da, auch keine kleine (FR-0104).
///
/// Ohne [recalculation] und ohne [controller] zeigt die Karte nichts. In der
/// App kommt der Controller aus [session], [clock] und der einen
/// Neuberechnungs-Instanz; das Laden läuft über deren Reihe (`serializedRefreshingOffer`).
class LoadCard extends StatefulWidget {
  const LoadCard({
    super.key,
    this.session,
    this.clock,
    this.recalculation,
    this.controller,
    this.onFirstSettled,
  });

  /// Einmal, nachdem die Karte ihre endgültige Höhe hat (erstes Ergebnis oder
  /// Fehler statt „wird berechnet“). Die Seite stellt dann ihre gemerkte
  /// Scrollposition wieder her.
  final VoidCallback? onFirstSettled;

  final StorageSession? session;
  final Clock? clock;
  final RecalculationController? recalculation;

  /// Für Tests: ein fertiger Controller, den die Karte nicht besitzt.
  final LoadController? controller;

  @override
  State<LoadCard> createState() => _LoadCardState();
}

class _LoadCardState extends State<LoadCard> {
  LoadController? _owned;

  LoadController? get _controller => widget.controller ?? _owned;
  bool _settledReported = false;

  void _reportSettled() {
    final c = _controller;
    if (_settledReported || c == null || c.state.phase == LoadPhase.loading) {
      return;
    }
    _settledReported = true;
    // Nach dem Layout mit der neuen Höhe, nicht davor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFirstSettled?.call();
    });
  }

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    final clock = widget.clock;
    final recalculation = widget.recalculation;
    if (widget.controller == null &&
        session != null &&
        clock != null &&
        recalculation != null) {
      _owned = LoadController(
        service: TrainingLoadService(
          session: session,
          clock: clock,
          calculation: ValueCalculationService(session: session, clock: clock),
          recalculation: recalculation.service,
        ),
        serialize: recalculation.serializedRefreshingOffer,
      );
    }
    _controller?.addListener(_reportSettled);
    _reportSettled();
  }

  @override
  void dispose() {
    _controller?.removeListener(_reportSettled);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            LoadCardBody(state: controller.state, onRetry: controller.reload),
      ),
    );
  }
}

/// Inhalt der Karte für einen Stand; ohne Controller, damit Tests jeden Stand
/// direkt zeigen können.
class LoadCardBody extends StatelessWidget {
  const LoadCardBody({
    super.key,
    required this.state,
    this.onRetry,
    this.initiallyExpanded = false,
  });

  final LoadViewState state;
  final VoidCallback? onRetry;

  /// Der Bereich „Grundlage“ ist eingeklappt; Tests können ihn offen starten.
  final bool initiallyExpanded;

  /// Tage im Diagramm: zwölf Wochen, wie der Trend der VO₂max.
  static const int chartDays = 84;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;

    // Das verwendete Profil steht immer sichtbar neben dem Titel (FR-0197);
    // dieselbe Zeile, damit die eingeklappte Karte nicht höher wird.
    final profileName = switch (state.profile ?? LoadProfile.edwards) {
      LoadProfile.edwards => l10n.loadProfileNameEdwards,
      LoadProfile.banister => l10n.loadProfileNameBanister,
    };
    final children = <Widget>[
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 4,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.loadTitle,
              key: const Key('load_title'),
              style: theme.titleMedium!.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (state.phase == LoadPhase.ready)
            Text(
              l10n.loadProfileShort(profileName),
              key: const Key('load_profile_short'),
              style: theme.labelSmall!.copyWith(color: c.textMuted),
            ),
        ],
      ),
      const SizedBox(height: 10),
    ];

    switch (state.phase) {
      case LoadPhase.loading:
        children.add(
          Text(
            l10n.loadLoading,
            key: const Key('load_loading'),
            style: theme.bodyMedium!.copyWith(color: c.textMuted),
          ),
        );
      case LoadPhase.failed:
        children
          ..add(
            Text(
              l10n.loadFailed,
              key: const Key('load_failed'),
              style: theme.bodyMedium,
            ),
          )
          ..add(
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('load_retry'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    RamuriTheme.minTarget,
                    RamuriTheme.minTarget,
                  ),
                ),
                onPressed: onRetry,
                child: Text(l10n.loadRetry),
              ),
            ),
          );
      case LoadPhase.ready:
        children.addAll(_ready(context, l10n, c, theme));
    }

    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          key: const Key('load_card'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _ready(
    BuildContext context,
    AppLocalizations l10n,
    RamuriColors c,
    TextTheme theme,
  ) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    final material = MaterialLocalizations.of(context);
    String points(double v) => l10n.loadValuePoints(fitnessNumber(german, v));
    final current = state.current;
    final out = <Widget>[];
    // Alles, was nicht in die kompakte Ansicht passt, kommt in „Grundlage“.
    final details = <Widget>[];
    var window = const <LoadDay>[];
    double? scaleMax;

    if (current == null) {
      out.add(
        Text(
          l10n.loadEmpty,
          key: const Key('load_empty'),
          style: theme.bodyMedium,
        ),
      );
      // FR-0102: Unbewertete Einheiten nennen, ohne Fitnessaussage.
      final unrated = state.unratedUnits;
      if (unrated > 0) {
        final reasons = [
          if (state.unratedNoRpeUnits > 0)
            l10n.loadEmptyUnratedNoRpe(state.unratedNoRpeUnits),
          if (state.unratedNoFactorUnits > 0)
            l10n.loadEmptyUnratedNoFactor(state.unratedNoFactorUnits),
        ];
        out.add(
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              [l10n.loadEmptyUnrated(unrated), ...reasons].join(' '),
              key: const Key('load_empty_unrated'),
              style: theme.bodyMedium,
            ),
          ),
        );
      }
    } else {
      window = state.days.length > chartDays
          ? state.days.sublist(state.days.length - chartDays)
          : state.days;
      scaleMax = LoadChart.scaleFor(window);
      final first = window.first.day;
      final last = window.last.day;
      out
        ..add(
          Semantics(
            container: true,
            image: true,
            excludeSemantics: true,
            label: l10n.loadChartSemantics(
              window.length,
              material.formatMediumDate(last),
              fitnessNumber(german, current.atl!),
              fitnessNumber(german, current.ctl!),
            ),
            child: LoadChart(
              key: const Key('load_chart'),
              days: window,
              scaleMax: scaleMax,
            ),
          ),
        )
        ..add(const SizedBox(height: 4))
        ..add(
          // Row statt Wrap: Ein Wrap ist nur so breit wie sein Inhalt, dort
          // wirkt spaceBetween nicht und beide Daten klebten links.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  material.formatShortDate(first),
                  key: const Key('load_axis_start'),
                  style: theme.labelSmall!.copyWith(color: c.textMuted),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  material.formatShortDate(last),
                  key: const Key('load_axis_end'),
                  textAlign: TextAlign.end,
                  style: theme.labelSmall!.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(_legend(l10n, c, theme, window))
        ..add(const SizedBox(height: 10))
        ..add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Figure(
                  keyName: 'load_atl',
                  label: l10n.loadFigAtl,
                  semanticsLabel: l10n.loadAtlLabel,
                  value: points(current.atl!),
                  provisional: state.atlProvisional,
                  swatch: _Swatch.line(c.ember, 2),
                ),
              ),
              Expanded(
                child: _Figure(
                  keyName: 'load_ctl',
                  label: l10n.loadFigCtl,
                  semanticsLabel: l10n.loadCtlLabel,
                  value: points(current.ctl!),
                  provisional: current.ctlProvisional,
                  swatch: _Swatch.line(c.accent, 4),
                ),
              ),
              Expanded(
                child: _Figure(
                  keyName: 'load_tsb',
                  label: l10n.loadFigTsb,
                  semanticsLabel: l10n.loadTsbLabel,
                  value: current.tsb == null
                      ? l10n.loadTsbNone
                      : l10n.loadValuePoints(
                          fitnessNumber(german, current.tsb!, sign: true),
                        ),
                  provisional: current.ctlProvisional || current.atlProvisional,
                ),
              ),
            ],
          ),
        );

      // Hinweise: kurz, Gründe stehen unter „Grundlage“.
      // Ohne Zusage haben ATL und CTL denselben Grund: ein gemeinsamer Satz.
      final bothNoCommitment =
          state.atlProvisionalReasons.contains(
            LoadProvisionalReason.noCommitment,
          ) &&
          state.ctlProvisionalReasons.contains(
            LoadProvisionalReason.noCommitment,
          );
      final reasons = <String?>[
        for (final r in LoadProvisionalReason.values)
          if (state.atlProvisionalReasons.contains(r))
            switch (r) {
              LoadProvisionalReason.startup => l10n.loadProvAtl,
              LoadProvisionalReason.noCommitment =>
                bothNoCommitment
                    ? l10n.loadProvBothCommitment
                    : l10n.loadProvAtlCommitment,
              // ATL kennt keinen Rückfall nach PAR-090.
              LoadProvisionalReason.missingUnits => null,
            },
        for (final r in LoadProvisionalReason.values)
          if (state.ctlProvisionalReasons.contains(r))
            switch (r) {
              LoadProvisionalReason.startup => l10n.loadProvStartup,
              LoadProvisionalReason.missingUnits => l10n.loadProvMissing,
              // Beim gemeinsamen Satz steht er schon bei ATL.
              LoadProvisionalReason.noCommitment =>
                bothNoCommitment ? null : l10n.loadProvCommitment,
            },
      ];
      if (reasons.nonNulls.isNotEmpty) {
        out.add(
          _Hint(l10n.loadHintProvisional, keyName: 'load_hint_provisional'),
        );
      }
      for (final r in reasons.nonNulls) {
        details.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              r,
              key: const Key('load_provisional_reason'),
              style: theme.bodySmall!.copyWith(color: c.textMuted),
            ),
          ),
        );
      }
    }
    if (!state.profileApplicable) {
      out.add(_Hint(l10n.loadHintProfile, keyName: 'load_hint_profile'));
    }
    if (state.factorOffered) {
      out.add(_Hint(l10n.loadFactorOffered, keyName: 'load_factor_offered'));
    }
    out
      ..add(const SizedBox(height: 8))
      ..add(
        _BasisSection(
          initiallyExpanded: initiallyExpanded,
          title: l10n.loadBasisTitle,
          children: [
            ..._basis(context, l10n, c, theme),
            ...details,
            if (current != null) ...[
              const SizedBox(height: 10),
              Text(
                l10n.loadBasisFiguresTitle,
                style: theme.labelMedium!.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 2),
              Text(l10n.loadAtlLabel, style: theme.bodySmall),
              Text(l10n.loadCtlLabel, style: theme.bodySmall),
              Text(l10n.loadTsbLabel, style: theme.bodySmall),
              Text(
                l10n.loadScaleNote(scaleMax!.toStringAsFixed(0)),
                key: const Key('load_scale'),
                style: theme.bodySmall!.copyWith(color: c.textMuted),
              ),
              ..._flagExplanations(l10n, c, theme, window),
            ],
          ],
        ),
      );
    return out;
  }

  /// Erklärung der Kennzeichen im Verlauf, nur für die vorhandenen Arten.
  List<Widget> _flagExplanations(
    AppLocalizations l10n,
    RamuriColors c,
    TextTheme theme,
    List<LoadDay> window,
  ) {
    bool any(LoadDayFlag f) => window.any((d) => d.flags.contains(f));
    final texts = <String>[
      if (any(LoadDayFlag.converted)) l10n.loadFlagConverted,
      if (any(LoadDayFlag.unrated)) l10n.loadFlagUnrated,
      if (any(LoadDayFlag.emptyUnchanged)) l10n.loadFlagEmpty,
    ];
    if (texts.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Text(
        l10n.loadBasisFlagsTitle,
        style: theme.labelMedium!.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: 2),
      for (final t in texts) Text(t, style: theme.bodySmall),
    ];
  }

  /// Eine Zeile: die Linien und, nur wenn im Zeitraum vorhanden, die
  /// Kennzeichen-Symbole (Erklärung unter „Grundlage“).
  Widget _legend(
    AppLocalizations l10n,
    RamuriColors c,
    TextTheme theme,
    List<LoadDay> window,
  ) {
    bool any(LoadDayFlag f) => window.any((d) => d.flags.contains(f));
    return Wrap(
      key: const Key('load_legend'),
      spacing: 12,
      runSpacing: 4,
      children: [
        _LegendItem(swatch: _Swatch.line(c.ember, 2), text: l10n.loadLegendAtl),
        _LegendItem(
          swatch: _Swatch.line(c.accent, 4),
          text: l10n.loadLegendCtl,
        ),
        if (any(LoadDayFlag.converted))
          _LegendItem(
            keyName: 'load_legend_converted',
            swatch: _Swatch.marker(LoadDayFlag.converted, c),
            text: l10n.loadLegendConverted,
          ),
        if (any(LoadDayFlag.unrated))
          _LegendItem(
            keyName: 'load_legend_unrated',
            swatch: _Swatch.marker(LoadDayFlag.unrated, c),
            text: l10n.loadLegendUnrated,
          ),
        if (any(LoadDayFlag.emptyUnchanged))
          _LegendItem(
            keyName: 'load_legend_empty',
            swatch: _Swatch.marker(LoadDayFlag.emptyUnchanged, c),
            text: l10n.loadLegendEmpty,
          ),
      ],
    );
  }

  List<Widget> _basis(
    BuildContext context,
    AppLocalizations l10n,
    RamuriColors c,
    TextTheme theme,
  ) {
    final german = Localizations.localeOf(context).languageCode == 'de';
    final material = MaterialLocalizations.of(context);
    final profile = state.profile ?? LoadProfile.edwards;
    final profileName = switch (profile) {
      LoadProfile.edwards => l10n.loadProfileNameEdwards,
      LoadProfile.banister => l10n.loadProfileNameBanister,
    };
    final String profileText;
    if (state.profileApplicable) {
      profileText = switch (profile) {
        LoadProfile.edwards => l10n.loadProfileEdwards,
        LoadProfile.banister => l10n.loadProfileBanister,
      };
    } else {
      final issues = state.report?.profileIssues ?? const [];
      profileText = l10n.loadProfileNotApplicable(
        profileName,
        [
          for (final i in issues)
            switch (i) {
              LoadProfileIssue.missingRestingHeartRate =>
                l10n.loadIssueRestingHr,
              LoadProfileIssue.missingCoefficients =>
                l10n.loadIssueCoefficients,
              LoadProfileIssue.heartRateReserveUnusable =>
                l10n.loadIssueReserve,
            },
        ].join(', '),
      );
    }

    String factorNumber(double v) {
      final t = v.toStringAsFixed(2);
      return german ? t.replaceAll('.', ',') : t;
    }

    final factor = state.factor;
    final factorText = switch (state.factorStatus) {
      LoadFactorStatus.missing => l10n.loadFactorMissing,
      LoadFactorStatus.tentative => l10n.loadFactorTentative(
        factorNumber(factor!),
        state.factorRunCount,
      ),
      LoadFactorStatus.secured => l10n.loadFactorSecured(
        factorNumber(factor!),
        state.factorRunCount,
      ),
      LoadFactorStatus.unsupported => l10n.loadFactorUnsupported(
        factorNumber(factor!),
      ),
      LoadFactorStatus.profileNotApplicable => l10n.loadFactorNotApplicable,
    };

    final through = state.dataThrough;
    final dataText = through == null
        ? l10n.loadDataNone
        : l10n.loadDataThrough(material.formatMediumDate(through));
    final small = theme.bodySmall!.copyWith(color: c.textMuted);

    return [
      Text(profileText, key: const Key('load_profile'), style: theme.bodySmall),
      const SizedBox(height: 2),
      Text(factorText, key: const Key('load_factor'), style: theme.bodySmall),
      const SizedBox(height: 2),
      Text(dataText, key: const Key('load_data'), style: theme.bodySmall),
      const SizedBox(height: 6),
      Text(l10n.loadDataNote, key: const Key('load_note'), style: small),
    ];
  }
}

/// Kurzer Hinweis unter den Kennzahlen.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {required this.keyName});

  final String text;
  final String keyName;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        key: Key(keyName),
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(color: c.textMuted),
      ),
    );
  }
}

/// Aufklappbarer Bereich „Grundlage“: Kopfzeile mit mindestens 48 dp, als
/// Schalter mit Zustand für die Vorlesehilfe. Eingeklappt steht nichts davon
/// im Baum.
class _BasisSection extends StatefulWidget {
  const _BasisSection({
    required this.title,
    required this.children,
    required this.initiallyExpanded,
  });

  final String title;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<_BasisSection> createState() => _BasisSectionState();
}

class _BasisSectionState extends State<_BasisSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          excludeSemantics: true,
          label: widget.title,
          onTap: () => setState(() => _open = !_open),
          child: InkWell(
            key: const Key('load_basis_toggle'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _open = !_open),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: RamuriTheme.minTarget,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: theme.labelLarge!.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open)
          Column(
            key: const Key('load_basis'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.children,
          ),
      ],
    );
  }
}

/// Eine Kennzahl kompakt: Name, Wert, ggf. „vorläufig“. Die Spalte ist ein
/// zusammenhängender Satz für die Vorlesehilfe ([semanticsLabel] ist die
/// ausgeschriebene Bezeichnung).
class _Figure extends StatelessWidget {
  const _Figure({
    required this.keyName,
    required this.label,
    required this.semanticsLabel,
    required this.value,
    required this.provisional,
    this.swatch,
  });

  final String keyName;
  final String label;
  final String semanticsLabel;
  final String value;
  final bool provisional;
  final _Swatch? swatch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final mark = l10n.loadProvisionalMark;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: [semanticsLabel, value, if (provisional) mark].join(', '),
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.labelSmall!.copyWith(color: c.textMuted)),
            Text(
              value,
              key: Key(keyName),
              style: theme.titleMedium!.copyWith(fontWeight: FontWeight.w800),
            ),
            if (provisional)
              Row(
                key: Key('${keyName}_provisional'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmberDot(),
                  const SizedBox(width: 4),
                  Flexible(child: Text(mark, style: theme.labelSmall)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.swatch, required this.text, this.keyName});

  final _Swatch swatch;
  final String text;
  final String? keyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    return Row(
      key: keyName == null ? null : Key(keyName!),
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: theme.labelSmall!.copyWith(color: c.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Kleines Zeichen für Legende und Kennzahlen: Linienstück oder Tageszeichen.
class _Swatch extends StatelessWidget {
  const _Swatch.line(Color color, double width)
    : _color = color,
      _width = width,
      _flag = null,
      _colors = null;

  const _Swatch.marker(LoadDayFlag flag, RamuriColors colors)
    : _flag = flag,
      _colors = colors,
      _color = null,
      _width = 0;

  final Color? _color;
  final double _width;
  final LoadDayFlag? _flag;
  final RamuriColors? _colors;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: const Size(18, 12),
        painter: _SwatchPainter(_color, _width, _flag, _colors),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color, this.width, this.flag, this.colors);

  final Color? color;
  final double width;
  final LoadDayFlag? flag;
  final RamuriColors? colors;

  @override
  void paint(Canvas canvas, Size size) {
    final f = flag;
    if (f == null) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()
          ..color = color!
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    } else {
      LoadChartPainter.paintMarker(
        canvas,
        Offset(size.width / 2, size.height / 2),
        f,
        colors!,
      );
    }
  }

  @override
  bool shouldRepaint(_SwatchPainter old) =>
      old.color != color ||
      old.width != width ||
      old.flag != flag ||
      old.colors != colors;
}

/// Diagramm von ATL und CTL über die Tage: eine Skala von 0 bis [scaleMax],
/// darunter ein Streifen mit den gekennzeichneten Tagen. Linien reißen an
/// Tagen ohne Wert ab (vor dem ersten bewerteten Tag steht nichts, FR-0104).
class LoadChart extends StatelessWidget {
  const LoadChart({
    super.key,
    required this.days,
    required this.scaleMax,
    this.height = 130,
  });

  final List<LoadDay> days;
  final double scaleMax;
  final double height;

  /// Obergrenze der Skala: der größte Wert von ATL und CTL, aufgerundet, mind.
  /// 1. Eine Skala für beide Linien.
  static double scaleFor(List<LoadDay> days) {
    var m = 0.0;
    for (final d in days) {
      m = math.max(m, math.max(d.atl ?? 0, d.ctl ?? 0));
    }
    return math.max(1, m.ceilToDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: CustomPaint(
        painter: LoadChartPainter(days: days, scaleMax: scaleMax, colors: c),
      ),
    );
  }
}

/// Zeichner des Diagramms. Die Geometrie ist als statische Funktionen
/// ausgelegt, damit Tests Punkte und Zeichen prüfen können.
class LoadChartPainter extends CustomPainter {
  LoadChartPainter({
    required this.days,
    required this.scaleMax,
    required this.colors,
  });

  final List<LoadDay> days;
  final double scaleMax;
  final RamuriColors colors;

  /// Höhe des Streifens für die Tageszeichen unter der Grundlinie.
  static const double stripHeight = 16;
  static const double _pad = 4;

  /// Kantenlänge eines Tageszeichens.
  static const double markerSize = 8;

  /// x-Mitte des Tages [index] von [count] in der Breite [width].
  static double xOf(int index, int count, double width) {
    if (count <= 1) return width / 2;
    return _pad + (width - 2 * _pad) * index / (count - 1);
  }

  /// y eines Werts; 0 liegt an der Grundlinie, [scaleMax] oben.
  static double yOf(double value, double scaleMax, double plotHeight) =>
      _pad + (plotHeight - 2 * _pad) * (1 - value / scaleMax);

  /// Zusammenhängende Läufe von Tagen mit Wert (Indizes), getrennt an Tagen
  /// ohne Wert.
  static List<List<int>> runs(List<LoadDay> days, double? Function(LoadDay) v) {
    final out = <List<int>>[];
    var cur = <int>[];
    for (var i = 0; i < days.length; i++) {
      if (v(days[i]) == null) {
        if (cur.isNotEmpty) out.add(cur);
        cur = [];
      } else {
        cur.add(i);
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  /// Zeichen eines gekennzeichneten Tages. Die Form unterscheidet die Arten,
  /// nicht nur die Farbe: umgerechnet = Ring, unbewertet = gefüllte Raute,
  /// leer und unverändert = senkrechter Strich.
  static void paintMarker(
    Canvas canvas,
    Offset center,
    LoadDayFlag flag,
    RamuriColors c,
  ) {
    final r = markerSize / 2;
    switch (flag) {
      case LoadDayFlag.converted:
        canvas.drawCircle(
          center,
          r - 0.75,
          Paint()
            ..color = c.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case LoadDayFlag.unrated:
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - r)
            ..lineTo(center.dx + r, center.dy)
            ..lineTo(center.dx, center.dy + r)
            ..lineTo(center.dx - r, center.dy)
            ..close(),
          Paint()..color = c.ember,
        );
      case LoadDayFlag.emptyUnchanged:
        canvas.drawLine(
          Offset(center.dx, center.dy - r),
          Offset(center.dx, center.dy + r),
          Paint()
            ..color = c.textMuted
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
    }
  }

  void _line(
    Canvas canvas,
    Size size,
    double? Function(LoadDay) v,
    Color color,
    double width,
  ) {
    final plotH = size.height - stripHeight;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final run in runs(days, v)) {
      Offset at(int i) => Offset(
        xOf(i, days.length, size.width),
        yOf(v(days[i])!, scaleMax, plotH),
      );
      if (run.length == 1) {
        canvas.drawCircle(
          at(run.first),
          width / 2 + 0.5,
          Paint()..color = color,
        );
        continue;
      }
      final path = Path()..moveTo(at(run.first).dx, at(run.first).dy);
      for (final i in run.skip(1)) {
        path.lineTo(at(i).dx, at(i).dy);
      }
      canvas.drawPath(path, paint);
    }
    // Endpunkt: der aktuelle Wert.
    final last = runs(days, v).lastOrNull?.last;
    if (last != null && last == days.length - 1) {
      canvas.drawCircle(
        Offset(
          xOf(last, days.length, size.width),
          yOf(v(days[last])!, scaleMax, plotH),
        ),
        width / 2 + 2,
        Paint()..color = color,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final plotH = size.height - stripHeight;
    final grid = Paint()
      ..color = colors.outline
      ..strokeWidth = 1;
    // Grundlinie (0) und obere Linie (Skalenende).
    canvas.drawLine(
      Offset(0, plotH - _pad),
      Offset(size.width, plotH - _pad),
      grid,
    );
    canvas.drawLine(const Offset(0, _pad), Offset(size.width, _pad), grid);

    _line(canvas, size, (d) => d.ctl, colors.accent, 3.5);
    _line(canvas, size, (d) => d.atl, colors.ember, 2);

    for (var i = 0; i < days.length; i++) {
      final x = xOf(i, days.length, size.width);
      final y = plotH + stripHeight / 2 + 1;
      // Ein Tag kann mehrere Kennzeichen tragen; sie stehen nebeneinander.
      final flags = [
        for (final f in LoadDayFlag.values)
          if (days[i].flags.contains(f)) f,
      ];
      for (var k = 0; k < flags.length; k++) {
        paintMarker(
          canvas,
          Offset(x + (k - (flags.length - 1) / 2) * markerSize, y),
          flags[k],
          colors,
        );
      }
    }
  }

  @override
  bool shouldRepaint(LoadChartPainter old) =>
      old.days != days || old.scaleMax != scaleMax || old.colors != colors;
}
