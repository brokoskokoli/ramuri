import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../export/file_handoff_scope.dart';

/// Messpaare Kamera und Gurt im Abschnitt Entwickler auf „Über“ (WP33 Teil E,
/// K62 F4, Design `morgen/Ueber`): Zahl der Morgen mit und ohne Gurt-RR und der
/// Knopf „Messpaare als CSV teilen“. Vor dem Teilen warnt ein Dialog, dass die
/// Datei unverschlüsselt ist (wie bei der Zusatzmetriken-CSV, K57). Erst „Teilen“
/// im Dialog erzeugt und übergibt die Datei. Meldungen enthalten weder Werte
/// noch Pfade. Die App zeigt keine Gurt-RMSSD und keine Differenzen.
class MorningPairsSection extends StatefulWidget {
  const MorningPairsSection({super.key, required this.store, this.clock});

  final MorningStore store;

  /// Zeitquelle für den Dateinamen; ohne Angabe die Systemzeit.
  final DateTime Function()? clock;

  @override
  State<MorningPairsSection> createState() => _MorningPairsSectionState();
}

class _MorningPairsSectionState extends State<MorningPairsSection> {
  late final Future<({int withBelt, int without})?> _count = _load();
  bool _busy = false;

  Future<({int withBelt, int without})?> _load() async {
    try {
      return await countMorningPairs(widget.store);
    } on Object {
      return null;
    }
  }

  Future<void> _share(FileHandoff handoff) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _WarnDialog(),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    FileHandoffResult result;
    try {
      final file = await buildMorningPairsCsvFile(
        widget.store,
        now: (widget.clock ?? DateTime.now)(),
      );
      result = await handoff.share(file);
    } on Object {
      result = FileHandoffResult.failed;
    }
    if (mounted) setState(() => _busy = false);
    final message = switch (result) {
      FileHandoffResult.completed => l10n.exportShared,
      FileHandoffResult.cancelled => null,
      FileHandoffResult.failed => l10n.exportFailed,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final handoff = FileHandoffScope.of(context);
    return Padding(
      key: const Key('about_pairs'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.devPairsTitle, style: theme.titleSmall),
          const SizedBox(height: 4),
          FutureBuilder<({int withBelt, int without})?>(
            future: _count,
            builder: (context, snap) {
              final n = snap.data;
              return Text(
                n == null ? '' : l10n.devPairsCount(n.withBelt, n.without),
                key: const Key('about_pairs_count'),
                style: theme.bodySmall!.copyWith(color: c.textMuted),
              );
            },
          ),
          if (handoff != null) ...[
            const SizedBox(height: 12),
            RamuriSecondaryButton(
              key: const Key('about_pairs_share'),
              onPressed: _busy ? null : () => _share(handoff),
              label: l10n.devPairsShare,
            ),
          ],
        ],
      ),
    );
  }
}

class _WarnDialog extends StatelessWidget {
  const _WarnDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('about_pairs_dialog'),
      title: Text(l10n.devPairsWarnTitle),
      content: Text(l10n.devPairsWarnBody),
      actions: [
        TextButton(
          key: const Key('about_pairs_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.exportCancel),
        ),
        FilledButton(
          key: const Key('about_pairs_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.exportShare),
        ),
      ],
    );
  }
}
