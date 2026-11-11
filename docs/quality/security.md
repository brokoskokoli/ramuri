# Sicherheit und Datenschutz

**Status:** Draft. Maßgeblich für alle Datenschutzregeln; andere Dokumente verweisen hierher.

Herzfrequenz-, Schlaf- und Trainingsinformationen sind sensible persönliche Daten (SRC-001 §21, Z. 1235).

## Sicherheitsinvarianten

### SEC-0001 — Gesundheitsdaten nur mit ausdrücklicher Zustimmung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1235–1237
- **Verwandt:** FR-0022, OQ-0017, OQ-0025, OQ-0048

Gesundheitsdaten werden nur mit ausdrücklicher Zustimmung verwendet.

**Akzeptanzkriterien:**
- [ ] Ohne Zustimmung werden Gesundheitsdaten weder gelesen noch für Berechnungen verwendet.
- [ ] Plattform-Import und Strava brauchen je eine Einwilligung; ein selbst gestarteter Lauf mit gekoppeltem Sensor braucht keine weitere (OQ-0025).

### SEC-0002 — Datenquellen getrennt freigeben
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1238
- **Verwandt:** OQ-0017

Der Nutzer kann einzelne Datenquellen getrennt freigeben.

**Akzeptanzkriterien:**
- [ ] Die Freigabe einer Quelle gibt keine andere Quelle frei.

### SEC-0003 — Externe Synchronisierung ist optional
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1239
- **Verwandt:** CON-0010, FR-0187, OQ-0017

Externe Synchronisierung ist optional.

**Akzeptanzkriterien:**
- [ ] Alle Funktionen außer der Synchronisierung selbst bleiben ohne externe Synchronisierung nutzbar.

### SEC-0004 — Export und Löschung der eigenen Daten
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1240; §25 Nr. 15, Z. 1410
- **Verwandt:** FR-0192, ACC-15, OQ-0017, OQ-0025

Export und Löschung der eigenen Daten sind möglich.

**Akzeptanzkriterien:**
- [ ] Gelöschte Daten sind aus dem Speicher der App entfernt und nicht nur ausgeblendet (ACC-15).
- [ ] Löschen geht je Lauf oder komplett (OQ-0025).
- [ ] Daten bei Strava bleiben dort, und die App weist beim Löschen darauf hin (OQ-0025).

### SEC-0005 — Datenherkunft erkennbar
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1241
- **Verwandt:** FR-0020, FR-0053, OQ-0017

Es muss erkennbar sein, welche Daten aus welchen Quellen stammen.

**Akzeptanzkriterien:**
- [ ] Zu jedem angezeigten importierten oder gemessenen Datensatz ist die Quelle abrufbar.

### SEC-0006 — Berechnungen ohne zwingende externe Übertragung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1242
- **Verwandt:** CON-0008, OQ-0017, OQ-0023

Fitnessberechnungen sollen ohne zwingende externe Datenübertragung möglich sein.

**Akzeptanzkriterien:**
- [ ] Ohne Netzwerkverbindung lassen sich Fitnesswerte aus vorhandenen Daten berechnen.

### SEC-0007 — Berechtigungen widerrufen
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1243
- **Verwandt:** FR-0191, OQ-0017, OQ-0025

Der Nutzer kann Berechtigungen widerrufen.

**Akzeptanzkriterien:**
- [ ] Nach dem Widerruf werden über diese Berechtigung keine neuen Daten mehr gelesen oder gesendet.
- [ ] Beim Widerruf fragt die App, ob importierte Daten gelöscht werden (OQ-0025).

### SEC-0008 — Keine Übertragung an Dritte ohne Einwilligung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1244
- **Verwandt:** FR-0185, FR-0186, FR-0187, FR-0204, OQ-0017, OQ-0025, OQ-0074, ADR-0009

Externe Daten dürfen nicht ohne Einwilligung an Dritte übertragen werden.

**Akzeptanzkriterien:**
- [ ] Ein Netzwerkmitschnitt ohne erteilte Einwilligung zeigt keine Übertragung solcher Daten an Dritte.

### SEC-0009 — Verschlüsselte Speicherung
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-001 §21, Z. 1235; SRC-003 (OQ-0024, OQ-0062)
- **Verwandt:** FR-0185, FR-0174, OQ-0024, OQ-0062, OQ-0072, ADR-0005

Datenbank und Zugangsdaten werden auf dem Gerät verschlüsselt gespeichert. Lässt sich die Datenbank nicht mehr öffnen, erklärt die App das Problem und bietet einen Neubeginn mit leerer Datenbank und den Reimport aus dem Archiv an; die alte Datei wird erst nach ausdrücklicher Bestätigung gelöscht.

**Ausnahme (Entscheidung des Maintainers 2026-11-11, K53):** Für die Erinnerungen (FR-0174) liegen außerhalb der Datenbank unverschlüsselt in den App-eigenen SharedPreferences nur: je geplanter Einheit Zeitpunkt und Art, höchstens 60 Tage voraus, und die Benachrichtigungstexte je Art. Sonst keine Plan- oder Gesundheitsdaten. Grund: Der Boot-Empfänger hat keinen Datenbankschlüssel. Einzelheiten im Nachtrag zu ADR-0005. Die Datenbank selbst bleibt ohne Ausnahme verschlüsselt.

**Akzeptanzkriterien:**
- [ ] Die Datenbankdatei ist ohne Schlüssel nicht lesbar.
- [ ] Ohne gültigen Schlüssel bleibt die alte Datei erhalten, bis der Nutzer das Löschen bestätigt.
- [ ] Zugangsdaten externer Dienste liegen nicht im Klartext vor.

### SEC-0010 — System-Backups immer aus
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (OQ-0024)
- **Verwandt:** SEC-0008, FR-0192, OQ-0024, OQ-0056

System-Backups der App-Daten sind immer aus, es gibt keinen Schalter (OQ-0056). Gesichert wird über den verschlüsselten Gesamtexport.

**Akzeptanzkriterien:**
- [ ] Ein System-Backup enthält keine App-Daten.

### SEC-0011 — Verschlüsseltes Archiv
- **Status:** Approved | **Phase:** 1
- **Quelle:** SRC-003 (OQ-0050)
- **Verwandt:** SEC-0009, FR-0192, FR-0198, OQ-0050

Der Gesamtexport ist immer mit einem Passwort des Nutzers verschlüsselt und enthält keine Zugangsdaten und Einwilligungen.

**Akzeptanzkriterien:**
- [ ] Ohne Passwort ist das Archiv nicht lesbar.
- [ ] Die App weist darauf hin, dass ein vergessenes Passwort das Archiv unbrauchbar macht.

## In der Quelle nicht geregelt

Die Quelle macht zu diesem Punkt keine Aussage. Er ist deshalb keine Anforderung, sondern eine offene Frage:

| Thema | Offene Frage |
|---|---|
| Rechtliche Prüfung (Datenschutz, Medizinprodukt, Patent, NHS-Abfolge): noch nicht erfolgt | OQ-0048 |

## Vorschläge

Nicht bindend, keine Anforderungen.

- Ein Bedrohungsmodell erstellen, bevor Strava-Anbindung und Speicherung umgesetzt werden.
- Eine zusätzliche App-Sperre prüfen; sie ist weder verlangt noch entschieden.
- Die Einordnung als Gesundheitsdaten nach DSGVO rechtlich prüfen lassen.
