import '../src/prediction/reference_performance.dart';
import 'storage.dart' show StorageException, StorageFailure;

/// Gespeicherte Referenzleistung mit ihrer Kennung (zum Löschen).
class StoredReference {
  const StoredReference({required this.id, required this.reference});

  final int id;
  final ReferencePerformance reference;
}

/// Referenzleistungen und abgelehnte Vorschläge der Leistungsprognose
/// (FR-0129, FR-0131). Eine Referenz oder Ablehnung mit Lauf-ID hängt am Lauf:
/// Wird der Lauf gelöscht ([StorageSession.deleteRun]) oder alles
/// ([StorageSession.deleteAll]), verschwinden sie mit.
abstract interface class PredictionStore {
  /// Legt eine Referenz an und gibt ihre Kennung zurück. Ungültig
  /// ([ReferencePerformance.validate] zum Anlegezeitpunkt `createdAt`, oder ein
  /// bestätigter Lauf ohne Lauf-ID): `rejected`, nichts wird geschrieben. Eine
  /// Lauf-ID, die es nicht gibt: `rejected`. Idempotent je Lauf: Ist der Lauf
  /// schon als Referenz gespeichert, entsteht keine zweite Zeile und die
  /// vorhandene Kennung kommt zurück.
  Future<int> addReference(ReferencePerformance reference);

  /// Löscht eine Referenz. Unbekannte Kennung: `notFound`. Stammt sie aus
  /// einem bestätigten Lauf, wird in derselben Transaktion der Vorschlag für
  /// diesen Lauf abgelehnt (wie [rejectSuggestion]); manuelle Referenzen
  /// hinterlassen nichts.
  Future<void> deleteReference(int id);

  /// Alle Referenzen, jüngste zuerst (nach Datum, bei gleichem Datum die
  /// zuletzt angelegte), auch unbrauchbare (z. B. importiert außerhalb der
  /// Tempospanne); [activeReference] ist die erste brauchbare.
  Future<List<StoredReference>> references();

  /// Die geltende Referenz nach `activeReference` in `core` (jüngste
  /// brauchbare, [isUsableReference]) oder `null`.
  Future<ReferencePerformance?> activeReference();

  /// Lehnt den Vorschlag für den Lauf ab (idempotent). Unbekannter Lauf:
  /// `notFound`.
  Future<void> rejectSuggestion(int runId);

  /// Läufe, deren Vorschlag abgelehnt wurde.
  Future<Set<int>> rejectedSuggestions();
}

/// Ein Speicher, der die Prognose-Daten führt. Bewusst getrennt von
/// [StorageSession], damit dessen Implementierungen (und Test-Doubles) sich
/// nicht ändern; [EncryptedStorageSession] und der Fake tragen beides.
abstract interface class PredictionStorage {
  PredictionStore get prediction;
}

/// Prüfung vor dem Speichern, gleich für Fake und Datenbank: gültig nach
/// [ReferencePerformance.validate] zum Anlegezeitpunkt und ein bestätigter
/// Lauf mit Lauf-ID. Sonst `rejected`.
void checkReferenceForStorage(ReferencePerformance r) {
  if (r.validate(r.createdAt) != null ||
      (r.kind == ReferenceKind.confirmedRun && r.runId == null)) {
    throw const StorageException(StorageFailure.rejected);
  }
}

/// Jüngste zuerst: nach Datum, bei gleichem Datum die zuletzt angelegte, dann
/// die höhere Kennung. Das erste Element ist die geltende Referenz.
List<StoredReference> sortedReferences(Iterable<StoredReference> all) {
  final out = all.toList();
  out.sort((a, b) {
    final x = a.reference, y = b.reference;
    final d = calendarDay(y.date).compareTo(calendarDay(x.date));
    if (d != 0) return d;
    final c = y.createdAt.compareTo(x.createdAt);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  return out;
}
