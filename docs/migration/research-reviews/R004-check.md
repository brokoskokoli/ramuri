# Gezielte Prüfung der R004-Korrekturen

Bezug: [R004-fixes.md](R004-fixes.md). Keine volle Prüfrunde und keine unabhängige Prüfung. Geprüft wurden die Rechnung (Skript aus R004-fixes neu ausgeführt, Ausgabe identisch), die Prüfsummen und die Übereinstimmung der geänderten Regeln und Specs.

## Befunde

| Befund | Stelle | Ergebnis |
|---|---|---|
| Ein späteres Datum konnte schlechter gelten als ein früheres, Verstoß gegen FR-0154. Das Skript aus R004-fixes prüft nur PAR-084. | PAR-083 | Korrigiert: Die erlaubte Verbesserung insgesamt sinkt über 12 Wochen nie unter den Wert bei 12 Wochen. Empfehlung ohne Präferenz des Maintainers, änderbar. |
| Hinweis auf einen 5-km-Test, den der Plan ausschließt | FR-0129, PAR-143, PAR-117 | Korrigiert: Der Hinweis folgt PAR-117. Empfehlung ohne Präferenz des Maintainers, änderbar. |
| 5-km-Zeitziel dauert länger als 10 km (33 gegen 26 Wochen) | PAR-084 | Bleibt, entschieden vom Maintainer. |
| RPE-Wörter unbestätigt | PAR-105 | Bestätigt vom Maintainer. |
| „Mit Ja kommen 4 Wochen dazu“ war mehrdeutig | PAR-068 | Wortlaut präzisiert, Werte unverändert. |

## Rechnung zu PAR-083

```python
"""PAR-083 nach DEC-0059: spaeteres Datum nie schlechter (FR-0154). Lauf: python3 -I par083_final.py"""
EPS = 1e-12
BASE = {"Einsteiger": (.5, 1.0), "Aufbau": (.3, .6), "Erfahren": (.225, .45)}
def total(limit, n, floor=True):
    """Erlaubte Verbesserung insgesamt in %. Erfahren ist schon um ein Viertel gesenkt."""
    f = limit if limit == .225 or limit == .45 or n <= 12 else limit * .75
    return max(f * n, limit * 12) if floor and n > 12 else f * n
def stufe(x, n, s, floor):
    a, b = BASE[s]
    return 2 if x <= total(a, n, floor) + EPS else 1 if x <= total(b, n, floor) + EPS else 0
for floor in (False, True):
    for s in BASE:
        bad, diff = 0, set()
        for xi in range(1, 3001):
            v = [stufe(xi / 100, n, s, floor) for n in range(1, 61)]
            bad += any(p > q for p, q in zip(v, v[1:]))
            if floor:
                diff |= {n for n in range(1, 61) if stufe(xi / 100, n, s, False) != v[n - 1]}
        print("mit Untergrenze" if floor else "vorher", s, "Faelle mit Fehler:", bad, "geaenderte Laengen:", sorted(diff) if floor else "-")
print("Aufbau 3,3 %:", [(n, stufe(3.3, n, "Aufbau", True)) for n in range(11, 17)])
```

```text
vorher Einsteiger Faelle mit Fehler: 338 geaenderte Laengen: -
vorher Aufbau Faelle mit Fehler: 203 geaenderte Laengen: -
vorher Erfahren Faelle mit Fehler: 0 geaenderte Laengen: -
mit Untergrenze Einsteiger Faelle mit Fehler: 0 geaenderte Laengen: [13, 14, 15]
mit Untergrenze Aufbau Faelle mit Fehler: 0 geaenderte Laengen: [13, 14, 15]
mit Untergrenze Erfahren Faelle mit Fehler: 0 geaenderte Laengen: []
Aufbau 3,3 %: [(11, 2), (12, 2), (13, 2), (14, 2), (15, 2), (16, 2)]
```

## Stand

Kein Git-Repository, deshalb SHA-256 nach `build`:

- `1e2438495f41a6eb583d650a3bd2178d0e0481f65a6dcf6d0f67692f35971527` planning-rules.md
- `18c7c0ba74ec9dd9ea6b2ac67c3e73ca3fd11f7b028d9c24c6c7168c3503cf9e` phase-2-3-rules.md
- `1bee25c6ca627bbc42dd76447d75f7775ba33f227773612c2c8c2c3a35d75646` model-parameters.md

## Nachtrag: Energiereserve (DEC-0060)

Nur Zuordnung zur Phase und Hinweise, keine Werte geändert. SHA-256 danach:

- `812d9049bb87368ee9ad3ff2d03165fe1010a2c5f67fdb5d736d007534641b5b` planning-rules.md
- `3041f28694b4f9ad136d9dfa759de719213439c784d2c3691fb06278f1345b60` phase-2-3-rules.md
