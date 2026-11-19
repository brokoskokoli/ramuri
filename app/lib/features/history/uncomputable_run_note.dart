import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Satz in der Detailansicht eines Laufs, dessen Werte sich nach drei
/// Versuchen nicht berechnen ließen (FR-0219). Sonst und bei einem Lesefehler
/// bleibt die Stelle leer. Nur Anzeige.
class UncomputableRunNote extends StatefulWidget {
  const UncomputableRunNote({
    super.key,
    required this.session,
    required this.clock,
    required this.runId,
  });

  final StorageSession session;
  final Clock clock;
  final int runId;

  @override
  State<UncomputableRunNote> createState() => _UncomputableRunNoteState();
}

class _UncomputableRunNoteState extends State<UncomputableRunNote> {
  late final Future<bool> _uncomputable = _read();

  Future<bool> _read() async {
    try {
      return (await CalculationFailures(
        settings: widget.session.settings,
        clock: widget.clock,
      ).uncomputable()).contains(widget.runId);
    } on Object {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _uncomputable,
    builder: (context, snap) {
      if (snap.data != true) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: RamuriCard(
          key: const Key('detail_uncomputable'),
          radius: 18,
          padding: const EdgeInsets.all(14),
          child: Text(
            AppLocalizations.of(context).detailUncomputable,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    },
  );
}
