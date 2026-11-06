import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../settings/app_settings.dart';
import 'live_run_view.dart';
import 'run_controller.dart';
import 'run_ports.dart';

/// Ablauf „Lauf starten“: Startprüfung (FR-0195), Live-Bildschirm
/// (FR-0026, FR-0027, FR-0028 bis FR-0030) und einfache Abschlussansicht.
/// Die Zusammenfassung baut WP10.
class RunFlowScreen extends StatefulWidget {
  const RunFlowScreen({
    super.key,
    required this.session,
    required this.clock,
    required this.ports,
    required this.permissions,
    this.tickEvery = const Duration(seconds: 1),
  });

  final StorageSession session;
  final Clock clock;
  final RunPorts ports;
  final PermissionStatusPort permissions;
  final Duration tickEvery;

  @override
  State<RunFlowScreen> createState() => _RunFlowScreenState();
}

class _RunFlowScreenState extends State<RunFlowScreen>
    with WidgetsBindingObserver {
  RunController? _controller;
  StartBlock? _block;
  bool _checking = true;

  /// Jede Prüfung bekommt eine Nummer; nur die jüngste zählt. So kann eine
  /// Antwort, die nach einer Neuerzeugung der Activity nie ankommt (oder
  /// `busy` ist), die Oberfläche nicht festhalten.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(askUser: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Zurück aus Systemdialog oder Einstellungen: Stand neu lesen, ohne zu
    // fragen. Das ersetzt auch eine verlorene Antwort auf die Anfrage.
    if (state == AppLifecycleState.resumed && _controller == null) {
      _check(askUser: false);
    }
  }

  Future<void> _check({required bool askUser}) async {
    final gen = ++_generation;
    setState(() => _checking = true);
    final result = await RecordingStartGate(widget.ports.access)
        .check(askUser: askUser);
    if (!mounted || gen != _generation) return;
    if (!result.canStart) {
      setState(() {
        _block = result.block;
        _checking = false;
      });
      return;
    }
    final controller = RunController(
      clock: widget.clock,
      storage: widget.session,
      location: widget.ports.location,
      heartRate: widget.ports.heartRate,
      tickEvery: widget.tickEvery,
    );
    setState(() {
      _controller = controller;
      _block = null;
      _checking = false;
    });
    await controller.start();
  }

  Future<void> _retryStart() async {
    await _controller?.start();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.homeStartRun)),
        body: _checking ? _checkingBody(l10n) : _blockBody(l10n),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.startFailed) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.homeStartRun)),
            body: _explanation(l10n, l10n.runStartFailed, [
              FilledButton(
                key: const Key('run_start_retry'),
                onPressed: _retryStart,
                child: Text(l10n.notOpenableRetry),
              ),
            ]),
          );
        }
        return LiveRunView(
          controller: controller,
          formatter: AppSettingsScope.formatterOf(context),
        );
      },
    );
  }

  Widget _checkingBody(AppLocalizations l10n) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(l10n.runChecking, key: const Key('run_checking')),
      ],
    ),
  );

  Widget _blockBody(AppLocalizations l10n) {
    final block = _block ?? StartBlock.unknown;
    final text = switch (block) {
      StartBlock.permissionDenied => l10n.runBlockPermissionDenied,
      StartBlock.approximateOnly => l10n.runBlockApproximate,
      StartBlock.gpsOff => l10n.runBlockGpsOff,
      StartBlock.unknown => l10n.runBlockUnknown,
    };
    final canAsk =
        block == StartBlock.permissionDenied ||
        block == StartBlock.approximateOnly;
    final canOpenSettings = canAsk;
    return _explanation(l10n, text, [
      if (canAsk)
        FilledButton(
          key: const Key('run_block_ask'),
          onPressed: () => _check(askUser: true),
          child: Text(l10n.runActionAsk),
        ),
      if (canOpenSettings)
        OutlinedButton(
          key: const Key('run_block_settings'),
          onPressed: () => widget.permissions.openSystemSettings(),
          child: Text(l10n.runActionSettings),
        ),
      // Ohne Abfrage lesen: nach Schalter oder Einstellungen genügt das.
      if (!canAsk)
        FilledButton(
          key: const Key('run_block_recheck'),
          onPressed: () => _check(askUser: false),
          child: Text(l10n.runActionRecheck),
        )
      else
        TextButton(
          key: const Key('run_block_recheck'),
          onPressed: () => _check(askUser: false),
          child: Text(l10n.runActionRecheck),
        ),
    ], blockKey: Key('run_block_${block.name}'));
  }

  Widget _explanation(
    AppLocalizations l10n,
    String text,
    List<Widget> actions, {
    Key? blockKey,
  }) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(l10n.runBlockTitle, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(text, key: blockKey ?? const Key('run_explanation')),
      const SizedBox(height: 16),
      for (final a in actions) ...[a, const SizedBox(height: 8)],
    ],
  );
}
