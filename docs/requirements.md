# Anforderungsregister

Durchsuchbare Übersicht. Maßgeblich ist immer die verlinkte Detailstelle. Die Tabelle wird mit `python3 docs/migration/tools/spec_tool.py build` erzeugt und nicht von Hand bearbeitet.

**Status:** `Draft` = übernommen, noch nicht freigegeben. `Blocked` = von einem Widerspruch oder einer unentschiedenen Modellfrage betroffen. `Approved` vergibt nur der Maintainer. Freigegeben sind alle Anforderungen der Phasen 1 bis 3 (2026-11-03 und 2026-11-04). Phase 4 und die zurückgestellten Strava-Punkte bleiben `Draft`.

**Phase:** Die Phasen sind verbindlich (OQ-0017). Belegt durch SRC-001 §24 oder eine Entscheidung des Maintainers. `1*` = dort nicht genannt, aber Voraussetzung für Phase 1. `4 (möglich)` = dort nur als mögliche Zusatzfunktion genannt. `Zurückgestellt` = derzeit keiner Phase zugeordnet (OQ-0049). Abweichende Zuordnungen hat der Maintainer entschieden (OQ-0041). Eine Priorität wird nicht geführt, weil die Quelle keine nennt. Der Implementierungsstatus wird hier nicht geführt.

<!-- BEGIN REGISTER -->
| ID | Titel | Kategorie | Status | Phase | Detail | Verwandt |
|---|---|---|---|---|---|---|
| FR-0001 | Profil beim ersten Start einrichten | functional | Approved | 1 | [profile](specs/profile.md#fr-0001--profil-beim-ersten-start-einrichten) | FR-0002, OQ-0010 |
| FR-0002 | Profildatenfelder | functional | Approved | 1 | [profile](specs/profile.md#fr-0002--profildatenfelder) | FR-0001, OQ-0010, OQ-0013, OQ-0038, OQ-0065 |
| FR-0003 | Gemessene maximale Herzfrequenz hat Vorrang | functional | Approved | 1 | [profile](specs/profile.md#fr-0003--gemessene-maximale-herzfrequenz-hat-vorrang) | FR-0004 |
| FR-0004 | Altersbasierte Näherung der maximalen Herzfrequenz | functional | Approved | 1 | [profile](specs/profile.md#fr-0004--altersbasierte-näherung-der-maximalen-herzfrequenz) | FR-0003, FR-0005, OQ-0012 |
| FR-0005 | Hinweis auf Streuung und Korrektur der Näherung | functional | Approved | 1 | [profile](specs/profile.md#fr-0005--hinweis-auf-streuung-und-korrektur-der-näherung) | FR-0004 |
| FR-0006 | Neuberechnung nach Änderung der Basiswerte | functional | Approved | 1 | [profile](specs/profile.md#fr-0006--neuberechnung-nach-änderung-der-basiswerte) | FR-0058, OQ-0031 |
| FR-0007 | Unterstützte Gerätekategorien | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0007--unterstützte-gerätekategorien) | CON-0003, OQ-0009, ACC-02 |
| FR-0008 | Automatische Erkennung standardisierter Geräte | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0008--automatische-erkennung-standardisierter-geräte) | FR-0011 |
| FR-0009 | Ergänzende Uhrenanwendung | functional | Draft | 4 (möglich) | [sensors](specs/sensors.md#fr-0009--ergänzende-uhrenanwendung) | OQ-0009, OQ-0017 |
| FR-0010 | Herstellerspezifische Anbindungen sind optional | functional | Draft | 4 (möglich) | [sensors](specs/sensors.md#fr-0010--herstellerspezifische-anbindungen-sind-optional) | CON-0003, OQ-0009, OQ-0017 |
| FR-0011 | Geräte suchen | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0011--geräte-suchen) | FR-0008 |
| FR-0012 | Gerät verbinden und trennen | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0012--gerät-verbinden-und-trennen) | ACC-02 |
| FR-0013 | Mehrere bekannte Geräte speichern | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0013--mehrere-bekannte-geräte-speichern) | — |
| FR-0014 | Bevorzugtes Gerät festlegen | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0014--bevorzugtes-gerät-festlegen) | FR-0019 |
| FR-0015 | Aktuelle Herzfrequenz anzeigen | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0015--aktuelle-herzfrequenz-anzeigen) | — |
| FR-0016 | Batteriestand anzeigen, sofern bereitgestellt | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0016--batteriestand-anzeigen-sofern-bereitgestellt) | — |
| FR-0017 | Verbindungsabbrüche erkennen | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0017--verbindungsabbrüche-erkennen) | FR-0036, FR-0056, ACC-03 |
| FR-0018 | Datenquelle während des Trainings wechseln | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0018--datenquelle-während-des-trainings-wechseln) | FR-0019, FR-0020, OQ-0018, OQ-0064 |
| FR-0019 | Eindeutige Priorisierung ohne Vermischung | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0019--eindeutige-priorisierung-ohne-vermischung) | FR-0014, OQ-0018 |
| FR-0020 | Herkunft der Messwerte dokumentieren | functional | Approved | 1 | [sensors](specs/sensors.md#fr-0020--herkunft-der-messwerte-dokumentieren) | SEC-0005 |
| FR-0021 | Erweiterte Sensordaten aufzeichnen | functional | Draft | 4 | [sensors](specs/sensors.md#fr-0021--erweiterte-sensordaten-aufzeichnen) | OQ-0013 |
| FR-0022 | Import nur mit Zustimmung | functional | Approved | 3 | [health-import](specs/health-import.md#fr-0022--import-nur-mit-zustimmung) | SEC-0001, SEC-0002, OQ-0033 |
| FR-0023 | Importierbare Datenarten | functional | Approved | 3 | [health-import](specs/health-import.md#fr-0023--importierbare-datenarten) | OQ-0033 |
| FR-0024 | Fremde VO2max-Werte nicht ungeprüft zusammenführen | functional | Approved | 3 | [health-import](specs/health-import.md#fr-0024--fremde-vo2max-werte-nicht-ungeprüft-zusammenführen) | FR-0081, OQ-0033 |
| FR-0025 | Freie oder geplante Einheit starten | functional | Approved | 1 (frei), 2 (aus Plan) | [run-recording](specs/run-recording.md#fr-0025--freie-oder-geplante-einheit-starten) | — |
| FR-0026 | Pflichtanzeigen während des Trainings | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0026--pflichtanzeigen-während-des-trainings) | FR-0051, FR-0056, OQ-0012 |
| FR-0027 | Optionale Anzeigen während des Trainings | functional | Approved | 1 (Rundenzeiten, Höhenmeter, Schrittfrequenz), 2 (Soll-/Ist-Vergleich, Belastungsbereich) | [run-recording](specs/run-recording.md#fr-0027--optionale-anzeigen-während-des-trainings) | OQ-0041 |
| FR-0028 | Training starten, pausieren, fortsetzen, beenden | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0028--training-starten-pausieren-fortsetzen-beenden) | FR-0052 |
| FR-0029 | Automatisches Pausieren | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0029--automatisches-pausieren) | OQ-0037, OQ-0065, OQ-0068 |
| FR-0030 | Manuelle Rundenmarkierung | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0030--manuelle-rundenmarkierung) | — |
| FR-0031 | Akustische Trainingshinweise | functional | Approved | 2 | [run-recording](specs/run-recording.md#fr-0031--akustische-trainingshinweise) | OQ-0044 |
| FR-0032 | Warnung bei Überschreitung des Herzfrequenzbereichs | functional | Approved | 2 | [run-recording](specs/run-recording.md#fr-0032--warnung-bei-überschreitung-des-herzfrequenzbereichs) | — |
| FR-0033 | Hinweise zum nächsten Trainingsintervall | functional | Approved | 2 | [run-recording](specs/run-recording.md#fr-0033--hinweise-zum-nächsten-trainingsintervall) | — |
| FR-0034 | Aufzeichnung bei ausgeschaltetem Bildschirm | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0034--aufzeichnung-bei-ausgeschaltetem-bildschirm) | OQ-0021 |
| FR-0035 | Aufzeichnung ohne Pulssensor | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0035--aufzeichnung-ohne-pulssensor) | CON-0004, ACC-01, OQ-0021 |
| FR-0036 | Verbindungsabbruch verliert den übrigen Lauf nicht | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0036--verbindungsabbruch-verliert-den-übrigen-lauf-nicht) | FR-0017, ACC-03 |
| FR-0037 | Zusammenfassung nach dem Lauf | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0037--zusammenfassung-nach-dem-lauf) | FR-0052, FR-0092, OQ-0037, OQ-0065 |
| FR-0038 | Subjektive Angaben erfassen | functional | Approved | 2 | [run-recording](specs/run-recording.md#fr-0038--subjektive-angaben-erfassen) | FR-0095, OQ-0059 |
| FR-0039 | Subjektive Angaben in der Planung berücksichtigen | functional | Approved | 2 | [run-recording](specs/run-recording.md#fr-0039--subjektive-angaben-in-der-planung-berücksichtigen) | FR-0148, FR-0157 |
| FR-0040 | Trainingshistorie | functional | Approved | 1 | [history-statistics](specs/history-statistics.md#fr-0040--trainingshistorie) | ACC-04 |
| FR-0041 | Detailansicht eines Laufs | functional | Approved | 1 | [history-statistics](specs/history-statistics.md#fr-0041--detailansicht-eines-laufs) | — |
| FR-0042 | Pace und Herzfrequenz zeitlich vergleichen | functional | Approved | 1 | [history-statistics](specs/history-statistics.md#fr-0042--pace-und-herzfrequenz-zeitlich-vergleichen) | — |
| FR-0043 | Statistische Kennzahlen | functional | Approved | 1 (je Kennzahl abhängig von der liefernden Funktion) | [history-statistics](specs/history-statistics.md#fr-0043--statistische-kennzahlen) | FR-0055, OQ-0039, OQ-0065 |
| FR-0044 | Auswertungszeiträume | functional | Approved | 1 | [history-statistics](specs/history-statistics.md#fr-0044--auswertungszeiträume) | — |
| FR-0045 | Keine Fitnessberechnung auf ungefilterten Daten | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0045--keine-fitnessberechnung-auf-ungefilterten-daten) | — |
| FR-0046 | Synchronisation über Zeitstempel | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0046--synchronisation-über-zeitstempel) | — |
| FR-0047 | Zu berücksichtigende Datenprobleme | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0047--zu-berücksichtigende-datenprobleme) | OQ-0019 |
| FR-0048 | Qualitätsbewertung je Abschnitt | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0048--qualitätsbewertung-je-abschnitt) | OQ-0019 |
| FR-0049 | Strecke aus plausiblen Positionsdistanzen | functional | Approved | 1 | [data-quality](specs/data-quality.md#fr-0049--strecke-aus-plausiblen-positionsdistanzen) | — |
| FR-0050 | Geschwindigkeit und Pace | functional | Approved | 1 | [data-quality](specs/data-quality.md#fr-0050--geschwindigkeit-und-pace) | OQ-0037 |
| FR-0051 | Geglättete Tempoanzeige | functional | Approved | 1 | [data-quality](specs/data-quality.md#fr-0051--geglättete-tempoanzeige) | OQ-0019 |
| FR-0052 | Bewegungszeit und Gesamtzeit getrennt | functional | Approved | 1 | [data-quality](specs/data-quality.md#fr-0052--bewegungszeit-und-gesamtzeit-getrennt) | OQ-0068, OQ-0069 |
| FR-0053 | Metadaten jedes fortgeschrittenen Fitnesswerts | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0053--metadaten-jedes-fortgeschrittenen-fitnesswerts) | CON-0005, CON-0009, NFR-0001, OQ-0019, OQ-0040, OQ-0059 |
| FR-0054 | Qualitätsstufen sind keine Genauigkeitsangaben | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0054--qualitätsstufen-sind-keine-genauigkeitsangaben) | NFR-0003 |
| FR-0055 | Funktionen je Datenverfügbarkeitsstufe | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0055--funktionen-je-datenverfügbarkeitsstufe) | CON-0004, CON-0007, OQ-0012, OQ-0034 |
| FR-0056 | Fehlender Sensorwert ist keine Nullmessung | functional | Approved | 1 | [data-quality](specs/data-quality.md#fr-0056--fehlender-sensorwert-ist-keine-nullmessung) | — |
| FR-0057 | Vier Zustände eines Messwerts | functional | Approved | 1 | [data-quality](specs/data-quality.md#fr-0057--vier-zustände-eines-messwerts) | CON-0009 |
| FR-0058 | Ursprüngliche und neu berechnete Werte unterscheiden | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0058--ursprüngliche-und-neu-berechnete-werte-unterscheiden) | FR-0006, NFR-0001, OQ-0031 |
| FR-0059 | Nachvollziehbarkeit eines geschätzten Werts | functional | Approved | 1* | [data-quality](specs/data-quality.md#fr-0059--nachvollziehbarkeit-eines-geschätzten-werts) | CON-0005, FR-0181, ACC-06 |
| FR-0060 | Herzfrequenzreserve und relative Auslastung | functional | Approved | 1 | [heart-rate-zones](specs/heart-rate-zones.md#fr-0060--herzfrequenzreserve-und-relative-auslastung) | OQ-0012, OQ-0019, OQ-0059 |
| FR-0061 | Fünf konfigurierbare Zonen | functional | Approved | 1 | [heart-rate-zones](specs/heart-rate-zones.md#fr-0061--fünf-konfigurierbare-zonen) | — |
| FR-0062 | Vorläufiges Zonenmodell auf Basis der Herzfrequenzreserve | functional | Approved | 1 | [heart-rate-zones](specs/heart-rate-zones.md#fr-0062--vorläufiges-zonenmodell-auf-basis-der-herzfrequenzreserve) | OQ-0003, OQ-0014 |
| FR-0063 | Bereiche unter Zone 1 separat ausweisen | functional | Approved | 1 | [heart-rate-zones](specs/heart-rate-zones.md#fr-0063--bereiche-unter-zone-1-separat-ausweisen) | — |
| FR-0064 | Zonen als Näherung kennzeichnen | functional | Approved | 1 | [heart-rate-zones](specs/heart-rate-zones.md#fr-0064--zonen-als-näherung-kennzeichnen) | CON-0009 |
| FR-0065 | Zonen aus Tests oder gemessenen Schwellen | functional | Draft | 4 (möglich) | [heart-rate-zones](specs/heart-rate-zones.md#fr-0065--zonen-aus-tests-oder-gemessenen-schwellen) | OQ-0003, OQ-0017 |
| FR-0066 | Schätzung aus gewöhnlichen Läufen | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0066--schätzung-aus-gewöhnlichen-läufen) | — |
| FR-0067 | Kennzeichnung als indirekte Schätzung | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0067--kennzeichnung-als-indirekte-schätzung) | CON-0009, ACC-05 |
| FR-0068 | Eingabedaten | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0068--eingabedaten) | OQ-0012, OQ-0059 |
| FR-0069 | Sauerstoffbedarf nach ACSM-Laufformel | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0069--sauerstoffbedarf-nach-acsm-laufformel) | NFR-0002, OQ-0001, OQ-0059 |
| FR-0070 | Grenzen der ACSM-Laufformel beachten | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0070--grenzen-der-acsm-laufformel-beachten) | FR-0074 |
| FR-0071 | Hochrechnung auf VO2max | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0071--hochrechnung-auf-vo2max) | FR-0060, NFR-0002, OQ-0001 |
| FR-0072 | Keine Genauigkeit ohne Validierung versprechen | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0072--keine-genauigkeit-ohne-validierung-versprechen) | NFR-0004, OQ-0020 |
| FR-0073 | Auswahl geeigneter Abschnitte | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0073--auswahl-geeigneter-abschnitte) | FR-0075, OQ-0019 |
| FR-0074 | Klare Laufgeschwindigkeit, keine unkritische Bewertung des Gehens | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0074--klare-laufgeschwindigkeit-keine-unkritische-bewertung-des-gehens) | FR-0070, OQ-0001 |
| FR-0075 | Schwellenwerte sind Modellparameter | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0075--schwellenwerte-sind-modellparameter) | NFR-0001, OQ-0019, OQ-0020 |
| FR-0076 | Verarbeitung eines Laufs | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0076--verarbeitung-eines-laufs) | FR-0045, FR-0053 |
| FR-0077 | Abweichende Schätzungen senken die Konfidenz | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0077--abweichende-schätzungen-senken-die-konfidenz) | OQ-0019, OQ-0059 |
| FR-0078 | Stabiler langfristiger Wert | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0078--stabiler-langfristiger-wert) | — |
| FR-0079 | Mögliche Glättung des langfristigen Werts | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0079--mögliche-glättung-des-langfristigen-werts) | OQ-0019 |
| FR-0080 | Keine Aktualisierung bei unzureichender Qualität | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0080--keine-aktualisierung-bei-unzureichender-qualität) | — |
| FR-0081 | Drei Sichten auf die VO2max | functional | Approved | 1 | [vo2max](specs/vo2max.md#fr-0081--drei-sichten-auf-die-vo2max) | — |
| FR-0082 | Bekannte Leistungsdaten für die Kalibrierung | functional | Draft | 4 (möglich) | [vo2max](specs/vo2max.md#fr-0082--bekannte-leistungsdaten-für-die-kalibrierung) | OQ-0001, OQ-0017 |
| FR-0083 | Messmethoden getrennt kennzeichnen | functional | Draft | 4 | [vo2max](specs/vo2max.md#fr-0083--messmethoden-getrennt-kennzeichnen) | FR-0024, OQ-0041 |
| FR-0084 | Kennzahl für aerobe Laufeffizienz | functional | Approved | 1 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0084--kennzahl-für-aerobe-laufeffizienz) | OQ-0036 |
| FR-0085 | Referenzgeschwindigkeit | functional | Approved | 1 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0085--referenzgeschwindigkeit) | OQ-0036 |
| FR-0086 | Vergleichbare Bedingungen | functional | Approved | 1 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0086--vergleichbare-bedingungen) | OQ-0036 |
| FR-0087 | Veränderung der aeroben Effizienz | functional | Approved | 1 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0087--veränderung-der-aeroben-effizienz) | OQ-0036 |
| FR-0088 | Abgrenzung zur VO2max | functional | Approved | 1 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0088--abgrenzung-zur-vo2max) | — |
| FR-0089 | Herzfrequenzdrift | functional | Draft | 4 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0089--herzfrequenzdrift) | — |
| FR-0090 | Drift nur bei geeigneten Läufen und vorsichtig deuten | functional | Draft | 4 | [aerobic-efficiency](specs/aerobic-efficiency.md#fr-0090--drift-nur-bei-geeigneten-läufen-und-vorsichtig-deuten) | OQ-0019 |
| FR-0091 | Belastung erfassen | functional | Approved | 1 | [training-load](specs/training-load.md#fr-0091--belastung-erfassen) | — |
| FR-0092 | Edwards-TRIMP als erste Variante | functional | Approved | 1 | [training-load](specs/training-load.md#fr-0092--edwards-trimp-als-erste-variante) | FR-0093, NFR-0002, OQ-0002, OQ-0014, OQ-0051 |
| FR-0093 | TRIMP-Zonen beziehen sich auf die maximale Herzfrequenz | functional | Approved | 1 | [training-load](specs/training-load.md#fr-0093--trimp-zonen-beziehen-sich-auf-die-maximale-herzfrequenz) | FR-0062, OQ-0059 |
| FR-0094 | TRIMP nicht als Maß für Ermüdung darstellen | functional | Approved | 1 | [training-load](specs/training-load.md#fr-0094--trimp-nicht-als-maß-für-ermüdung-darstellen) | — |
| FR-0095 | Subjektive Trainingsbelastung (sRPE) | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0095--subjektive-trainingsbelastung-srpe) | FR-0038, OQ-0015 |
| FR-0096 | TRIMP und sRPE getrennt führen | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0096--trimp-und-srpe-getrennt-führen) | OQ-0015 |
| FR-0097 | Konsistente Skala für Belastungsverläufe | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0097--konsistente-skala-für-belastungsverläufe) | ACC-07, OQ-0015, OQ-0046 |
| FR-0098 | Kurzfristige Trainingsbelastung (ATL) | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0098--kurzfristige-trainingsbelastung-atl) | FR-0097, OQ-0015, OQ-0016, OQ-0046, OQ-0054 |
| FR-0099 | Langfristige Trainingsbelastung (CTL) | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0099--langfristige-trainingsbelastung-ctl) | FR-0097, OQ-0015, OQ-0016, OQ-0054 |
| FR-0100 | CTL als langfristiges Belastungsniveau bezeichnen | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0100--ctl-als-langfristiges-belastungsniveau-bezeichnen) | OQ-0039 |
| FR-0101 | Training Stress Balance (TSB) | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0101--training-stress-balance-tsb) | — |
| FR-0102 | Unvollständige Belastungsdaten berücksichtigen | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0102--unvollständige-belastungsdaten-berücksichtigen) | OQ-0016, OQ-0054 |
| FR-0103 | Nicht aufgezeichnete Tage nur bedingt als trainingsfrei | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0103--nicht-aufgezeichnete-tage-nur-bedingt-als-trainingsfrei) | OQ-0016, OQ-0058 |
| FR-0104 | Fehlender Datenbestand ist kein niedriges Fitnessniveau | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0104--fehlender-datenbestand-ist-kein-niedriges-fitnessniveau) | OQ-0016 |
| FR-0105 | Zwei Stufen der Einschätzung | functional | Approved | 2 (Basis), 3 (erweitert) | [readiness](specs/readiness.md#fr-0105--zwei-stufen-der-einschätzung) | FR-0106, FR-0108 |
| FR-0106 | Basis-Erholungseinschätzung ohne Fitnessuhr | functional | Approved | 2 | [readiness](specs/readiness.md#fr-0106--basis-erholungseinschätzung-ohne-fitnessuhr) | CON-0004, OQ-0029, OQ-0057 |
| FR-0107 | Kein Anspruch auf vollständige Bestimmung | functional | Approved | 2 | [readiness](specs/readiness.md#fr-0107--kein-anspruch-auf-vollständige-bestimmung) | — |
| FR-0108 | Faktoren der erweiterten Training Readiness | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0108--faktoren-der-erweiterten-training-readiness) | FR-0022, SEC-0001 |
| FR-0109 | Wert von 0 bis 100 mit Einordnung | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0109--wert-von-0-bis-100-mit-einordnung) | OQ-0006, OQ-0059 |
| FR-0110 | Vorläufige Gewichtung | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0110--vorläufige-gewichtung) | NFR-0002, NFR-0003, NFR-0004, OQ-0020, OQ-0029, OQ-0057, OQ-0059 |
| FR-0111 | Fehlende Faktoren gelten nicht als normal | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0111--fehlende-faktoren-gelten-nicht-als-normal) | ACC-11, OQ-0029, OQ-0059 |
| FR-0112 | Persönlicher Referenzzeitraum | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0112--persönlicher-referenzzeitraum) | ACC-11, OQ-0006 |
| FR-0113 | Robuste Abweichungsbewertung | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0113--robuste-abweichungsbewertung) | OQ-0059 |
| FR-0114 | Keine künstlich präzise Abweichung | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0114--keine-künstlich-präzise-abweichung) | OQ-0006 |
| FR-0115 | Messmethoden nur konsistent vergleichen | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0115--messmethoden-nur-konsistent-vergleichen) | OQ-0059 |
| FR-0116 | Mögliche Zustände | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0116--mögliche-zustände) | OQ-0029, OQ-0058, OQ-0059 |
| FR-0117 | Wichtigste Ursachen erklären | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0117--wichtigste-ursachen-erklären) | FR-0181, OQ-0059 |
| FR-0118 | Keine medizinische Diagnose | functional | Approved | 3 | [readiness](specs/readiness.md#fr-0118--keine-medizinische-diagnose) | OQ-0026 |
| FR-0119 | Optionale Funktion | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0119--optionale-funktion) | CON-0007, OQ-0007 |
| FR-0120 | Datenvoraussetzungen | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0120--datenvoraussetzungen) | ACC-12, OQ-0007 |
| FR-0121 | Deaktiviert oder als unvollständig gekennzeichnet | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0121--deaktiviert-oder-als-unvollständig-gekennzeichnet) | ACC-12, OQ-0007 |
| FR-0122 | Berechnungsmodell | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0122--berechnungsmodell) | NFR-0002, OQ-0030, OQ-0048 |
| FR-0123 | Regenerations- und Belastungskomponente | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0123--regenerations--und-belastungskomponente) | OQ-0030 |
| FR-0124 | Empirische Kalibrierung, keine physikalische Energie | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0124--empirische-kalibrierung-keine-physikalische-energie) | NFR-0004, OQ-0030 |
| FR-0125 | Darstellung | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0125--darstellung) | — |
| FR-0126 | Keine Fortschreibung über Datenlücken | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0126--keine-fortschreibung-über-datenlücken) | CON-0009, OQ-0030 |
| FR-0127 | Getrennt von der Training Readiness | functional | Draft | 4 | [energy-reserve](specs/energy-reserve.md#fr-0127--getrennt-von-der-training-readiness) | FR-0109 |
| FR-0128 | Prognose für mögliche Distanzen | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0128--prognose-für-mögliche-distanzen) | — |
| FR-0129 | Bevorzugt tatsächliche Leistungen als Grundlage | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0129--bevorzugt-tatsächliche-leistungen-als-grundlage) | FR-0055, OQ-0034, OQ-0058, OQ-0059 |
| FR-0130 | Riegel-Modell | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0130--riegel-modell) | NFR-0002, OQ-0008 |
| FR-0131 | Voraussetzungen der Referenzleistung | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0131--voraussetzungen-der-referenzleistung) | OQ-0034 |
| FR-0132 | Einflussgrößen der Prognosequalität | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0132--einflussgrößen-der-prognosequalität) | FR-0059 |
| FR-0133 | Allgemeine Schätzung und Zielprognose unterscheiden | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0133--allgemeine-schätzung-und-zielprognose-unterscheiden) | — |
| FR-0134 | VO2max allein ist keine verbindliche Prognosegrundlage | functional | Approved | 2 | [performance-prediction](specs/performance-prediction.md#fr-0134--vo2max-allein-ist-keine-verbindliche-prognosegrundlage) | OQ-0034 |
| FR-0135 | Zieltypen | functional | Approved | 2 | [goals](specs/goals.md#fr-0135--zieltypen) | OQ-0004, OQ-0059, OQ-0060 |
| FR-0136 | Zusätzliche Angaben für die Planung | functional | Approved | 2 | [goals](specs/goals.md#fr-0136--zusätzliche-angaben-für-die-planung) | FR-0002, OQ-0013, OQ-0027, OQ-0038, OQ-0060 |
| FR-0137 | Keine feste Zielzeit erforderlich | functional | Approved | 2 | [goals](specs/goals.md#fr-0137--keine-feste-zielzeit-erforderlich) | OQ-0027, OQ-0059, OQ-0060 |
| FR-0138 | Individuellen Plan erzeugen | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0138--individuellen-plan-erzeugen) | ACC-08 |
| FR-0139 | Ausgangsanalyse | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0139--ausgangsanalyse) | OQ-0013, OQ-0027, OQ-0059, OQ-0060 |
| FR-0140 | Konservativer Einstiegsplan bei unzureichenden Daten | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0140--konservativer-einstiegsplan-bei-unzureichenden-daten) | FR-0104, OQ-0010, OQ-0028, OQ-0048, OQ-0059, OQ-0060 |
| FR-0141 | Trainingsphasen | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0141--trainingsphasen) | OQ-0027, OQ-0028, OQ-0059, OQ-0060 |
| FR-0142 | Trainingstypen | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0142--trainingstypen) | OQ-0004, OQ-0057 |
| FR-0143 | Beschreibung einer Trainingseinheit | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0143--beschreibung-einer-trainingseinheit) | OQ-0057 |
| FR-0144 | Arten der Zielintensität | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0144--arten-der-zielintensität) | OQ-0003 |
| FR-0145 | Keine genaue Pace aus unzureichender VO2max | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0145--keine-genaue-pace-aus-unzureichender-vo2max) | OQ-0028 |
| FR-0146 | Intervalle bevorzugt nach Pace oder RPE | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0146--intervalle-bevorzugt-nach-pace-oder-rpe) | — |
| FR-0147 | Regelbasierte Planung | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0147--regelbasierte-planung) | NFR-0002, OQ-0028 |
| FR-0148 | Wöchentliches Belastungsbudget | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0148--wöchentliches-belastungsbudget) | FR-0039, OQ-0028, OQ-0059, OQ-0060 |
| FR-0149 | Keine pauschale Steigerung als garantiert sicher | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0149--keine-pauschale-steigerung-als-garantiert-sicher) | OQ-0028 |
| FR-0150 | Wochen mit reduziertem Umfang | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0150--wochen-mit-reduziertem-umfang) | OQ-0028 |
| FR-0151 | Verteilung der Einheiten | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0151--verteilung-der-einheiten) | OQ-0028, OQ-0059, OQ-0060 |
| FR-0152 | Intensive Einheiten nicht ohne Erholung hintereinander | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0152--intensive-einheiten-nicht-ohne-erholung-hintereinander) | FR-0177, OQ-0028 |
| FR-0153 | Rangfolge für die Ableitung der Zielintensität | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0153--rangfolge-für-die-ableitung-der-zielintensität) | FR-0145, OQ-0003, OQ-0057, OQ-0059 |
| FR-0154 | Machbarkeit des Ziels beurteilen | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0154--machbarkeit-des-ziels-beurteilen) | FR-0137, OQ-0027, OQ-0059, OQ-0060 |
| FR-0155 | Einfache Trainingsplanung nur mit dem Smartphone | functional | Approved | 2 | [training-plan](specs/training-plan.md#fr-0155--einfache-trainingsplanung-nur-mit-dem-smartphone) | CON-0004, OQ-0028 |
| FR-0156 | Fortlaufende Anpassung | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0156--fortlaufende-anpassung) | CON-0006, OQ-0005, OQ-0011, OQ-0060 |
| FR-0157 | Auslöser einer Neuberechnung | functional | Approved | 2, 3 (Erholung) | [plan-adaptation](specs/plan-adaptation.md#fr-0157--auslöser-einer-neuberechnung) | ACC-09, FR-0039, OQ-0022, OQ-0058, OQ-0059 |
| FR-0158 | Mindestens wöchentliche Überprüfung | functional | Approved | 2, 3 (Erholung) | [plan-adaptation](specs/plan-adaptation.md#fr-0158--mindestens-wöchentliche-überprüfung) | OQ-0005, OQ-0011 |
| FR-0159 | Kurzfristige Empfehlung vor einer Einheit | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0159--kurzfristige-empfehlung-vor-einer-einheit) | FR-0179 |
| FR-0160 | Anpassung bei hoher Belastung | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0160--anpassung-bei-hoher-belastung) | OQ-0028 |
| FR-0161 | Anpassung bei deutlich besserer Leistungsentwicklung | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0161--anpassung-bei-deutlich-besserer-leistungsentwicklung) | FR-0165 |
| FR-0162 | Anpassung bei ausgefallenem Training | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0162--anpassung-bei-ausgefallenem-training) | FR-0164, OQ-0011 |
| FR-0163 | Anpassung bei Beschwerden oder Krankheit | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0163--anpassung-bei-beschwerden-oder-krankheit) | FR-0118, OQ-0026, OQ-0048 |
| FR-0164 | Kontinuität vor exaktem Nachholen | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0164--kontinuität-vor-exaktem-nachholen) | — |
| FR-0165 | Keine starke Erhöhung nach einer einzelnen Messung | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0165--keine-starke-erhöhung-nach-einer-einzelnen-messung) | — |
| FR-0166 | Konservative Anpassung bei Überlastungssignalen | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0166--konservative-anpassung-bei-überlastungssignalen) | OQ-0026, OQ-0028 |
| FR-0167 | Pausen und Wiedereinstiege berücksichtigen | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0167--pausen-und-wiedereinstiege-berücksichtigen) | OQ-0028, OQ-0059, OQ-0060 |
| FR-0168 | Ziel nur mit Zustimmung ändern | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0168--ziel-nur-mit-zustimmung-ändern) | — |
| FR-0169 | Nutzer behält die Kontrolle über Termine | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0169--nutzer-behält-die-kontrolle-über-termine) | FR-0176, OQ-0011 |
| FR-0170 | Größere Änderungen begründen | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0170--größere-änderungen-begründen) | FR-0180, ACC-10, OQ-0028, OQ-0060 |
| FR-0171 | Kalender mit geplanten und absolvierten Einheiten | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0171--kalender-mit-geplanten-und-absolvierten-einheiten) | — |
| FR-0172 | Ansichten und Kennzeichnungen | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0172--ansichten-und-kennzeichnungen) | — |
| FR-0173 | Training verschieben, ersetzen, Ruhetage festlegen | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0173--training-verschieben-ersetzen-ruhetage-festlegen) | OQ-0011 |
| FR-0174 | Trainingszeiten und Erinnerungen | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0174--trainingszeiten-und-erinnerungen) | — |
| FR-0175 | Termine empfehlen | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0175--termine-empfehlen) | FR-0176 |
| FR-0176 | Bestätigung vor Kalenderänderungen | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0176--bestätigung-vor-kalenderänderungen) | FR-0156, FR-0169, OQ-0011, OQ-0005 |
| FR-0177 | Prüfung beim Verschieben | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0177--prüfung-beim-verschieben) | FR-0152 |
| FR-0178 | Alternativen bei Konflikten | functional | Approved | 2 | [calendar](specs/calendar.md#fr-0178--alternativen-bei-konflikten) | — |
| FR-0179 | Bedeutung erklären | functional | Approved | 2 | [explanations](specs/explanations.md#fr-0179--bedeutung-erklären) | CON-0005 |
| FR-0180 | Erklärungsarten | functional | Approved | 2 | [explanations](specs/explanations.md#fr-0180--erklärungsarten) | FR-0170, OQ-0011, OQ-0039 |
| FR-0181 | Erklärungen beruhen auf tatsächlichen Daten | functional | Approved | 2 | [explanations](specs/explanations.md#fr-0181--erklärungen-beruhen-auf-tatsächlichen-daten) | FR-0059 |
| FR-0182 | Dateiexport als GPX, TCX und FIT | functional | Approved | 1 | [export-sync](specs/export-sync.md#fr-0182--dateiexport-als-gpx-tcx-und-fit) | CON-0010, ACC-13, OQ-0032, OQ-0066 |
| FR-0183 | Exportinhalte | functional | Approved | 1 | [export-sync](specs/export-sync.md#fr-0183--exportinhalte) | — |
| FR-0184 | Zusatzmetriken separat exportierbar | functional | Approved | 2 | [export-sync](specs/export-sync.md#fr-0184--zusatzmetriken-separat-exportierbar) | OQ-0032 |
| FR-0185 | Strava-Konto einmalig verknüpfen | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0185--strava-konto-einmalig-verknüpfen) | SEC-0003, SEC-0008, OQ-0024, OQ-0049 |
| FR-0186 | Manueller Upload einzelner Läufe | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0186--manueller-upload-einzelner-läufe) | SEC-0008, OQ-0049 |
| FR-0187 | Optionale automatische Synchronisierung | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0187--optionale-automatische-synchronisierung) | SEC-0003, SEC-0008, OQ-0025, OQ-0032, OQ-0049 |
| FR-0188 | Upload-Status anzeigen | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0188--upload-status-anzeigen) | OQ-0049 |
| FR-0189 | Uploadfehler behandeln | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0189--uploadfehler-behandeln) | CON-0010, OQ-0032, OQ-0049 |
| FR-0190 | Doppelte Uploads vermeiden | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0190--doppelte-uploads-vermeiden) | OQ-0032, OQ-0049 |
| FR-0191 | Verbindung trennen | functional | Draft | Zurückgestellt (OQ-0049) | [export-sync](specs/export-sync.md#fr-0191--verbindung-trennen) | SEC-0007, OQ-0025, OQ-0049 |
| FR-0192 | Gesamtexport der Nutzerdaten | functional | Approved | 1 | [export-sync](specs/export-sync.md#fr-0192--gesamtexport-der-nutzerdaten) | SEC-0004, CON-0008, ACC-15, OQ-0041, OQ-0032, SEC-0011, OQ-0050 |
| FR-0193 | Laufende Sicherung und Wiederaufnahme | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0193--laufende-sicherung-und-wiederaufnahme) | FR-0034, FR-0036, OQ-0021, OQ-0061, OQ-0065 |
| FR-0194 | Verhalten bei GPS-Verlust | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0194--verhalten-bei-gps-verlust) | FR-0049, FR-0057, OQ-0021 |
| FR-0195 | Start nur mit Standortberechtigung | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0195--start-nur-mit-standortberechtigung) | OQ-0021, OQ-0064 |
| FR-0196 | Laufbandmodus | functional | Approved | 2 | [run-recording](specs/run-recording.md#fr-0196--laufbandmodus) | FR-0195, OQ-0042 |
| FR-0197 | Belastungsprofil wählen | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0197--belastungsprofil-wählen) | FR-0097, NFR-0005, OQ-0043, OQ-0045, OQ-0053 |
| FR-0198 | Reimport des Gesamtexports | functional | Approved | 1 | [export-sync](specs/export-sync.md#fr-0198--reimport-des-gesamtexports) | FR-0192, OQ-0032 |
| FR-0199 | Training manuell nachtragen | functional | Approved | 2 | [training-load](specs/training-load.md#fr-0199--training-manuell-nachtragen) | FR-0157, FR-0095, OQ-0022, OQ-0058 |
| FR-0200 | Import über Health Connect | functional | Approved | 3 | [health-import](specs/health-import.md#fr-0200--import-über-health-connect) | FR-0022, SEC-0002, CON-0003, OQ-0033, OQ-0047, OQ-0059 |
| FR-0201 | Export teilen | functional | Approved | 1 | [export-sync](specs/export-sync.md#fr-0201--export-teilen) | FR-0182, CON-0010, OQ-0049 |
| FR-0202 | Schrittfrequenz aus dem Smartphone | functional | Approved | 1 | [run-recording](specs/run-recording.md#fr-0202--schrittfrequenz-aus-dem-smartphone) | FR-0027, FR-0021, OQ-0052 |
| FR-0203 | Warnsignal melden und aufheben | functional | Approved | 2 | [plan-adaptation](specs/plan-adaptation.md#fr-0203--warnsignal-melden-und-aufheben) | FR-0163, FR-0118, OQ-0026, OQ-0048, OQ-0055, OQ-0058 |
| NFR-0001 | Algorithmen versionierbar und nachvollziehbar | non-functional | Approved | 1* | [non-functional](quality/non-functional.md#nfr-0001--algorithmen-versionierbar-und-nachvollziehbar) | FR-0053, FR-0058 |
| NFR-0002 | Einordnung in drei Verfahrenskategorien | non-functional | Approved | 1* | [non-functional](quality/non-functional.md#nfr-0002--einordnung-in-drei-verfahrenskategorien) | — |
| NFR-0003 | Heuristiken nicht als validiert darstellen | non-functional | Approved | 1* | [non-functional](quality/non-functional.md#nfr-0003--heuristiken-nicht-als-validiert-darstellen) | FR-0054 |
| NFR-0004 | Validierung vor Genauigkeitsaussagen | non-functional | Approved | 1* | [non-functional](quality/non-functional.md#nfr-0004--validierung-vor-genauigkeitsaussagen) | FR-0072, FR-0110, FR-0124, OQ-0020 |
| NFR-0005 | Austauschbare Algorithmen | non-functional | Approved | 1* | [non-functional](quality/non-functional.md#nfr-0005--austauschbare-algorithmen) | NFR-0001, NFR-0002, FR-0197, OQ-0043 |
| NFR-0006 | Sprachen und Einheiten | non-functional | Approved | 1 | [non-functional](quality/non-functional.md#nfr-0006--sprachen-und-einheiten) | CON-0001, FR-0031, OQ-0035, OQ-0067 |
| SEC-0001 | Gesundheitsdaten nur mit ausdrücklicher Zustimmung | non-functional | Approved | 1 | [security](quality/security.md#sec-0001--gesundheitsdaten-nur-mit-ausdrücklicher-zustimmung) | FR-0022, OQ-0017, OQ-0025, OQ-0048 |
| SEC-0002 | Datenquellen getrennt freigeben | non-functional | Approved | 1 | [security](quality/security.md#sec-0002--datenquellen-getrennt-freigeben) | OQ-0017 |
| SEC-0003 | Externe Synchronisierung ist optional | non-functional | Approved | 1 | [security](quality/security.md#sec-0003--externe-synchronisierung-ist-optional) | CON-0010, FR-0187, OQ-0017 |
| SEC-0004 | Export und Löschung der eigenen Daten | non-functional | Approved | 1 | [security](quality/security.md#sec-0004--export-und-löschung-der-eigenen-daten) | FR-0192, ACC-15, OQ-0017, OQ-0025 |
| SEC-0005 | Datenherkunft erkennbar | non-functional | Approved | 1 | [security](quality/security.md#sec-0005--datenherkunft-erkennbar) | FR-0020, FR-0053, OQ-0017 |
| SEC-0006 | Berechnungen ohne zwingende externe Übertragung | non-functional | Approved | 1 | [security](quality/security.md#sec-0006--berechnungen-ohne-zwingende-externe-übertragung) | CON-0008, OQ-0017, OQ-0023 |
| SEC-0007 | Berechtigungen widerrufen | non-functional | Approved | 1 | [security](quality/security.md#sec-0007--berechtigungen-widerrufen) | FR-0191, OQ-0017, OQ-0025 |
| SEC-0008 | Keine Übertragung an Dritte ohne Einwilligung | non-functional | Approved | 1 | [security](quality/security.md#sec-0008--keine-übertragung-an-dritte-ohne-einwilligung) | FR-0185, FR-0186, FR-0187, OQ-0017, OQ-0025 |
| SEC-0009 | Verschlüsselte Speicherung | non-functional | Approved | 1 | [security](quality/security.md#sec-0009--verschlüsselte-speicherung) | FR-0185, OQ-0024, OQ-0062 |
| SEC-0010 | System-Backups immer aus | non-functional | Approved | 1 | [security](quality/security.md#sec-0010--system-backups-immer-aus) | SEC-0008, FR-0192, OQ-0024, OQ-0056 |
| SEC-0011 | Verschlüsseltes Archiv | non-functional | Approved | 1 | [security](quality/security.md#sec-0011--verschlüsseltes-archiv) | SEC-0009, FR-0192, FR-0198, OQ-0050 |
| CON-0001 | Zielplattformen | constraint | Approved | 1 | [product](product.md#con-0001--zielplattformen) | OQ-0035, OQ-0063 |
| CON-0002 | Technik ist nicht Gegenstand der Quelle | constraint | Approved | 1 | [product](product.md#con-0002--technik-ist-nicht-gegenstand-der-quelle) | OQ-0023 |
| CON-0003 | Geräteunabhängigkeit | constraint | Approved | 1 | [product](product.md#con-0003--geräteunabhängigkeit) | FR-0007, FR-0010 |
| CON-0004 | Funktionalität ohne Wearable | constraint | Approved | 1 | [product](product.md#con-0004--funktionalität-ohne-wearable) | FR-0035, FR-0155, ACC-01 |
| CON-0005 | Transparente Berechnungen | constraint | Approved | 1 | [product](product.md#con-0005--transparente-berechnungen) | FR-0053, FR-0059, FR-0179 |
| CON-0006 | Adaptive Trainingsplanung | constraint | Approved | 2 | [product](product.md#con-0006--adaptive-trainingsplanung) | FR-0156 |
| CON-0007 | Optionale Gesundheitsdaten | constraint | Approved | 1 | [product](product.md#con-0007--optionale-gesundheitsdaten) | FR-0022, FR-0119 |
| CON-0008 | Datenhoheit | constraint | Approved | 1 | [product](product.md#con-0008--datenhoheit) | FR-0182, FR-0192, SEC-0004, OQ-0023 |
| CON-0009 | Kennzeichnung von Unsicherheit | constraint | Approved | 1 | [product](product.md#con-0009--kennzeichnung-von-unsicherheit) | FR-0057, FR-0067 |
| CON-0010 | Unabhängigkeit von externen Plattformen | constraint | Approved | 1 | [product](product.md#con-0010--unabhängigkeit-von-externen-plattformen) | FR-0182, FR-0185, SEC-0003, ACC-14 |
<!-- END REGISTER -->
