# ADR-0006 — Anbindung von Bluetooth-Sensoren

- **Status:** Accepted (Maintainer, 2026-11-04)
- **Datum:** 2026-11-04
- **Quellen:** SRC-003 (OQ-0018, OQ-0037)
- **Betroffene Anforderungen:** FR-0007, FR-0008, FR-0011, FR-0012, FR-0013, FR-0014, FR-0015, FR-0016, FR-0017, FR-0018, FR-0019, FR-0020, FR-0036, ACC-02, ACC-03, CON-0003, OQ-0018

## Kontext
Phase 1 verlangt kompatible Bluetooth-Pulssensoren ohne herstellerspezifische Einrichtung (FR-0007, FR-0008, CON-0003). Das bevorzugte Gerät hat Vorrang, gewechselt wird manuell oder nach einem Abbruch, mit Herkunft je Zeitabschnitt (OQ-0018), ohne automatischen Rückwechsel im Lauf (OQ-0037). Die Projektlizenz ist GPL-3.0.

## Entscheidung
**1. Standardprofil:** Bluetooth LE mit Heart Rate Service `0x180D`, Benachrichtigung auf Heart Rate Measurement `0x2A37`, optional Battery Service `0x180F` mit Battery Level `0x2A19` für FR-0016 [1][2]. Die Suche filtert auf `0x180D` (FR-0008, FR-0011). RR-Intervalle bleiben ungenutzt (FR-0021 ist Phase 4).

**2. Plugin:** `universal_ble` 3.2.0 (BSD-3-Clause, Stand 2026-10-30, Navideck) hinter dem Port aus ADR-0002 [3][4]. Keine zusätzliche native Laufzeitabhängigkeit, dokumentiert Benachrichtigungen, `autoConnect` und den Betrieb ohne Activity bei vorab erteilten Rechten.

**3. Berechtigungen:** `BLUETOOTH_SCAN` mit `neverForLocation` und `BLUETOOTH_CONNECT`, abgefragt erst, wenn der Nutzer einen Sensor einrichtet. Läufe ohne Sensor kommen ohne sie aus (FR-0035). Mit minSdk 31 entfallen die alten Rechte [5]; die Einträge des Plugins mit `maxSdkVersion` 30 sind wirkungslos.

**4. Verbindung im Lauf:** Der Dienst aus ADR-0005 hält den Prozess und damit die Verbindung; eine Verbindung endet mit dem Prozess [6]. Empfohlen werden `autoConnect: true` und `closeGattOnDetach: true`, damit der Sensor nach dem Beenden frei wird [3]. Bis ein anderes Gerät aktiv wird, verbindet die App das bisherige neu.

**5. Fachlogik in `core`:** Vorrang, Wechsel, Rückfall und Herkunft sind reines Dart mit Fake-Sensor, unabhängig vom Plugin. Es speist immer nur eine Quelle die Messreihe, jeder Wert trägt sein Quellgerät (FR-0019, FR-0020). Zeit ohne Werte bleibt „nicht verfügbar“ (FR-0056).

## Erwogene Alternativen
- **`flutter_blue_plus` 2.3.14:** Seit 2.0.0 eigene „FlutterBluePlus License“ 1.6 statt BSD. Kommerzielle Nutzung, auch durch Einzelpersonen, kostet Gebühren, die Lizenz verbietet Neulizenzierung und erlaubt eine Lizenzmeldung beim Build [7]. Das sind nach meiner Einschätzung, ohne Rechtsprüfung, weitere Einschränkungen im Sinne von GPL-3.0 Abschnitt 10; damit nicht kompatibel. Stehenbleiben bei 1.36.8 (letzte Version davor) hieße, ein Bluetooth-Plugin ohne Pflege zu nutzen.
- **`flutter_reactive_ble` 5.6.0 (BSD-3-Clause, Signify, Stand 2026-09-23):** Lizenz passt, seriöser Träger, aber 140 offene Issues und 26 offene PRs [8], und es zieht RxAndroidBle und Protobuf nach. **Erster Rückfallweg** hinter demselben Port.
- **`bluetooth_low_energy` 6.2.1 (MIT):** Letzte stabile Version vom 2026-01-17.
- **Eigener GATT-Code in Kotlin:** Volle Kontrolle, aber Fehlerquelle und Pflege; nur als letzter Ausweg.
- **Companion Device Manager:** Laut Android eingeschränkte Filter und keine zufälligen MAC-Adressen [6], und der Dienst wird für GPS ohnehin gebraucht.

## Konsequenzen
- CON-0003 gilt für das Standardprofil. Geräte ohne `0x180D` bleiben außen vor; FR-0009 und FR-0010 sind Phase 4.
- `universal_ble` hat einen kleinen Anbieter und baut mit `compileSdkVersion 34`; der Bau mit Target 36 ist noch unbelegt (R005). Der Port begrenzt die Kosten eines Wechsels.
- Nutzt ein Sensor wechselnde Adressen (bei Pulssensoren unbelegt), veraltet die Kennung des bekannten Geräts (FR-0013); dann hilft eine neue Suche.

## Im Emulator nicht belegbar
ACC-02 mit echtem Pulsgurt, Funkabbrüche, Eigenheiten der Bluetooth-Chips einzelner Hersteller, Uhren im Broadcast-Modus und die Kategorien aus FR-0007. ACC-02 bleibt in `work-packages/STATUS.md` offen.

## Vorschlag Research R006: Virtueller Pulssensor im Emulator
Das Emulator-Bluetooth Netsim lässt sich von Bumble (Apache-2.0) ansprechen, das GATT-Server als virtuelle Geräte betreiben kann [9]. **Frage:** Reicht das für einen reproduzierbaren Test mit Heart Rate Service? **Prüfen:** Suche, Verbindung, Benachrichtigungen, Batterie, Abbruch und Neuverbinden mit `universal_ble` unter dem Dienst aus ADR-0005, bei gesperrtem Bildschirm. **Ergebnis:** Testaufbau für ACC-03 und die Wechselregeln oder die Aussage, dass nur Fakes tragen. Ob das Vorhaben so funktioniert, ist unbelegt.

## Belege (Abruf 2026-11-04)
[1] https://www.bluetooth.com/specifications/specs/heart-rate-service-1-0/ ·
[2] https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/uuids/ ·
[3] https://pub.dev/packages/universal_ble ·
[4] https://github.com/Navideck/universal_ble/blob/main/LICENSE ·
[5] https://developer.android.com/develop/connectivity/bluetooth/bt-permissions ·
[6] https://developer.android.com/develop/connectivity/bluetooth/ble/background ·
[7] https://pub.dev/packages/flutter_blue_plus/license, Changelog: https://pub.dev/packages/flutter_blue_plus/changelog ·
[8] https://github.com/PhilipsHue/flutter_reactive_ble ·
[9] https://google.github.io/bumble/platforms/android.html
