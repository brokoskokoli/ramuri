import 'package:flutter/material.dart';

/// Hauptknopf: Minze, Pille, 56 dp hoch. Die Breite bestimmt der Aufrufer
/// (etwa `Expanded` in einer Zeile).
class RamuriPrimaryButton extends StatelessWidget {
  const RamuriPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return icon == null
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}

/// Nebenknopf: Pille mit Rand, 56 dp hoch.
class RamuriSecondaryButton extends StatelessWidget {
  const RamuriSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return icon == null
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
  }
}

/// Stil für Knöpfe, die Daten unwiderruflich löschen: Fehlerrot statt
/// Minze (gefüllt, für die Bestätigung im Dialog).
ButtonStyle ramuriDangerFilledStyle(BuildContext context) {
  // Das Theme belegt `error` mit `danger` (ramuri_theme.dart).
  final scheme = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: scheme.error,
    foregroundColor: scheme.onError,
  );
}

/// Wie [ramuriDangerFilledStyle], mit Rand statt Fläche (für den Knopf, der
/// den Dialog erst öffnet).
ButtonStyle ramuriDangerOutlinedStyle(BuildContext context) {
  final color = Theme.of(context).colorScheme.error;
  return OutlinedButton.styleFrom(
    foregroundColor: color,
    side: BorderSide(color: color, width: 1.5),
  );
}
