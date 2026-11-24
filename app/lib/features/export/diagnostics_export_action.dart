import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../error_counter.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import 'file_handoff_scope.dart';

/// Formatversion des Diagnose-Exports (`docs/contracts/diagnostics-export.md`).
const int diagnosticsFormatVersion = 1;

/// Kennung des Formats im Feld `format`.
const String diagnosticsFormat = 'ramuri-diagnose';

/// Einträge nach Anzahl absteigend; bei gleicher Anzahl nach Typ, dann Ort
/// (Anzeige und Export, FR-0223).
List<ErrorCount> sortErrorCounts(Iterable<ErrorCount> entries) =>
    List.of(entries)..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      final byType = a.type.compareTo(b.type);
      return byType != 0 ? byType : a.place.compareTo(b.place);
    });

/// Zeitraum der Einträge: frühester erster und spätester letzter Tag;
/// `null`-Felder, wenn kein Eintrag einen Tag trägt.
({String? from, String? to}) errorCountPeriod(Iterable<ErrorCount> entries) {
  String? from;
  String? to;
  for (final e in entries) {
    final f = e.firstDay;
    final l = e.lastDay;
    if (f != null && (from == null || f.compareTo(from) < 0)) from = f;
    if (l != null && (to == null || l.compareTo(to) > 0)) to = l;
  }
  return (from: from, to: to);
}

/// Inhalt der Diagnose-Datei (JSON, UTF-8): Formatversion, App-Version,
/// Zeitraum und je Eintrag nur Typ, Ort und Anzahl. Sonst nichts – keine
/// Gerätekennung, keine Läufe, keine Werte, keine Nachrichten oder Stacks
/// (FR-0223, SEC-0008).
String diagnosticsJson(
  Iterable<ErrorCount> entries, {
  required String? appVersion,
}) {
  final period = errorCountPeriod(entries);
  return const JsonEncoder.withIndent('  ').convert({
    'format': diagnosticsFormat,
    'formatVersion': diagnosticsFormatVersion,
    'appVersion': appVersion,
    'from': period.from,
    'to': period.to,
    'errors': [
      for (final e in sortErrorCounts(entries))
        {'type': e.type, 'place': e.place, 'count': e.count},
    ],
  });
}

/// Dateiname `ramuri-diagnose-JJJJMMTT.json` mit dem Kalendertag von [now].
String diagnosticsFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final y = now.year.toString().padLeft(4, '0');
  return 'ramuri-diagnose-$y${two(now.month)}${two(now.day)}.json';
}

/// Die Datei für das Teilen-Menü; der Inhalt ist [text] aus
/// [diagnosticsJson]. Die Plattform legt sie im Export-Cache ab, der wie bei
/// jedem Export geleert wird (`docs/contracts/file-export.md`).
ExportFile diagnosticsFile(String text, {required DateTime now}) => ExportFile(
  fileName: diagnosticsFileName(now),
  mimeType: 'application/json',
  bytes: Uint8List.fromList(utf8.encode(text)),
);

/// Schaltfläche „Diagnose teilen“ in den Entwicklereinstellungen (FR-0223).
/// Der Dialog zeigt den Inhalt der Datei; erst „Teilen“ dort erzeugt die Datei
/// und gibt sie an das Teilen-Menü des Systems (FR-0201). Kein Netz, keine
/// automatische Übertragung. Meldungen enthalten weder Inhalte noch Pfade.
class DiagnosticsExportAction extends StatelessWidget {
  const DiagnosticsExportAction({
    super.key,
    required this.errors,
    required this.appVersion,
    this.clock,
  });

  final ErrorCounter errors;

  /// Quelle der App-Version; `null` ergibt `appVersion: null` in der Datei.
  final Future<String?> Function() appVersion;

  /// Zeitquelle für den Dateinamen; ohne Angabe die Systemzeit.
  final DateTime Function()? clock;

  Future<void> _open(BuildContext context, FileHandoff handoff) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    String text;
    try {
      final entries = await errors.read();
      String? version;
      try {
        version = await appVersion();
      } on Object {
        version = null;
      }
      text = diagnosticsJson(entries, appVersion: version);
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.exportFailed)));
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DiagnosticsDialog(text: text),
    );
    if (ok != true) return;
    FileHandoffResult result;
    try {
      result = await handoff.share(
        diagnosticsFile(text, now: (clock ?? DateTime.now)()),
      );
    } on Object {
      result = FileHandoffResult.failed;
    }
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
    final handoff = FileHandoffScope.of(context);
    if (handoff == null) return const SizedBox.shrink();
    return RamuriSecondaryButton(
      key: const Key('dev_errors_share'),
      onPressed: () => _open(context, handoff),
      label: AppLocalizations.of(context).devErrorsShare,
    );
  }
}

class _DiagnosticsDialog extends StatelessWidget {
  const _DiagnosticsDialog({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('dev_errors_share_dialog'),
      title: Text(l10n.devErrorsShareTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.devErrorsShareBody),
            const SizedBox(height: 12),
            SelectableText(
              text,
              key: const Key('dev_errors_share_content'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('dev_errors_share_cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.exportCancel),
        ),
        FilledButton(
          key: const Key('dev_errors_share_confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.exportShare),
        ),
      ],
    );
  }
}
