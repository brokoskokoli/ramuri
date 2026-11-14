import 'package:flutter/material.dart';

import 'morning_entry_view.dart';
import 'morning_measure_controller.dart';
import 'morning_result_view.dart';
import 'resting_measure_controller.dart';
import 'resting_measuring_view.dart';
import 'resting_no_value_view.dart';
import 'resting_rest_view.dart';

/// Die Screens der Morgenmessung (FR-0215, Design `morgen/*`): Einstieg,
/// Ruhephase, Messung, Ergebnis. Messung und Ruhephase sind die Ansichten aus
/// WP27; welche zu sehen ist, bestimmt die Phase der Messung im [controller].
/// Der Controller gehört dem Aufrufer. Die Messung endet, wenn die App wirklich
/// in den Hintergrund geht (`paused`), wie bei der Ruhepuls-Messung.
class MorningMeasureScreen extends StatefulWidget {
  const MorningMeasureScreen({
    super.key,
    required this.controller,
    required this.soundOn,
    this.onClose,
  });

  final MorningMeasureController controller;

  /// Ton oder Vibration am Ende der Ruhephase (derselbe Wert im Signal).
  final ValueNotifier<bool> soundOn;

  /// Der Screen ist fertig; Vorgabe: `Navigator.maybePop`.
  final VoidCallback? onClose;

  @override
  State<MorningMeasureScreen> createState() => _MorningMeasureScreenState();
}

class _MorningMeasureScreenState extends State<MorningMeasureScreen>
    with WidgetsBindingObserver {
  bool _closed = false;

  MorningMeasureController get _c => widget.controller;
  RestingMeasureController get _e => _c.engine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _e.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _e.removeListener(_check);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _e.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      _e.onForeground();
    }
  }

  void _check() {
    if (_e.phase == RestingMeasurePhase.stopped &&
        _e.stopCause == RestingStopCause.userCancelled) {
      _close();
    }
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    final f = widget.onClose;
    if (f != null) {
      f();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool get _active => switch (_e.phase) {
    RestingMeasurePhase.resting ||
    RestingMeasurePhase.starting ||
    RestingMeasurePhase.measuring => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _e]),
      builder: (context, _) {
        final Widget view = switch (_e.phase) {
          RestingMeasurePhase.entry => MorningEntryView(
            controller: _c,
            onClose: _close,
          ),
          RestingMeasurePhase.resting => RestingRestView(
            controller: _e,
            soundOn: widget.soundOn,
            allowSkip: false,
          ),
          RestingMeasurePhase.starting ||
          RestingMeasurePhase.measuring => RestingMeasuringView(controller: _e),
          RestingMeasurePhase.result => MorningResultView(
            controller: _c,
            onClose: _close,
          ),
          _ => RestingNoValueView(controller: _e, onClose: _close),
        };
        // Zurück während Ruhephase und Messung bricht ab, statt die Seite mit
        // laufender Kamera zu verlassen.
        return PopScope(
          canPop: !_active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _active) _e.cancel();
          },
          child: view,
        );
      },
    );
  }
}
