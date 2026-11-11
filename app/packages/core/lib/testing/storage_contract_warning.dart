import '../core.dart';
import 'contract_support.dart';

/// Vertrag des Warnsignals (WP23 Teil B1). Der Speicher muss
/// [WarningStorage] sein.
final List<StorageContractCase> warningContractCases = [
  const StorageContractCase(
    'Warnsignal: setzen, ersetzen (höchstens eines), aufheben, Neuöffnen',
    _lifecycle,
  ),
  const StorageContractCase(
    'Warnsignal: Aufheben ohne Warnsignal ist ein Nichts; ungültige Lauf-ID',
    _lift,
  ),
  const StorageContractCase(
    'Warnsignal übersteht das Löschen seines Laufs und jedes anderen',
    _deleteRun,
  ),
  const StorageContractCase(
    'Alles löschen entfernt Warnsignal und Zusatzzustände (settings)',
    _deleteAll,
  ),
  const StorageContractCase(
    'Zusatzzustände: Rundgang über settings, Unlesbares gilt als leer',
    _state,
  ),
];

WarningStore _w(StorageSession s) => (s as WarningStorage).warning;

String _d(WarningSignal? w) => w == null
    ? 'null'
    : '${w.reportedOn.toIso8601String()}/${w.source.name}/${w.runId}';

Future<void> _lifecycle(StorageContractHarness h) async {
  var s = await h.open();
  expectTrue(await _w(s).read() == null, 'ohne Warnsignal null');
  final run = (await s.runs.create(startedAt: at(0))).id;
  final a = WarningSignal(
    reportedOn: DateTime(2030, 3, 4, 23, 59),
    source: WarningSource.runFeedback,
    runId: run,
  );
  await _w(s).set(a);
  expectEq(_d(await _w(s).read()), _d(a), 'gelesen (Ortstag, Quelle, Lauf)');
  expectEq(
    (await _w(s).read())!.reportedOn,
    DateTime.utc(2030, 3, 4),
    'Ortstag ohne Uhrzeit',
  );
  final b = WarningSignal(
    reportedOn: DateTime(2030, 3, 9),
    source: WarningSource.manual,
  );
  await _w(s).set(b);
  expectEq(_d(await _w(s).read()), _d(b), 'ersetzt, ohne Lauf');
  await s.close();
  s = await h.open();
  expectEq(_d(await _w(s).read()), _d(b), 'nach Neuöffnen');
  await _w(s).lift();
  expectTrue(await _w(s).read() == null, 'nach Aufheben null');
  await s.close();
  s = await h.open();
  expectTrue(await _w(s).read() == null, 'nach Neuöffnen null');
  await s.close();
}

Future<void> _lift(StorageContractHarness h) async {
  final s = await h.open();
  await _w(s).lift();
  await _w(s).lift();
  await expectFails(
    () => _w(s).set(
      WarningSignal(
        reportedOn: DateTime(2030, 3, 4),
        source: WarningSource.manual,
        runId: 0,
      ),
    ),
    StorageFailure.rejected,
    'Lauf-ID 0',
  );
  expectTrue(await _w(s).read() == null, 'nichts geschrieben');
  // Kein Fremdschlüssel: Ein Lauf, den es nicht gibt, wird angenommen.
  await _w(s).set(
    WarningSignal(
      reportedOn: DateTime(2030, 3, 4),
      source: WarningSource.runFeedback,
      runId: 4711,
    ),
  );
  expectEq((await _w(s).read())!.runId, 4711, 'Lauf ohne Fremdschlüssel');
  await s.close();
}

Future<void> _deleteRun(StorageContractHarness h) async {
  final s = await h.open();
  final a = (await s.runs.create(startedAt: at(0))).id;
  final b = (await s.runs.create(startedAt: at(1))).id;
  final w = WarningSignal(
    reportedOn: DateTime(2030, 3, 4),
    source: WarningSource.runFeedback,
    runId: a,
  );
  await _w(s).set(w);
  await s.deleteRun(b);
  expectEq(_d(await _w(s).read()), _d(w), 'nach Löschen eines anderen Laufs');
  await s.deleteRun(a);
  expectEq(_d(await _w(s).read()), _d(w), 'nach Löschen des eigenen Laufs');
  await s.close();
}

Future<void> _deleteAll(StorageContractHarness h) async {
  var s = await h.open();
  final st = WarningState(s.settings);
  await _w(s).set(
    WarningSignal(
      reportedOn: DateTime(2030, 3, 4),
      source: WarningSource.manual,
    ),
  );
  await st.setLastPromptOn(DateTime(2030, 3, 11), at: at(1));
  await st.setPauseAnswer(
    PauseAnswer(paused: true, on: DateTime(2030, 3, 12)),
    at: at(2),
  );
  await st.setHintBlockedUntil(DateTime(2030, 4, 1), at: at(3));
  await st.setPlanChangeSeen(5, at: at(4));
  expectEq((await s.settings.all()).length, 4, 'vier Zusatzzustände');
  await s.deleteAll();
  expectTrue(await _w(s).read() == null, 'Warnsignal nach Alles löschen');
  expectEq((await s.settings.all()).length, 0, 'Zusatzzustände gelöscht');
  await s.close();
  s = await h.open();
  expectTrue(await _w(s).read() == null, 'nach Neuöffnen');
  expectEq((await s.settings.all()).length, 0, 'nach Neuöffnen: settings leer');
  await s.close();
}

Future<void> _state(StorageContractHarness h) async {
  var s = await h.open();
  var st = WarningState(s.settings);
  expectTrue(await st.lastPromptOn() == null, 'leer: Nachfrage');
  expectTrue(await st.pauseAnswer() == null, 'leer: Pausenantwort');
  expectTrue(await st.hintBlockedUntil() == null, 'leer: Sperre');
  expectTrue(await st.planChangeSeen() == null, 'leer: gesehen');
  await st.setLastPromptOn(DateTime(2030, 3, 11, 8), at: at(1));
  await st.setPauseAnswer(
    PauseAnswer(paused: false, on: DateTime(2030, 3, 12)),
    at: at(2),
  );
  await st.setHintBlockedUntil(DateTime(2030, 4, 1), at: at(3));
  await st.setPlanChangeSeen(12, at: at(4));
  await s.close();
  s = await h.open();
  st = WarningState(s.settings);
  expectEq(await st.lastPromptOn(), DateTime.utc(2030, 3, 11), 'Nachfrage');
  expectTrue(
    await st.pauseAnswer() ==
        PauseAnswer(paused: false, on: DateTime(2030, 3, 12)),
    'Pausenantwort',
  );
  expectEq(await st.hintBlockedUntil(), DateTime.utc(2030, 4, 1), 'Sperre');
  expectEq(await st.planChangeSeen(), 12, 'gesehen');
  // Die Schlüssel stehen wirklich in settings (daher im Archiv).
  expectEq(
    (await s.settings.all()).keys.toList()..sort(),
    [
      WarningSettingKeys.hintBlockedUntil,
      WarningSettingKeys.lastPromptOn,
      WarningSettingKeys.pauseAnswer,
      WarningSettingKeys.planChangeSeen,
    ]..sort(),
    'Schlüssel',
  );
  // Unlesbare Werte gelten als fehlend, ohne Ausnahme.
  await s.settings.set(
    WarningSettingKeys.lastPromptOn,
    '2030-02-30',
    at: at(5),
  );
  await s.settings.set(
    WarningSettingKeys.pauseAnswer,
    'maybe:2030-03-12',
    at: at(5),
  );
  await s.settings.set(WarningSettingKeys.hintBlockedUntil, 'x', at: at(5));
  await s.settings.set(WarningSettingKeys.planChangeSeen, '-3', at: at(5));
  expectTrue(await st.lastPromptOn() == null, 'Datum 30. Februar');
  expectTrue(await st.pauseAnswer() == null, 'unbekannte Antwort');
  expectTrue(await st.hintBlockedUntil() == null, 'Text statt Datum');
  expectTrue(await st.planChangeSeen() == null, 'negative Kennung');
  await expectFails(
    () => st.setPlanChangeSeen(0, at: at(6)),
    StorageFailure.rejected,
    'Kennung 0',
  );
  await s.close();
}
