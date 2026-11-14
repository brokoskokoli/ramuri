# Sammlung: morgenmessungen-maintainer

- **Was:** Exporte „Messpaare“ der App ramuri (Entwicklermodus): Morgenmessungen des Maintainers mit der Handykamera, dazu die gleichzeitig vom Brustgurt (Polar H9) gespeicherten RR-Werte. Erstellt vom Maintainer ab 2026-11-14 auf seinem eigenen Telefon, abgelegt vom Orchestrator.
- **Format:** CSV nach `docs/contracts/morning-pairs-csv.md` (Formatversion siehe Spalte `format_version`), Dateiname `running-morgenpaare-<JJJJMMTT>.csv` wie vom Export erzeugt. Ab WP37 ggf. zusätzlich das Kamera-Rohsignal (K70).
- **Inhalt:** je Messung Metadaten (Zeit, Haltung, Stufe, Gerätemodell ohne Seriennummer), Kamera-Ruhepuls/RMSSD/Zeitrauschen, alle Kamera-Schlagabstände (ungültige leer), rohe Gurt-RR in 1/1024 s.
- **Privat:** ja – Gesundheitsdaten des Maintainers (SEC-0001 bis SEC-0010).
- **Erlaubte Nutzung (Maintainer 2026-11-14):** nur lokal für Research-Analysen (zuerst R010); nie in Git, nie in Logs; in `RESULTS.md` nur Dateinamen und Kennzahlen (z. B. Abweichung Kamera gegen Gurt), keine Rohwerte oder Zeitreihen; nicht auf fremde Server.
- **Genutzt von:** R010.
