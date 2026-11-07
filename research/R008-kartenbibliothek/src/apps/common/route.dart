// R008: synthetische Laeufe auf dem Tempelhofer Feld (oeffentliche Flaeche, keine Person).
// Ellipse mit Rauschen, Seed je Lauf; Lauf 0 ist die Live-Strecke.
import 'dart:math';

class P {
  const P(this.lat, this.lon);
  final double lat, lon;
}

const centerLat = 52.4731, centerLon = 13.4031;

List<P> syntheticRun(int seed, {int n = 600}) {
  final r = Random(seed);
  final a = 0.0040 + r.nextDouble() * 0.0020; // Halbachse Breite in Grad (~450-670 m)
  final b = 0.0060 + r.nextDouble() * 0.0040; // Halbachse Laenge in Grad
  final dl = (r.nextDouble() - 0.5) * 0.004, dn = (r.nextDouble() - 0.5) * 0.006;
  final rot = r.nextDouble() * pi;
  final out = <P>[];
  for (var i = 0; i < n; i++) {
    final t = 2 * pi * i / n;
    final x = b * cos(t), y = a * sin(t);
    final xr = x * cos(rot) - y * sin(rot), yr = x * sin(rot) + y * cos(rot);
    out.add(P(centerLat + dl + yr + (r.nextDouble() - 0.5) * 0.00004, centerLon + dn + xr + (r.nextDouble() - 0.5) * 0.00006));
  }
  return out;
}
