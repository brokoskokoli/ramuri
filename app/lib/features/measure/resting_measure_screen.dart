import 'package:flutter/material.dart';

import 'resting_entry_view.dart';
import 'resting_measure_controller.dart';
import 'resting_measuring_view.dart';
import 'resting_no_value_view.dart';
import 'resting_rest_view.dart';
import 'resting_result_view.dart';

/// Wie die Ruhepuls-Messung beendet wurde.
enum RestingMeasureOutcome {
  /// Wert ins Profil übernommen (bei [RestingMeasureController.originMissing]
  /// ohne Herkunft).
  adopted,

  /// Wert verworfen.
  discarded,

  /// Vom Nutzer abgebrochen.
  cancelled,

  /// Geschlossen ohne Übernahme (Zurück, Schließen, „Selbst eintragen“).
  dismissed,
}

/// Die Screens der Ruhepuls-Messung mit der Kamera (FR-0214, Design
/// `ruhepuls/*`): Einstieg, Ruhephase, Messung, Ergebnis, Kein Wert. Welcher
/// zu sehen ist, bestimmt die Phase des [controller]; der Controller gehört
/// dem Aufrufer (er legt ihn an und gibt ihn frei). Die Messung endet, wenn
/// die App wirklich in den Hintergrund geht ([AppLifecycleState.paused]); ein
/// Rechtedialog oder eine Systemleiste (`inactive`) bricht nichts ab.
class RestingMeasureScreen extends StatefulWidget {
  const RestingMeasureScreen({
    super.key,
    required this.controller,
    required this.soundOn,
    this.onClose,
  });

  final RestingMeasureController controller;

  /// Ton oder Vibration am Ende der Ruhephase. Der Aufrufer liest denselben
  /// Wert in seinem [RestingMeasureSignal].
  final ValueNotifier<bool> soundOn;

  /// Der Screen ist fertig; Vorgabe: `Navigator.maybePop`.
  final ValueChanged<RestingMeasureOutcome>? onClose;

  @override
  State<RestingMeasureScreen> createState() => _RestingMeasureScreenState();
}

class _RestingMeasureScreenState extends State<RestingMeasureScreen>
    with WidgetsBindingObserver {
  bool _closed = false;

  RestingMeasureController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(RestingMeasureScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_check);
      widget.controller.addListener(_check);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_check);
    super.dispose();
  }

  /// Nur `paused` ist ein Hintergrund (Bildschirm aus oder andere App vorn);
  /// `inactive` und `hidden` kommen auch bei Rechtedialog und Systemleisten.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _c.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      _c.onForeground();
    }
  }

  RestingMeasureOutcome? get _outcome => switch (_c.phase) {
    RestingMeasurePhase.adopted => RestingMeasureOutcome.adopted,
    RestingMeasurePhase.discarded => RestingMeasureOutcome.discarded,
    RestingMeasurePhase.stopped
        when _c.stopCause == RestingStopCause.userCancelled =>
      RestingMeasureOutcome.cancelled,
    _ => null,
  };

  void _check() {
    final o = _outcome;
    if (o != null) _close(o);
  }

  void _close(RestingMeasureOutcome o) {
    if (_closed || !mounted) return;
    _closed = true;
    final f = widget.onClose;
    if (f != null) {
      f(o);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool get _active => switch (_c.phase) {
    RestingMeasurePhase.resting ||
    RestingMeasurePhase.starting ||
    RestingMeasurePhase.measuring => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final Widget view = switch (_c.phase) {
          RestingMeasurePhase.entry => RestingEntryView(
            controller: _c,
            onClose: () => _close(RestingMeasureOutcome.dismissed),
          ),
          RestingMeasurePhase.resting => RestingRestView(
            controller: _c,
            soundOn: widget.soundOn,
          ),
          RestingMeasurePhase.starting ||
          RestingMeasurePhase.measuring => RestingMeasuringView(controller: _c),
          RestingMeasurePhase.result when _c.result?.hasValue ?? false =>
            RestingResultView(
              controller: _c,
              onClose: () => _close(RestingMeasureOutcome.dismissed),
            ),
          RestingMeasurePhase.adopted ||
          RestingMeasurePhase.discarded => const SizedBox.shrink(),
          _ => RestingNoValueView(
            controller: _c,
            onClose: () => _close(RestingMeasureOutcome.dismissed),
          ),
        };
        // Zurück während Ruhephase und Messung bricht ab, statt die Seite
        // mit laufender Kamera zu verlassen.
        return PopScope(
          canPop: !_active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _c.cancel();
          },
          child: view,
        );
      },
    );
  }
}
