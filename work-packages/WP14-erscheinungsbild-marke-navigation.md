# WP14 – Erscheinungsbild, Marke und Navigation (`app/lib/ui`, `app/lib/app.dart`, `app/lib/features/home`, `setup`, `pubspec.yaml`, `app/assets/fonts`, Android-Ressourcen, Manifest, Paket-ID)

**Zuordnung:** M1, nachgereicht am 2026-11-08 (OQ-0075). Grundlage für WP13, WP15 und WP16.

Bezug: FR-0205, FR-0206, FR-0207, FR-0208, FR-0209, FR-0001, FR-0034, NFR-0006, CON-0009; OQ-0075, DEC-0070; K33. Vorlagen: `design/README.md`, `design/screens/Splash.dc.html`, `Main.dc.html`, `branding/README.md`, `branding/android/res/`.

## Inhalt
1. **Theme und Bausteine (Teil A):**
   - Farben als Tokens an einer Stelle (`app/lib/ui/`), hell nach Design, dunkel abgeleitet aus den Markenfarben (FR-0205). Schriftstile für Sora und Manrope.
   - Sora und Manrope als TTF in `app/assets/fonts/`, eingebunden über `pubspec.yaml`, OFL-Lizenztext über `LicenseRegistry`. Kein `google_fonts`, kein Laden zur Laufzeit.
   - Bausteine, die die Screens wiederholt nutzen: Karte (hell und dunkel), Haupt- und Nebenknopf, Umschalter, Chip, Wertkachel (Zahl, Einheit, Beschriftung), Kennzeichnung „geschätzt“ mit Glutpunkt, Zonenbalken, Abschnittsüberschrift.
   - Test der Kontrastpaare beider Modi (mindestens 4,5 : 1 für Text).
2. **Name, Paket-ID und Systemsymbole (Teil B):**
   - App-Titel „ramuri“ in `app_de.arb`/`app_en.arb` und im Manifest (`android:label` über Ressource, nicht fest verdrahtet).
   - Paket-ID `io.github.brokoskokoli.ramuri`: `applicationId`, `namespace`, Kotlin-Paket (main und test), Kanalnamen auf beiden Seiten, Verweise in Gate und Tests. Der Dart-Paketname `running_app` bleibt.
   - Launcher als Adaptive Icon mit monochromer Ebene aus `branding/android/res/`; Benachrichtigung der Aufzeichnung mit `ic_stat_ramuri` statt `R.mipmap.ic_launcher` (`RecordingService.kt`).
   - System-Splash: Logo auf Nacht, für API 31+ über die Splash-Screen-API, darunter über `launch_background.xml`.
3. **Navigation, Heute, Willkommen (Teil C):**
   - Untere Navigation mit Heute, Verlauf, Fortschritt (FR-0208). Verlauf und Fortschritt zeigen bis WP15/WP16 die bestehenden Seiten im neuen Theme.
   - „Heute“ nach `Main.dc.html` in der Phase-1-Fassung (FR-0209): Frei laufen, Woche Mo–So mit Laufhaken und km-Summe, letzter Lauf mit Sprung ins Detail, Profil-Symbol.
   - Profil-Symbol führt zu einer Übersicht mit Profil, Einstellungen, Sensoren, Zonen, Berechtigungen und Daten (alle bisherigen Einträge von `home_screen.dart`).
   - Willkommensbildschirm nach `Splash.dc.html` nur vor der ersten Einrichtung (FR-0207), Text nach der Festlegung dort.
4. **Seiten ohne Screen (Teil D):** Einrichtung, Profil, Einstellungen, Sensoren, Zonen, Berechtigungen, Daten/Archiv/Import, Speicher-Gate, Wiederaufnahme-Dialog und Erklärungen nutzen Theme und Bausteine. Kein neuer Inhalt.

## Umsetzung
- Erst Teil A, dann B, C, D, je ein Coder-Auftrag ohne Übergabe. Teil B in einem Commit, damit Paket-ID, Kanäle und Tests zusammenpassen.
- Neue Texte auf Deutsch und Englisch, Präfix `ui`/`home`/`welcome` in den arb-Dateien.
- Maße und Farben aus den Design-Dateien ablesen (Inline-Styles). Die Screens lassen sich ohne Canvas-Laufzeit im Browser öffnen; dabei die Schriften lokal einbinden, nicht von Google laden.
- Keine Gesundheitsdaten in Golden-Tests; Beispielwerte erfunden wie im Design.
- **Nicht dazu:** Lauf vorbereiten, Lauf, Zusammenfassung, Verlauf, Detail (WP16), Fortschritt (WP15), Karte (WP13), Inhalte aus Phase 2/3.
- **Parallel:** läuft allein (ändert Manifest, `pubspec.yaml`, Kotlin-Paket und `app.dart`). WP13, WP15 und WP16 bauen auf dem Theme auf.

## Abnahmekriterien
- [ ] FR-0205: Theme hell und dunkel an einer Stelle; Kontrasttest grün; keine Farbwerte außerhalb des Themes (Suche nach `Color(0x` und `Colors.` außerhalb `app/lib/ui/` leer oder begründet).
- [ ] Schriften gebündelt, Lizenz in den Lizenzangaben sichtbar; die Release-APK enthält die TTF-Dateien und kein `google_fonts`.
- [ ] FR-0206: Launcher, Titel, Benachrichtigung zeigen ramuri; `aapt dump badging` der Release-APK zeigt `package: name='io.github.brokoskokoli.ramuri'`; Themed Icon auf API 33+ einfarbig.
- [ ] Aufzeichnung, Wiederanlauf, Export und Archiv funktionieren nach dem Wechsel der Paket-ID (Kotlin-Tests und App-Tests grün, Kanäle auf beiden Seiten gleich).
- [ ] FR-0207: Willkommen erscheint nur vor der ersten Einrichtung; nicht nach Reimport, nicht beim zweiten Start (Widget-Test).
- [ ] FR-0208, FR-0209: drei Bereiche, Zurück-Verhalten nach FR-0208; jede bisherige Seite erreichbar; Wochensumme gleich der Wochenstatistik (Test).
- [ ] E2E (separater Agent), API 31 und 36, hell und dunkel: Bildschirmfotos von Willkommen, Heute und der Übersicht neben den Design-Screens, Abweichungen benannt; Launcher-Icon und Benachrichtigung im Foto.
- [ ] Release-APK ohne `INTERNET` (bis WP13), ohne Hintergrundstandort und Boot-Start, ohne Test-Sensor. Gate grün.

## Ungeprüft
Darstellung auf sehr kleinen und sehr großen Displays außerhalb der Emulatoren, Themed Icons bei Herstelleroberflächen.
