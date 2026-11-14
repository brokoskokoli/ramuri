import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Abschlussprüfung M2, Teil D (WP18-Punkt „sRPE kann nach fehlgeschlagener
/// Neuberechnung veraltet bleiben“): Scheitert das Nachziehen des sRPE nach
/// der neu gerechneten Kurzfassung, bleibt der Wert, weil die Kurzfassung
/// danach aktuell ist und nichts mehr nachzieht.
class _FailingSrpe implements RunSubjectiveStore {
  _FailingSrpe(this.i);
  final RunSubjectiveStore i;
  bool fail = true;
  @override
  Future<StoredRunSubjective?> read(int runId) => i.read(runId);
  @override
  Future<Map<int, StoredRunSubjective>> readAll() => i.readAll();
  @override
  Future<void> save(int runId, RunSubjective subjective, {SrpeLoad? srpe}) =>
      i.save(runId, subjective, srpe: srpe);
  @override
  Future<bool> setSrpe(int runId, SrpeLoad? srpe, {required int? expectedRpe}) {
    if (fail) throw const StorageException(StorageFailure.failed);
    return i.setSrpe(runId, srpe, expectedRpe: expectedRpe);
  }
}

class _Session implements StorageSession {
  _Session(this.s, this.subj);
  final StorageSession s;
  final RunSubjectiveStore subj;
  @override
  RawDataStore get rawData => s.rawData;
  @override
  RunStore get runs => s.runs;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  ProfileStore get profile => s.profile;
  @override
  SettingsStore get settings => s.settings;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  RunSubjectiveStore get subjective => subj;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

void main() {
  test(
    'sRPE folgt der Bewegungszeit auch nach einem gescheiterten Nachziehen',
    () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
      await w.session.subjective.save(id, RunSubjective(rpe: 5));
      final subj = _FailingSrpe(w.session.subjective);
      final session = _Session(w.session, subj);
      // Erste Anzeige: Kurzfassung gerechnet, sRPE schreiben scheitert.
      await RunOverviewService(session: session, clock: w.clock).load();
      expect((await w.session.subjective.read(id))!.srpe, isNull);
      // Die Kurzfassung bleibt veraltet, damit der nächste Aufruf nachzieht.
      expect(
        (await w.session.preprocessing.readOverviews())[id],
        isNull,
        reason: 'ohne sRPE keine als aktuell gespeicherte Kurzfassung',
      );
      // Später geht der Speicher wieder; die Historie wird erneut geöffnet.
      subj.fail = false;
      await RunOverviewService(session: session, clock: w.clock).load();
      final moving = (await w.session.preprocessing.read(id))!
          .summary
          .movingTime!;
      expect((await w.session.subjective.read(id))!.srpe?.duration, moving);
    },
  );
}
