# WP19 – Belastungsverlauf und Belastungsprofil (`core`, `app/lib/features/statistics`, `settings`)

**Zuordnung:** M2, Welle 2, nach WP18. Parallel zu WP21.

Bezug: FR-0097 bis FR-0104, FR-0197; PAR-072 bis PAR-076, PAR-086 bis PAR-090; OQ-0002, OQ-0028, OQ-0043, OQ-0045, OQ-0053. Vorlage: `design/screens/Fortschritt.dc.html`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **ATL, CTL, TSB (Teil A, FR-0097 bis FR-0101):** Reine Berechnung in `core` auf einer Skala, mit den Sperr- und Anlaufregeln aus PAR-073. Benennung nach FR-0100.
2. **Lücken (Teil B, FR-0102 bis FR-0104):** Unvollständige Daten, nicht aufgezeichnete Tage und fehlender Datenbestand gelten nicht stillschweigend als trainingsfrei oder als niedrige Fitness. Dazu die Zusage „alles erfasst“ und die Bestätigung einer Pause, soweit dieses Paket sie braucht.
3. **Anzeige (Teil C):** Verlauf auf der Seite Fortschritt im Stil des Designs, mit Grundlage und Datenstand. Keine Risikoaussage aus TSB (OQ-0028).
4. **Belastungsprofil (Teil D, FR-0197):** Edwards und Banister; ohne Ruhepuls oder Koeffizienten nur Edwards. Beim Wechsel Neuberechnung alter Läufe nach Bestätigung über den Mechanismus aus WP09.
5. **Aus WP18 (Teil B):** Der Reimport nimmt nachgetragene Trainings mit Datum in der Zukunft an, die Eingabe nicht. Der Reimport weist sie wie die Eingabe ab, bevor sie in die Belastung eingehen (Test). Python-Testvektor für Archivformat 2 nachziehen.

## Umsetzung
- Teile je ein Coder-Auftrag. Mutationsbelege für die Glättung, die Anlaufsperre, das Einbeziehen nachgetragener Trainings und die Auswahlregel des Profils.
- Laufzeit mit mehreren Jahren Daten auf der VM messen.
- **Parallel:** WP21 liest den Belastungsstand erst mit WP23; bis dahin keine gemeinsame Schnittstelle nötig.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0097 bis FR-0104 und FR-0197.
- [ ] Wechsel des Profils hält ATL und CTL auf einer Skala (Test), das verwendete Profil ist sichtbar.
- [ ] E2E auf API 36 und 31, hell und dunkel, mit Bildschirmfotos. Gate grün.
