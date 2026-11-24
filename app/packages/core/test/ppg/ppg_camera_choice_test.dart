// Kamerasuche (FR-0220): Lichtmenge, Fenster je Kamera und Empfehlung (PAR-219, PAR-227,
// PAR-228). Synthetische Zahlen, keine Messdaten.
import 'package:core/core.dart';
import 'package:test/test.dart';

const _a = PpgCameraRef('0');
const _b = PpgCameraRef('0', '2');
const _c = PpgCameraRef('1');

PpgCameraInfo _info(PpgCameraRef ref, {int? fps = 30, bool usable = true}) =>
    PpgCameraInfo(
      ref: ref,
      frameRate: fps,
      unusable: usable ? null : PpgCameraUnusable.noFlash,
    );

PpgCameraFinderState _st(
  PpgCameraRef ref, {
  int? fps = 30,
  bool finger = true,
  double? light = 1000,
  bool usable = true,
}) => PpgCameraFinderState(
  camera: _info(ref, fps: fps, usable: usable),
  fingerDetected: finger,
  light: light,
);

PpgPreviewFrame _f(
  double t, {
  double r = 200,
  double g = 40,
  int? exposureNs = 10000000,
  int? iso = 100,
}) => PpgPreviewFrame(
  camera: _a,
  t: t,
  r: r,
  g: g,
  exposureNs: exposureNs,
  iso: iso,
);

void main() {
  group('ppgCameraLight (PAR-228)', () {
    test('Rot / (Belichtungszeit in s × ISO / 100)', () {
      // 200 / (0,01 s × 200 / 100) = 10 000
      expect(ppgCameraLight(200, 40, 10000000, 200), closeTo(10000, 1e-9));
      // Gleiche Helligkeit bei halber Belichtung: doppelt so viel Licht.
      expect(ppgCameraLight(200, 40, 5000000, 200), closeTo(20000, 1e-9));
    });

    test('fehlende oder unbrauchbare Angabe → null', () {
      expect(ppgCameraLight(null, 40, 10000000, 100), isNull);
      expect(ppgCameraLight(200, null, 10000000, 100), isNull);
      expect(ppgCameraLight(200, 40, null, 100), isNull);
      expect(ppgCameraLight(200, 40, 10000000, null), isNull);
      expect(ppgCameraLight(200, 40, 0, 100), isNull);
      expect(ppgCameraLight(200, 40, 10000000, 0), isNull);
      expect(ppgCameraLight(double.nan, 40, 10000000, 100), isNull);
    });
  });

  group('Fenster je Kamera (PAR-219, PAR-227)', () {
    test('Finger bei R/G ≥ 1,5 und R > 0, genau an der Grenze ja', () {
      final w = PpgCameraFinderWindow(_info(_a))..add(_f(0, r: 150, g: 100));
      expect(w.state.fingerDetected, isTrue);
      final below = PpgCameraFinderWindow(_info(_a))
        ..add(_f(0, r: 149.9, g: 100));
      expect(below.state.fingerDetected, isFalse);
      final dark = PpgCameraFinderWindow(_info(_a))..add(_f(0, r: 0, g: 0));
      expect(dark.state.fingerDetected, isFalse);
      final neg = PpgCameraFinderWindow(_info(_a))..add(_f(0, r: -3, g: -4));
      expect(neg.state.fingerDetected, isFalse);
    });

    test('gleitendes Mittel nur über die letzten 1,5 s Sensorzeit', () {
      final w = PpgCameraFinderWindow(_info(_a))
        ..add(_f(0, r: 50, g: 100)) // kein Finger
        ..add(_f(1.0, r: 300, g: 40))
        ..add(_f(1.5, r: 300, g: 40));
      // Bild bei 0 s liegt genau 1,5 s zurück und zählt nicht mehr.
      expect(w.state.frames, 2);
      expect(w.state.fingerDetected, isTrue);
      expect(w.state.meanRed, 300);
      expect(w.state.light, closeTo(30000, 1e-9));
      w.add(_f(1.49 + 1.5, r: 50, g: 100));
      // 1,5 s liegt 1,49 s zurück und zählt noch.
      expect(w.state.frames, 2);
    });

    test('fallende Sensorzeit (neue Zählung) beginnt das Fenster neu', () {
      final w = PpgCameraFinderWindow(_info(_a))
        ..add(_f(1.0))
        ..add(_f(1.4))
        ..add(_f(0.5, r: 50, g: 100)); // kein Finger, Zeit kleiner als zuvor
      // Nur das neue Bild zählt; alte Bilder mischen sich nicht ins Fenster.
      expect(w.state.frames, 1);
      expect(w.state.fingerDetected, isFalse);
      expect(w.state.meanRed, 50);
    });

    test('Lichtmenge aus Bildern mit Angaben, ohne Angaben null', () {
      final w = PpgCameraFinderWindow(_info(_a))
        ..add(_f(0, exposureNs: null))
        ..add(_f(0.1, iso: null));
      expect(w.state.light, isNull);
      expect(w.state.fingerDetected, isTrue);
      w.add(_f(0.2));
      expect(w.state.light, closeTo(20000, 1e-9));
    });

    test('ohne Bild: kein Finger, keine Lichtmenge', () {
      final s = PpgCameraFinderWindow(_info(_a)).state;
      expect(s.fingerDetected, isFalse);
      expect(s.light, isNull);
    });
  });

  group('recommendPpgCamera (PAR-228)', () {
    test('Finger und größte Lichtmenge gewinnt', () {
      expect(
        recommendPpgCamera([
          _st(_a, light: 1000),
          _st(_b, light: 2000),
          _st(_c, light: 1500),
        ]),
        _b,
      );
    });

    test('ohne Finger nie, auch mit viel Licht', () {
      expect(
        recommendPpgCamera([
          _st(_a, light: 1000),
          _st(_b, light: 9000, finger: false),
        ]),
        _a,
      );
    });

    test('unter 10 % Abstand gewinnt die frühere in der Liste', () {
      // 1000 gegen 1099: 9,0 % weniger → frühere (a).
      expect(
        recommendPpgCamera([_st(_a, light: 1000), _st(_b, light: 1099)]),
        _a,
      );
      // 1000 gegen 1112: 10,07 % weniger → größere (b).
      expect(
        recommendPpgCamera([_st(_a, light: 1000), _st(_b, light: 1112)]),
        _b,
      );
      // Genau 10 %: nicht „weniger als“, die größere gewinnt.
      expect(
        recommendPpgCamera([_st(_a, light: 900), _st(_b, light: 1000)]),
        _b,
      );
      // Frühere ist die bessere: bleibt.
      expect(
        recommendPpgCamera([_st(_a, light: 1099), _st(_b, light: 1000)]),
        _a,
      );
      // Gleichstand: frühere.
      expect(
        recommendPpgCamera([_st(_a, light: 1000), _st(_b, light: 1000)]),
        _a,
      );
    });

    test('fehlende Lichtmenge: nicht empfohlen', () {
      expect(
        recommendPpgCamera([_st(_a, light: null), _st(_b, light: 10)]),
        _b,
      );
      expect(recommendPpgCamera([_st(_a, light: null)]), isNull);
    });

    test('nicht nutzbare Kamera: nicht empfohlen', () {
      expect(
        recommendPpgCamera([_st(_a, usable: false, light: 9000), _st(_b)]),
        _b,
      );
    });

    test('kein Finger auf keiner Kamera → keine Empfehlung', () {
      expect(
        recommendPpgCamera([_st(_a, finger: false), _st(_b, finger: false)]),
        isNull,
      );
      expect(recommendPpgCamera(const []), isNull);
    });

    test('60 Bilder/s vor doppelter Lichtmenge bei 30 Bilder/s', () {
      expect(
        recommendPpgCamera([
          _st(_a, fps: 30, light: 2000),
          _st(_b, fps: 60, light: 1000),
        ]),
        _b,
      );
    });

    test('60 Bilder/s ohne Finger → die mit 30 Bilder/s', () {
      expect(
        recommendPpgCamera([
          _st(_a, fps: 30, light: 2000),
          _st(_b, fps: 60, light: 1000, finger: false),
        ]),
        _a,
      );
    });

    test('zwei mit 60 Bilder/s und Finger → die mit mehr Licht', () {
      expect(
        recommendPpgCamera([
          _st(_a, fps: 60, light: 1000),
          _st(_b, fps: 60, light: 1500),
          _st(_c, fps: 30, light: 9000),
        ]),
        _b,
      );
    });

    test('unbekannte Bildrate zählt hinter 30 Bilder/s', () {
      expect(
        recommendPpgCamera([
          _st(_a, fps: null, light: 9000),
          _st(_b, fps: 30, light: 1000),
        ]),
        _b,
      );
    });
  });
}
