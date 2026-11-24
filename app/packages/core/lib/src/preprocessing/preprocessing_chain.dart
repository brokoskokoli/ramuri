import 'altitude_processor.dart';
import 'heart_rate_processor.dart';
import 'movement_time_processor.dart';
import 'pace_processor.dart';
import 'position_processor.dart';
import 'section_quality.dart';
import 'settling_processor.dart';
import 'steps_series.dart';

/// Kettenversion der Vorverarbeitung (ADR-0004, NFR-0001, NFR-0005): ein
/// stabiler Text aus den Versionen aller Stufen, aus denen Laufwerte entstehen,
/// in fester Reihenfolge, z. B. `hr1.pace1.mov2.pos2.alt1.set1.sq2.st1`.
///
/// Jeder Laufwert trägt sie ([ComputedValue.preprocessingVersion]); weicht die
/// gespeicherte von der aktuellen ab, bietet die App eine Neuberechnung an
/// (`RecalculationService.checkVersions`). Jede neue Stufe mit eigener
/// `*MethodVersion` muss hier eingetragen werden; ein Test findet alle
/// Konstanten in `preprocessing/` und seinen Unterordnern und prüft das.
///
/// Die Parameter dienen nur Tests (eine Stufe um 1 erhöht); die App ruft die
/// Funktion ohne Argumente.
String preprocessingChainVersion({
  int heartRate = heartRateMethodVersion,
  int pace = paceMethodVersion,
  int movement = movementMethodVersion,
  int position = positionMethodVersion,
  int altitude = altitudeMethodVersion,
  int settling = settlingMethodVersion,
  int sectionQuality = sectionQualityMethodVersion,
  int steps = stepsMethodVersion,
}) => [
  'hr$heartRate',
  'pace$pace',
  'mov$movement',
  'pos$position',
  'alt$altitude',
  'set$settling',
  'sq$sectionQuality',
  'st$steps',
].join('.');

/// Kettenversion der Werte, die vor Schema 19 gespeichert wurden (die Spalte
/// gab es noch nicht): die Versionen der Stufen zu diesem Zeitpunkt. Die
/// Migration und der Reimport eines älteren Archivs setzen sie an jeden
/// Laufwert. Fest, nie an eine neue Stufenversion anpassen: sonst entstünde
/// für Werte, die mit der alten Kette gerechnet sind, kein Angebot.
const String legacyPreprocessingChainVersion =
    'hr1.pace1.mov2.pos2.alt1.set1.sq2.st1';
