import 'package:flutter/widgets.dart';

/// Ersatzbild der Kamerasuche ohne Texture (Debug-Quelle, FR-0220): eine Fläche in der
/// Farbe der gemessenen Bildmitte (Rot [r], Grün [g], Blau als Mittel der beiden; je
/// 0 bis 255). Mit Finger rot und hell, ohne Finger grau.
class PpgPreviewPatch extends StatelessWidget {
  const PpgPreviewPatch({super.key, required this.r, required this.g});

  final int r;
  final int g;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Color.fromARGB(
      255,
      r.clamp(0, 255),
      g.clamp(0, 255),
      ((r + g) / 2).round().clamp(0, 255),
    ),
  );
}
