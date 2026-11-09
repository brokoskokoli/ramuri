# Traceability

Bildet Aussagen aus SRC-001 auf Ergebnisse ab. Zeilenangaben beziehen sich auf die Kopie in `sources/`. Teil A wird generiert, Teil B wird von Hand gepflegt. SRC-002 enthält keine Produktaussagen und wird deshalb nicht einzeln abgebildet.

`Ungeklärt` in Teil A heißt: Die Aussage ist übernommen, ihre Anforderung hat aber den Status `Blocked`.

## Teil A: Anforderungen

<!-- BEGIN TRACE -->
| Quelle | Fundstelle | Aussage / Kurzfassung | Ergebnis | Dokument | Akzeptanzkriterium | Status |
|---|---|---|---|---|---|---|
| SRC-001 | §2, Z. 33 | Profil beim ersten Start einrichten | FR-0001 | [profile.md](../specs/profile.md) | 2 AK | Übernommen |
| SRC-001 | §2.1, Z. 37–47 | Profildatenfelder | FR-0002 | [profile.md](../specs/profile.md) | 3 AK | Übernommen |
| SRC-001 | §2.1, Z. 49 | Gemessene maximale Herzfrequenz hat Vorrang | FR-0003 | [profile.md](../specs/profile.md) | 1 AK | Übernommen |
| SRC-001 | §2.1, Z. 51–55 | Altersbasierte Näherung der maximalen Herzfrequenz | FR-0004 | [profile.md](../specs/profile.md) | 2 AK | Übernommen |
| SRC-001 | §2.1, Z. 57 | Hinweis auf Streuung und Korrektur der Näherung | FR-0005 | [profile.md](../specs/profile.md) | 2 AK | Übernommen |
| SRC-001 | §2.1, Z. 59 | Neuberechnung nach Änderung der Basiswerte | FR-0006 | [profile.md](../specs/profile.md) | 2 AK | Übernommen |
| SRC-001 | §3 und §3.1, Z. 63–74 | Unterstützte Gerätekategorien | FR-0007 | [sensors.md](../specs/sensors.md) | 1 AK, ACC-02 | Übernommen |
| SRC-001 | §3.1, Z. 76 | Automatische Erkennung standardisierter Geräte | FR-0008 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.1, Z. 78 | Ergänzende Uhrenanwendung | FR-0009 | [sensors.md](../specs/sensors.md) | TBD | Übernommen |
| SRC-001 | §3.1, Z. 80 | Herstellerspezifische Anbindungen sind optional | FR-0010 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.2, Z. 84–86 | Geräte suchen | FR-0011 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.2, Z. 87 | Gerät verbinden und trennen | FR-0012 | [sensors.md](../specs/sensors.md) | 1 AK, ACC-02 | Übernommen |
| SRC-001 | §3.2, Z. 88 | Mehrere bekannte Geräte speichern | FR-0013 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.2, Z. 89 | Bevorzugtes Gerät festlegen | FR-0014 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.2, Z. 90 | Aktuelle Herzfrequenz anzeigen | FR-0015 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.2, Z. 91 | Batteriestand anzeigen, sofern bereitgestellt | FR-0016 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.2, Z. 92 | Verbindungsabbrüche erkennen | FR-0017 | [sensors.md](../specs/sensors.md) | 2 AK, ACC-03 | Übernommen |
| SRC-001 | §3.2, Z. 93 | Datenquelle während des Trainings wechseln | FR-0018 | [sensors.md](../specs/sensors.md) | 3 AK | Übernommen |
| SRC-001 | §3.2, Z. 95 | Eindeutige Priorisierung ohne Vermischung | FR-0019 | [sensors.md](../specs/sensors.md) | 2 AK | Übernommen |
| SRC-001 | §3.2, Z. 97 | Herkunft der Messwerte dokumentieren | FR-0020 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3.3, Z. 101–109 | Erweiterte Sensordaten aufzeichnen | FR-0021 | [sensors.md](../specs/sensors.md) | 1 AK | Übernommen |
| SRC-001 | §3 und §3.4, Z. 113 | Import nur mit Zustimmung | FR-0022 | [health-import.md](../specs/health-import.md) | 1 AK | Übernommen |
| SRC-001 | §3.4, Z. 115–122 | Importierbare Datenarten | FR-0023 | [health-import.md](../specs/health-import.md) | 1 AK | Übernommen |
| SRC-001 | §3.4, Z. 124 | Fremde VO2max-Werte nicht ungeprüft zusammenführen | FR-0024 | [health-import.md](../specs/health-import.md) | 3 AK | Übernommen |
| SRC-001 | §4.1, Z. 130 | Freie oder geplante Einheit starten | FR-0025 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-001 | §4.1, Z. 132–140 | Pflichtanzeigen während des Trainings | FR-0026 | [run-recording.md](../specs/run-recording.md) | 3 AK | Übernommen |
| SRC-001 | §4.1, Z. 142–148 | Optionale Anzeigen während des Trainings | FR-0027 | [run-recording.md](../specs/run-recording.md) | TBD | Übernommen |
| SRC-001 | §4.2, Z. 152–157 | Training starten, pausieren, fortsetzen, beenden | FR-0028 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-001 | §4.2, Z. 158 | Automatisches Pausieren | FR-0029 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-001 | §4.2, Z. 159 | Manuelle Rundenmarkierung | FR-0030 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-001 | §4.2, Z. 160 | Akustische Trainingshinweise | FR-0031 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-001 | §4.2, Z. 161 | Warnung bei Überschreitung des Herzfrequenzbereichs | FR-0032 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-001 | §4.2, Z. 162 | Hinweise zum nächsten Trainingsintervall | FR-0033 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-001 | §4.2, Z. 164 | Aufzeichnung bei ausgeschaltetem Bildschirm | FR-0034 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-001 | §25 Nr. 1, Z. 1396 | Aufzeichnung ohne Pulssensor | FR-0035 | [run-recording.md](../specs/run-recording.md) | 1 AK, ACC-01 | Übernommen |
| SRC-001 | §25 Nr. 3, Z. 1398 | Verbindungsabbruch verliert den übrigen Lauf nicht | FR-0036 | [run-recording.md](../specs/run-recording.md) | 1 AK, ACC-03 | Übernommen |
| SRC-001 | §4.3, Z. 168–180 | Zusammenfassung nach dem Lauf | FR-0037 | [run-recording.md](../specs/run-recording.md) | 3 AK | Übernommen |
| SRC-001 | §4.3, Z. 182–187 | Subjektive Angaben erfassen | FR-0038 | [run-recording.md](../specs/run-recording.md) | 4 AK | Übernommen |
| SRC-001 | §4.3, Z. 189 | Subjektive Angaben in der Planung berücksichtigen | FR-0039 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-001 | §5, Z. 193 | Trainingshistorie | FR-0040 | [history-statistics.md](../specs/history-statistics.md) | 2 AK, ACC-04 | Übernommen |
| SRC-001 | §25 Nr. 4, Z. 1399 | Trainingshistorie | FR-0040 | [history-statistics.md](../specs/history-statistics.md) | 2 AK, ACC-04 | Übernommen |
| SRC-001 | §5.1, Z. 197 | Detailansicht eines Laufs | FR-0041 | [history-statistics.md](../specs/history-statistics.md) | 1 AK | Übernommen |
| SRC-001 | §5.1, Z. 199 | Pace und Herzfrequenz zeitlich vergleichen | FR-0042 | [history-statistics.md](../specs/history-statistics.md) | 1 AK | Übernommen |
| SRC-001 | §5.2, Z. 203–212 | Statistische Kennzahlen | FR-0043 | [history-statistics.md](../specs/history-statistics.md) | 1 AK | Übernommen |
| SRC-001 | §5.2, Z. 214 | Auswertungszeiträume | FR-0044 | [history-statistics.md](../specs/history-statistics.md) | 2 AK | Übernommen |
| SRC-001 | §6, Z. 218–220 | Keine Fitnessberechnung auf ungefilterten Daten | FR-0045 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §6.1, Z. 224 | Synchronisation über Zeitstempel | FR-0046 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §6.1, Z. 226–235 | Zu berücksichtigende Datenprobleme | FR-0047 | [data-quality.md](../specs/data-quality.md) | 2 AK | Übernommen |
| SRC-001 | §6.1, Z. 237 | Qualitätsbewertung je Abschnitt | FR-0048 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §6.2, Z. 241 | Strecke aus plausiblen Positionsdistanzen | FR-0049 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §6.2, Z. 243–253 | Geschwindigkeit und Pace | FR-0050 | [data-quality.md](../specs/data-quality.md) | 2 AK | Übernommen |
| SRC-001 | §6.2, Z. 255 | Geglättete Tempoanzeige | FR-0051 | [data-quality.md](../specs/data-quality.md) | 2 AK | Übernommen |
| SRC-001 | §6.2, Z. 257 | Bewegungszeit und Gesamtzeit getrennt | FR-0052 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §6.3, Z. 261–269 | Metadaten jedes fortgeschrittenen Fitnesswerts | FR-0053 | [data-quality.md](../specs/data-quality.md) | 2 AK | Übernommen |
| SRC-001 | §6.3, Z. 271 | Qualitätsstufen sind keine Genauigkeitsangaben | FR-0054 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §22, Z. 1248–1257 | Funktionen je Datenverfügbarkeitsstufe | FR-0055 | [data-quality.md](../specs/data-quality.md) | 2 AK | Übernommen |
| SRC-001 | §22, Z. 1259 | Fehlender Sensorwert ist keine Nullmessung | FR-0056 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §22, Z. 1261–1266 | Vier Zustände eines Messwerts | FR-0057 | [data-quality.md](../specs/data-quality.md) | 1 AK | Übernommen |
| SRC-001 | §23.2, Z. 1311–1317 | Ursprüngliche und neu berechnete Werte unterscheiden | FR-0058 | [data-quality.md](../specs/data-quality.md) | 4 AK | Übernommen |
| SRC-001 | §23.3, Z. 1321–1328 | Nachvollziehbarkeit eines geschätzten Werts | FR-0059 | [data-quality.md](../specs/data-quality.md) | 2 AK, ACC-06 | Übernommen |
| SRC-001 | §25 Nr. 6, Z. 1401 | Nachvollziehbarkeit eines geschätzten Werts | FR-0059 | [data-quality.md](../specs/data-quality.md) | 2 AK, ACC-06 | Übernommen |
| SRC-001 | §7.1, Z. 277–299 | Herzfrequenzreserve und relative Auslastung | FR-0060 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | 3 AK | Übernommen |
| SRC-001 | §7.2, Z. 303 | Fünf konfigurierbare Zonen | FR-0061 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | 1 AK | Übernommen |
| SRC-001 | §7.2, Z. 305–313 | Vorläufiges Zonenmodell auf Basis der Herzfrequenzreserve | FR-0062 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | 3 AK | Übernommen |
| SRC-001 | §7.2, Z. 315 | Bereiche unter Zone 1 separat ausweisen | FR-0063 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | 1 AK | Übernommen |
| SRC-001 | §7.2, Z. 317 | Zonen als Näherung kennzeichnen | FR-0064 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | 1 AK | Übernommen |
| SRC-001 | §7.2, Z. 319 | Zonen aus Tests oder gemessenen Schwellen | FR-0065 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | TBD | Übernommen |
| SRC-001 | §8, Z. 323–325 | Schätzung aus gewöhnlichen Läufen | FR-0066 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8, Z. 327 | Kennzeichnung als indirekte Schätzung | FR-0067 | [vo2max.md](../specs/vo2max.md) | 2 AK, ACC-05 | Übernommen |
| SRC-001 | §25 Nr. 5, Z. 1400 | Kennzeichnung als indirekte Schätzung | FR-0067 | [vo2max.md](../specs/vo2max.md) | 2 AK, ACC-05 | Übernommen |
| SRC-001 | §8.1, Z. 331–343 | Eingabedaten | FR-0068 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.2, Z. 347–363 | Sauerstoffbedarf nach ACSM-Laufformel | FR-0069 | [vo2max.md](../specs/vo2max.md) | 2 AK | Übernommen |
| SRC-001 | §8.2, Z. 365 | Grenzen der ACSM-Laufformel beachten | FR-0070 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.3, Z. 369–407 | Hochrechnung auf VO2max | FR-0071 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.3, Z. 409 | Keine Genauigkeit ohne Validierung versprechen | FR-0072 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.4, Z. 413–425 | Auswahl geeigneter Abschnitte | FR-0073 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.4, Z. 427 | Klare Laufgeschwindigkeit, keine unkritische Bewertung des Gehens | FR-0074 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.4, Z. 429 | Schwellenwerte sind Modellparameter | FR-0075 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.5, Z. 433–443 | Verarbeitung eines Laufs | FR-0076 | [vo2max.md](../specs/vo2max.md) | 2 AK | Übernommen |
| SRC-001 | §8.5, Z. 445 | Abweichende Schätzungen senken die Konfidenz | FR-0077 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.6, Z. 449–451, 469 | Stabiler langfristiger Wert | FR-0078 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.6, Z. 453–459 | Mögliche Glättung des langfristigen Werts | FR-0079 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.6, Z. 461 | Keine Aktualisierung bei unzureichender Qualität | FR-0080 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.6, Z. 463–467 | Drei Sichten auf die VO2max | FR-0081 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.7, Z. 473–480 | Bekannte Leistungsdaten für die Kalibrierung | FR-0082 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §8.7, Z. 482 | Messmethoden getrennt kennzeichnen | FR-0083 | [vo2max.md](../specs/vo2max.md) | 1 AK | Übernommen |
| SRC-001 | §9, Z. 486–488 | Kennzahl für aerobe Laufeffizienz | FR-0084 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 1 AK | Übernommen |
| SRC-001 | §9.1, Z. 492–494 | Referenzgeschwindigkeit | FR-0085 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 2 AK | Übernommen |
| SRC-001 | §9.1, Z. 496–501 | Vergleichbare Bedingungen | FR-0086 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 1 AK | Übernommen |
| SRC-001 | §9.2, Z. 505–518 | Veränderung der aeroben Effizienz | FR-0087 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 2 AK | Übernommen |
| SRC-001 | §9.2, Z. 520 | Abgrenzung zur VO2max | FR-0088 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 1 AK | Übernommen |
| SRC-001 | §9.3, Z. 524–534 | Herzfrequenzdrift | FR-0089 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 1 AK | Übernommen |
| SRC-001 | §9.3, Z. 536–538 | Drift nur bei geeigneten Läufen und vorsichtig deuten | FR-0090 | [aerobic-efficiency.md](../specs/aerobic-efficiency.md) | 2 AK | Übernommen |
| SRC-001 | §10, Z. 542 | Belastung erfassen | FR-0091 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §10.1, Z. 546–548, 552–576 | Edwards-TRIMP als erste Variante | FR-0092 | [training-load.md](../specs/training-load.md) | 4 AK | Übernommen |
| SRC-001 | §10.1, Z. 550 | TRIMP-Zonen beziehen sich auf die maximale Herzfrequenz | FR-0093 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §10.1, Z. 578 | TRIMP nicht als Maß für Ermüdung darstellen | FR-0094 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §10.2, Z. 582–596 | Subjektive Trainingsbelastung (sRPE) | FR-0095 | [training-load.md](../specs/training-load.md) | 2 AK | Übernommen |
| SRC-001 | §10.2, Z. 598–600 | TRIMP und sRPE getrennt führen | FR-0096 | [training-load.md](../specs/training-load.md) | 2 AK | Übernommen |
| SRC-001 | §10.2, Z. 602 | Konsistente Skala für Belastungsverläufe | FR-0097 | [training-load.md](../specs/training-load.md) | 3 AK, ACC-07 | Übernommen |
| SRC-001 | §25 Nr. 7, Z. 1402 | Konsistente Skala für Belastungsverläufe | FR-0097 | [training-load.md](../specs/training-load.md) | 3 AK, ACC-07 | Übernommen |
| SRC-001 | §10.3, Z. 606–614 | Kurzfristige Trainingsbelastung (ATL) | FR-0098 | [training-load.md](../specs/training-load.md) | 3 AK | Übernommen |
| SRC-001 | §10.4, Z. 618–624 | Langfristige Trainingsbelastung (CTL) | FR-0099 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §10.4, Z. 626 | CTL als langfristiges Belastungsniveau bezeichnen | FR-0100 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §10.5, Z. 630–638 | Training Stress Balance (TSB) | FR-0101 | [training-load.md](../specs/training-load.md) | 2 AK | Übernommen |
| SRC-001 | §10.6, Z. 642 | Unvollständige Belastungsdaten berücksichtigen | FR-0102 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §10.6, Z. 644 | Nicht aufgezeichnete Tage nur bedingt als trainingsfrei | FR-0103 | [training-load.md](../specs/training-load.md) | 2 AK | Übernommen |
| SRC-001 | §10.6, Z. 646 | Fehlender Datenbestand ist kein niedriges Fitnessniveau | FR-0104 | [training-load.md](../specs/training-load.md) | 1 AK | Übernommen |
| SRC-001 | §11, Z. 650–652 | Zwei Stufen der Einschätzung | FR-0105 | [readiness.md](../specs/readiness.md) | 1 AK | Übernommen |
| SRC-001 | §11.1, Z. 656–668 | Basis-Erholungseinschätzung ohne Fitnessuhr | FR-0106 | [readiness.md](../specs/readiness.md) | 1 AK | Übernommen |
| SRC-001 | §11.1, Z. 670 | Kein Anspruch auf vollständige Bestimmung | FR-0107 | [readiness.md](../specs/readiness.md) | 3 AK | Übernommen |
| SRC-001 | §11.2, Z. 674–681 | Faktoren der erweiterten Training Readiness | FR-0108 | [readiness.md](../specs/readiness.md) | 1 AK | Übernommen |
| SRC-001 | §11.2, Z. 683 | Wert von 0 bis 100 mit Einordnung | FR-0109 | [readiness.md](../specs/readiness.md) | 2 AK | Übernommen |
| SRC-001 | §11.2, Z. 685–695 | Vorläufige Gewichtung | FR-0110 | [readiness.md](../specs/readiness.md) | 4 AK | Übernommen |
| SRC-001 | §11.2, Z. 697 | Fehlende Faktoren gelten nicht als normal | FR-0111 | [readiness.md](../specs/readiness.md) | 2 AK, ACC-11 | Übernommen |
| SRC-001 | §25 Nr. 11, Z. 1406 | Fehlende Faktoren gelten nicht als normal | FR-0111 | [readiness.md](../specs/readiness.md) | 2 AK, ACC-11 | Übernommen |
| SRC-001 | §11.3, Z. 701–703 | Persönlicher Referenzzeitraum | FR-0112 | [readiness.md](../specs/readiness.md) | 1 AK, ACC-11 | Übernommen |
| SRC-001 | §11.3, Z. 705–711 | Robuste Abweichungsbewertung | FR-0113 | [readiness.md](../specs/readiness.md) | 2 AK | Übernommen |
| SRC-001 | §11.3, Z. 713 | Keine künstlich präzise Abweichung | FR-0114 | [readiness.md](../specs/readiness.md) | 1 AK | Übernommen |
| SRC-001 | §11.3, Z. 715–717 | Messmethoden nur konsistent vergleichen | FR-0115 | [readiness.md](../specs/readiness.md) | 3 AK | Übernommen |
| SRC-001 | §11.4, Z. 721–727 | Mögliche Zustände | FR-0116 | [readiness.md](../specs/readiness.md) | 3 AK | Übernommen |
| SRC-001 | §11.4, Z. 729–733 | Wichtigste Ursachen erklären | FR-0117 | [readiness.md](../specs/readiness.md) | 2 AK | Übernommen |
| SRC-001 | §11.4, Z. 735 | Keine medizinische Diagnose | FR-0118 | [readiness.md](../specs/readiness.md) | 1 AK | Übernommen |
| SRC-001 | §12, Z. 739–741 | Optionale Funktion | FR-0119 | [energy-reserve.md](../specs/energy-reserve.md) | 2 AK | Übernommen |
| SRC-001 | §12.1, Z. 745–751, 755 | Datenvoraussetzungen | FR-0120 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK, ACC-12 | Übernommen |
| SRC-001 | §12.1, Z. 753 | Deaktiviert oder als unvollständig gekennzeichnet | FR-0121 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK, ACC-12 | Übernommen |
| SRC-001 | §25 Nr. 12, Z. 1407 | Deaktiviert oder als unvollständig gekennzeichnet | FR-0121 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK, ACC-12 | Übernommen |
| SRC-001 | §12.2, Z. 759–771 | Berechnungsmodell | FR-0122 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK | Übernommen |
| SRC-001 | §12.3–12.4, Z. 775–789 | Regenerations- und Belastungskomponente | FR-0123 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK | Übernommen |
| SRC-001 | §12.4, Z. 791–793 | Empirische Kalibrierung, keine physikalische Energie | FR-0124 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK | Übernommen |
| SRC-001 | §12.5, Z. 797–803 | Darstellung | FR-0125 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK | Übernommen |
| SRC-001 | §12.5, Z. 805 | Keine Fortschreibung über Datenlücken | FR-0126 | [energy-reserve.md](../specs/energy-reserve.md) | 2 AK | Übernommen |
| SRC-001 | §12.5, Z. 807 | Getrennt von der Training Readiness | FR-0127 | [energy-reserve.md](../specs/energy-reserve.md) | 1 AK | Übernommen |
| SRC-001 | §13, Z. 811–818 | Prognose für mögliche Distanzen | FR-0128 | [performance-prediction.md](../specs/performance-prediction.md) | 1 AK | Übernommen |
| SRC-001 | §13, Z. 820 | Bevorzugt tatsächliche Leistungen als Grundlage | FR-0129 | [performance-prediction.md](../specs/performance-prediction.md) | 4 AK | Übernommen |
| SRC-001 | §13.1, Z. 824–838 | Riegel-Modell | FR-0130 | [performance-prediction.md](../specs/performance-prediction.md) | 1 AK | Übernommen |
| SRC-001 | §13.1, Z. 840–842 | Voraussetzungen der Referenzleistung | FR-0131 | [performance-prediction.md](../specs/performance-prediction.md) | 1 AK | Übernommen |
| SRC-001 | §13.2, Z. 846–852 | Einflussgrößen der Prognosequalität | FR-0132 | [performance-prediction.md](../specs/performance-prediction.md) | 1 AK | Übernommen |
| SRC-001 | §13.2, Z. 854 | Allgemeine Schätzung und Zielprognose unterscheiden | FR-0133 | [performance-prediction.md](../specs/performance-prediction.md) | 1 AK | Übernommen |
| SRC-001 | §13.2, Z. 856 | VO2max allein ist keine verbindliche Prognosegrundlage | FR-0134 | [performance-prediction.md](../specs/performance-prediction.md) | 1 AK | Übernommen |
| SRC-001 | §14 und §14.1, Z. 860–887 | Zieltypen | FR-0135 | [goals.md](../specs/goals.md) | 3 AK | Übernommen |
| SRC-001 | §14.2, Z. 891–900 | Zusätzliche Angaben für die Planung | FR-0136 | [goals.md](../specs/goals.md) | 4 AK | Übernommen |
| SRC-001 | §14.2, Z. 902 | Keine feste Zielzeit erforderlich | FR-0137 | [goals.md](../specs/goals.md) | 3 AK | Übernommen |
| SRC-001 | §15, Z. 906 | Individuellen Plan erzeugen | FR-0138 | [training-plan.md](../specs/training-plan.md) | 1 AK, ACC-08 | Übernommen |
| SRC-001 | §25 Nr. 8, Z. 1403 | Individuellen Plan erzeugen | FR-0138 | [training-plan.md](../specs/training-plan.md) | 1 AK, ACC-08 | Übernommen |
| SRC-001 | §15.1, Z. 910–919 | Ausgangsanalyse | FR-0139 | [training-plan.md](../specs/training-plan.md) | 3 AK | Übernommen |
| SRC-001 | §15.1, Z. 921–923 | Konservativer Einstiegsplan bei unzureichenden Daten | FR-0140 | [training-plan.md](../specs/training-plan.md) | 4 AK | Übernommen |
| SRC-001 | §15.2, Z. 927–938 | Trainingsphasen | FR-0141 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §15.3, Z. 942–953 | Trainingstypen | FR-0142 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §15.4, Z. 957–966 | Beschreibung einer Trainingseinheit | FR-0143 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §15.4, Z. 968–972 | Arten der Zielintensität | FR-0144 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §15.4, Z. 974 | Keine genaue Pace aus unzureichender VO2max | FR-0145 | [training-plan.md](../specs/training-plan.md) | 2 AK | Übernommen |
| SRC-001 | §15.4, Z. 976 | Intervalle bevorzugt nach Pace oder RPE | FR-0146 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §16, Z. 980 | Regelbasierte Planung | FR-0147 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §16.1, Z. 984–997 | Wöchentliches Belastungsbudget | FR-0148 | [training-plan.md](../specs/training-plan.md) | 4 AK | Übernommen |
| SRC-001 | §16.1, Z. 999 | Keine pauschale Steigerung als garantiert sicher | FR-0149 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §16.1, Z. 1001 | Wochen mit reduziertem Umfang | FR-0150 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §16.2, Z. 1005–1013 | Verteilung der Einheiten | FR-0151 | [training-plan.md](../specs/training-plan.md) | 3 AK | Übernommen |
| SRC-001 | §16.2, Z. 1015 | Intensive Einheiten nicht ohne Erholung hintereinander | FR-0152 | [training-plan.md](../specs/training-plan.md) | 1 AK | Übernommen |
| SRC-001 | §16.3, Z. 1019–1029 | Rangfolge für die Ableitung der Zielintensität | FR-0153 | [training-plan.md](../specs/training-plan.md) | 4 AK | Übernommen |
| SRC-001 | §16.4, Z. 1033–1051 | Machbarkeit des Ziels beurteilen | FR-0154 | [training-plan.md](../specs/training-plan.md) | 6 AK | Übernommen |
| SRC-001 | §1.1 Nr. 2, Z. 24 | Einfache Trainingsplanung nur mit dem Smartphone | FR-0155 | [training-plan.md](../specs/training-plan.md) | 2 AK | Übernommen |
| SRC-001 | §22, Z. 1252 | Einfache Trainingsplanung nur mit dem Smartphone | FR-0155 | [training-plan.md](../specs/training-plan.md) | 2 AK | Übernommen |
| SRC-001 | §17, Z. 1055 | Fortlaufende Anpassung | FR-0156 | [plan-adaptation.md](../specs/plan-adaptation.md) | 5 AK | Übernommen |
| SRC-001 | §17.1, Z. 1059–1069 | Auslöser einer Neuberechnung | FR-0157 | [plan-adaptation.md](../specs/plan-adaptation.md) | 3 AK, ACC-09 | Übernommen |
| SRC-001 | §25 Nr. 9, Z. 1404 | Auslöser einer Neuberechnung | FR-0157 | [plan-adaptation.md](../specs/plan-adaptation.md) | 3 AK, ACC-09 | Übernommen |
| SRC-001 | §17.2, Z. 1073–1084 | Mindestens wöchentliche Überprüfung | FR-0158 | [plan-adaptation.md](../specs/plan-adaptation.md) | 2 AK | Übernommen |
| SRC-001 | §17.3, Z. 1088–1090 | Kurzfristige Empfehlung vor einer Einheit | FR-0159 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.3, Z. 1092–1096 | Anpassung bei hoher Belastung | FR-0160 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.3, Z. 1098–1102 | Anpassung bei deutlich besserer Leistungsentwicklung | FR-0161 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.3, Z. 1104–1108 | Anpassung bei ausgefallenem Training | FR-0162 | [plan-adaptation.md](../specs/plan-adaptation.md) | 2 AK | Übernommen |
| SRC-001 | §17.3, Z. 1110–1114 | Anpassung bei Beschwerden oder Krankheit | FR-0163 | [plan-adaptation.md](../specs/plan-adaptation.md) | 3 AK | Übernommen |
| SRC-001 | §17.4 Nr. 1, Z. 1118–1120 | Kontinuität vor exaktem Nachholen | FR-0164 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.4 Nr. 2, Z. 1121 | Keine starke Erhöhung nach einer einzelnen Messung | FR-0165 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.4 Nr. 3, Z. 1122 | Konservative Anpassung bei Überlastungssignalen | FR-0166 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.4 Nr. 4, Z. 1123 | Pausen und Wiedereinstiege berücksichtigen | FR-0167 | [plan-adaptation.md](../specs/plan-adaptation.md) | 2 AK | Übernommen |
| SRC-001 | §17.4 Nr. 5, Z. 1124 | Ziel nur mit Zustimmung ändern | FR-0168 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.4 Nr. 6, Z. 1125 | Nutzer behält die Kontrolle über Termine | FR-0169 | [plan-adaptation.md](../specs/plan-adaptation.md) | 1 AK | Übernommen |
| SRC-001 | §17.4 Nr. 7, Z. 1126 | Größere Änderungen begründen | FR-0170 | [plan-adaptation.md](../specs/plan-adaptation.md) | 2 AK, ACC-10 | Übernommen |
| SRC-001 | §25 Nr. 10, Z. 1405 | Größere Änderungen begründen | FR-0170 | [plan-adaptation.md](../specs/plan-adaptation.md) | 2 AK, ACC-10 | Übernommen |
| SRC-001 | §18, Z. 1130 | Kalender mit geplanten und absolvierten Einheiten | FR-0171 | [calendar.md](../specs/calendar.md) | 1 AK | Übernommen |
| SRC-001 | §18.1, Z. 1134–1137 | Ansichten und Kennzeichnungen | FR-0172 | [calendar.md](../specs/calendar.md) | 2 AK | Übernommen |
| SRC-001 | §18.1, Z. 1138–1140 | Training verschieben, ersetzen, Ruhetage festlegen | FR-0173 | [calendar.md](../specs/calendar.md) | 2 AK | Übernommen |
| SRC-001 | §18.1, Z. 1141–1142 | Trainingszeiten und Erinnerungen | FR-0174 | [calendar.md](../specs/calendar.md) | 1 AK | Übernommen |
| SRC-001 | §18.1, Z. 1144–1148 | Termine empfehlen | FR-0175 | [calendar.md](../specs/calendar.md) | 1 AK | Übernommen |
| SRC-001 | §18.1, Z. 1150 | Bestätigung vor Kalenderänderungen | FR-0176 | [calendar.md](../specs/calendar.md) | 2 AK | Übernommen |
| SRC-001 | §18.2, Z. 1154–1159 | Prüfung beim Verschieben | FR-0177 | [calendar.md](../specs/calendar.md) | 1 AK | Übernommen |
| SRC-001 | §18.2, Z. 1161 | Alternativen bei Konflikten | FR-0178 | [calendar.md](../specs/calendar.md) | 1 AK | Übernommen |
| SRC-001 | §19, Z. 1165 | Bedeutung erklären | FR-0179 | [explanations.md](../specs/explanations.md) | 1 AK | Übernommen |
| SRC-001 | §19, Z. 1167–1183 | Erklärungsarten | FR-0180 | [explanations.md](../specs/explanations.md) | 1 AK | Übernommen |
| SRC-001 | §19, Z. 1185 | Erklärungen beruhen auf tatsächlichen Daten | FR-0181 | [explanations.md](../specs/explanations.md) | 2 AK | Übernommen |
| SRC-001 | §20.1, Z. 1191–1197 | Dateiexport als GPX, TCX und FIT | FR-0182 | [export-sync.md](../specs/export-sync.md) | 2 AK, ACC-13 | Übernommen |
| SRC-001 | §25 Nr. 13, Z. 1408 | Dateiexport als GPX, TCX und FIT | FR-0182 | [export-sync.md](../specs/export-sync.md) | 2 AK, ACC-13 | Übernommen |
| SRC-001 | §20.1, Z. 1199–1205 | Exportinhalte | FR-0183 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §20.1, Z. 1207 | Zusatzmetriken separat exportierbar | FR-0184 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §20.2, Z. 1211–1215 | Strava-Konto einmalig verknüpfen | FR-0185 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §20.2, Z. 1216 | Manueller Upload einzelner Läufe | FR-0186 | [export-sync.md](../specs/export-sync.md) | 1 AK | Übernommen |
| SRC-001 | §20.2, Z. 1217 | Optionale automatische Synchronisierung | FR-0187 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §20.2, Z. 1218 | Upload-Status anzeigen | FR-0188 | [export-sync.md](../specs/export-sync.md) | 1 AK | Übernommen |
| SRC-001 | §20.2, Z. 1219 | Uploadfehler behandeln | FR-0189 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §20.2, Z. 1220 | Doppelte Uploads vermeiden | FR-0190 | [export-sync.md](../specs/export-sync.md) | 1 AK | Übernommen |
| SRC-001 | §20.2, Z. 1221 | Verbindung trennen | FR-0191 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §20.3, Z. 1229–1231 | Gesamtexport der Nutzerdaten | FR-0192 | [export-sync.md](../specs/export-sync.md) | 3 AK, ACC-15 | Übernommen |
| SRC-001 | §25 Nr. 15, Z. 1410 | Gesamtexport der Nutzerdaten | FR-0192 | [export-sync.md](../specs/export-sync.md) | 3 AK, ACC-15 | Übernommen |
| SRC-001 | §6.1, Z. 234 | Laufende Sicherung und Wiederaufnahme | FR-0193 | [run-recording.md](../specs/run-recording.md) | 4 AK | Übernommen |
| SRC-003 | (OQ-0021, OQ-0061) | Laufende Sicherung und Wiederaufnahme | FR-0193 | [run-recording.md](../specs/run-recording.md) | 4 AK | Übernommen |
| SRC-001 | §6.1, Z. 234 | Verhalten bei GPS-Verlust | FR-0194 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-003 | (OQ-0021) | Verhalten bei GPS-Verlust | FR-0194 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-003 | (OQ-0021) | Start nur mit Standortberechtigung | FR-0195 | [run-recording.md](../specs/run-recording.md) | 1 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-03) | Laufbandmodus | FR-0196 | [run-recording.md](../specs/run-recording.md) | 7 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-03) | Belastungsprofil wählen | FR-0197 | [training-load.md](../specs/training-load.md) | 7 AK | Übernommen |
| SRC-003 | (OQ-0032) | Reimport des Gesamtexports | FR-0198 | [export-sync.md](../specs/export-sync.md) | 4 AK | Übernommen |
| SRC-001 | §17.1, Z. 1063 | Training manuell nachtragen | FR-0199 | [training-load.md](../specs/training-load.md) | 3 AK | Übernommen |
| SRC-003 | (OQ-0022) | Training manuell nachtragen | FR-0199 | [training-load.md](../specs/training-load.md) | 3 AK | Übernommen |
| SRC-001 | §3.4, Z. 113 | Import über Health Connect | FR-0200 | [health-import.md](../specs/health-import.md) | 3 AK | Übernommen |
| SRC-003 | (OQ-0033) | Import über Health Connect | FR-0200 | [health-import.md](../specs/health-import.md) | 3 AK | Übernommen |
| SRC-001 | §20.1, Z. 1191 | Export teilen | FR-0201 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-003 | (OQ-0049) | Export teilen | FR-0201 | [export-sync.md](../specs/export-sync.md) | 2 AK | Übernommen |
| SRC-001 | §4.1, Z. 146 | Schrittfrequenz aus dem Smartphone | FR-0202 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-003 | (OQ-0052) | Schrittfrequenz aus dem Smartphone | FR-0202 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-001 | §17.3, Z. 1110–1114 | Warnsignal melden und aufheben | FR-0203 | [plan-adaptation.md](../specs/plan-adaptation.md) | 3 AK | Übernommen |
| SRC-003 | (OQ-0055) | Warnsignal melden und aufheben | FR-0203 | [plan-adaptation.md](../specs/plan-adaptation.md) | 3 AK | Übernommen |
| SRC-001 | §4.3, Z. 168–180 | Karte der Route | FR-0204 | [run-recording.md](../specs/run-recording.md) | 6 AK | Übernommen |
| SRC-001 | §5.1, Z. 197 | Karte der Route | FR-0204 | [run-recording.md](../specs/run-recording.md) | 6 AK | Übernommen |
| SRC-003 | (OQ-0074) | Karte der Route | FR-0204 | [run-recording.md](../specs/run-recording.md) | 6 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Erscheinungsbild nach dem Screen-Design | FR-0205 | [app-design.md](../specs/app-design.md) | 3 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Name, Icon und Systemsymbole | FR-0206 | [app-design.md](../specs/app-design.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Willkommensbildschirm | FR-0207 | [app-design.md](../specs/app-design.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Navigation | FR-0208 | [app-design.md](../specs/app-design.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Startseite „Heute“ | FR-0209 | [app-design.md](../specs/app-design.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Lauf vorbereiten | FR-0210 | [run-recording.md](../specs/run-recording.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Kilometerwerte in der Detailansicht | FR-0211 | [history-statistics.md](../specs/history-statistics.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-08, OQ-0075) | Zeitraum in der Historie | FR-0212 | [history-statistics.md](../specs/history-statistics.md) | 1 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-09) | RR-Intervalle als Rohdaten speichern | FR-0213 | [sensors.md](../specs/sensors.md) | 4 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-09) | Ruhepuls mit der Handykamera messen | FR-0214 | [profile.md](../specs/profile.md) | 10 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-09) | Morgenmessung mit der Handykamera | FR-0215 | [readiness.md](../specs/readiness.md) | 8 AK | Übernommen |
| SRC-001 | §23, Z. 1270–1272 | Algorithmen versionierbar und nachvollziehbar | NFR-0001 | [non-functional.md](../quality/non-functional.md) | 1 AK | Übernommen |
| SRC-001 | §23.1, Z. 1276–1305 | Einordnung in drei Verfahrenskategorien | NFR-0002 | [non-functional.md](../quality/non-functional.md) | 1 AK | Übernommen |
| SRC-001 | §23.1, Z. 1307 | Heuristiken nicht als validiert darstellen | NFR-0003 | [non-functional.md](../quality/non-functional.md) | 1 AK | Übernommen |
| SRC-001 | §8.3, Z. 409 | Validierung vor Genauigkeitsaussagen | NFR-0004 | [non-functional.md](../quality/non-functional.md) | 2 AK | Übernommen |
| SRC-001 | §11.2, Z. 695 | Validierung vor Genauigkeitsaussagen | NFR-0004 | [non-functional.md](../quality/non-functional.md) | 2 AK | Übernommen |
| SRC-001 | §12.4, Z. 791 | Validierung vor Genauigkeitsaussagen | NFR-0004 | [non-functional.md](../quality/non-functional.md) | 2 AK | Übernommen |
| SRC-003 | (Maintainer 2026-11-03) | Austauschbare Algorithmen | NFR-0005 | [non-functional.md](../quality/non-functional.md) | 3 AK | Übernommen |
| SRC-003 | (OQ-0035) | Sprachen und Einheiten | NFR-0006 | [non-functional.md](../quality/non-functional.md) | 3 AK | Übernommen |
| SRC-001 | §21, Z. 1235–1237 | Gesundheitsdaten nur mit ausdrücklicher Zustimmung | SEC-0001 | [security.md](../quality/security.md) | 2 AK | Übernommen |
| SRC-001 | §21, Z. 1238 | Datenquellen getrennt freigeben | SEC-0002 | [security.md](../quality/security.md) | 1 AK | Übernommen |
| SRC-001 | §21, Z. 1239 | Externe Synchronisierung ist optional | SEC-0003 | [security.md](../quality/security.md) | 1 AK | Übernommen |
| SRC-001 | §21, Z. 1240 | Export und Löschung der eigenen Daten | SEC-0004 | [security.md](../quality/security.md) | 3 AK, ACC-15 | Übernommen |
| SRC-001 | §25 Nr. 15, Z. 1410 | Export und Löschung der eigenen Daten | SEC-0004 | [security.md](../quality/security.md) | 3 AK, ACC-15 | Übernommen |
| SRC-001 | §21, Z. 1241 | Datenherkunft erkennbar | SEC-0005 | [security.md](../quality/security.md) | 1 AK | Übernommen |
| SRC-001 | §21, Z. 1242 | Berechnungen ohne zwingende externe Übertragung | SEC-0006 | [security.md](../quality/security.md) | 1 AK | Übernommen |
| SRC-001 | §21, Z. 1243 | Berechtigungen widerrufen | SEC-0007 | [security.md](../quality/security.md) | 2 AK | Übernommen |
| SRC-001 | §21, Z. 1244 | Keine Übertragung an Dritte ohne Einwilligung | SEC-0008 | [security.md](../quality/security.md) | 1 AK | Übernommen |
| SRC-001 | §21, Z. 1235 | Verschlüsselte Speicherung | SEC-0009 | [security.md](../quality/security.md) | 3 AK | Übernommen |
| SRC-003 | (OQ-0024, OQ-0062) | Verschlüsselte Speicherung | SEC-0009 | [security.md](../quality/security.md) | 3 AK | Übernommen |
| SRC-003 | (OQ-0024) | System-Backups immer aus | SEC-0010 | [security.md](../quality/security.md) | 1 AK | Übernommen |
| SRC-003 | (OQ-0050) | Verschlüsseltes Archiv | SEC-0011 | [security.md](../quality/security.md) | 2 AK | Übernommen |
| SRC-001 | Kopf, Z. 4 | Zielplattformen | CON-0001 | [product.md](../product.md) | TBD | Übernommen |
| SRC-001 | Kopf, Z. 6–7 | Technik ist nicht Gegenstand der Quelle | CON-0002 | [product.md](../product.md) | TBD | Übernommen |
| SRC-001 | Schluss, Z. 1444 | Technik ist nicht Gegenstand der Quelle | CON-0002 | [product.md](../product.md) | TBD | Übernommen |
| SRC-001 | §1, Z. 17 | Geräteunabhängigkeit | CON-0003 | [product.md](../product.md) | 1 AK | Übernommen |
| SRC-001 | §1.1 Nr. 1, Z. 23 | Geräteunabhängigkeit | CON-0003 | [product.md](../product.md) | 1 AK | Übernommen |
| SRC-001 | §1.1 Nr. 2, Z. 24 | Funktionalität ohne Wearable | CON-0004 | [product.md](../product.md) | 1 AK, ACC-01 | Übernommen |
| SRC-001 | §1.1 Nr. 3, Z. 25 | Transparente Berechnungen | CON-0005 | [product.md](../product.md) | 1 AK | Übernommen |
| SRC-001 | §1, Z. 19 | Adaptive Trainingsplanung | CON-0006 | [product.md](../product.md) | TBD | Übernommen |
| SRC-001 | §1.1 Nr. 4, Z. 26 | Adaptive Trainingsplanung | CON-0006 | [product.md](../product.md) | TBD | Übernommen |
| SRC-001 | §1.1 Nr. 5, Z. 27 | Optionale Gesundheitsdaten | CON-0007 | [product.md](../product.md) | 1 AK | Übernommen |
| SRC-001 | §1.1 Nr. 6, Z. 28 | Datenhoheit | CON-0008 | [product.md](../product.md) | 1 AK | Übernommen |
| SRC-001 | §1.1 Nr. 7, Z. 29 | Kennzeichnung von Unsicherheit | CON-0009 | [product.md](../product.md) | 1 AK | Übernommen |
| SRC-001 | §20.2, Z. 1223–1225 | Unabhängigkeit von externen Plattformen | CON-0010 | [product.md](../product.md) | 1 AK, ACC-14 | Übernommen |
| SRC-001 | §25 Nr. 14, Z. 1409 | Unabhängigkeit von externen Plattformen | CON-0010 | [product.md](../product.md) | 1 AK, ACC-14 | Übernommen |
<!-- END TRACE -->

## Teil B: Weitere Aussagen

| Quelle | Fundstelle | Aussage / Kurzfassung | Ergebnis | Dokument | Status |
|---|---|---|---|---|---|
| SRC-001 | Kopf, Z. 1, 3, 5 | Titel, Version, Produktbereich | SRC-001 | [source-inventory.md](source-inventory.md), [product.md](../product.md) | Übernommen |
| SRC-001 | §1, Z. 13–15 | Produktvision | Abschnitt „Vision“ | [product.md](../product.md) | Übernommen |
| SRC-001 | §3, Z. 63 | Einleitung Quellen für Herzfrequenz- und Gesundheitsdaten | FEAT-002, FEAT-003 | [sensors.md](../specs/sensors.md) | Übernommen |
| SRC-001 | §7.1, Z. 277 | Einleitung Herzfrequenzreserve | FR-0060 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | Übernommen |
| SRC-001 | §24, Z. 1332–1390 | Empfohlener Funktionsumfang je Phase | DEC-0012 | [product.md](../product.md) | Übernommen |
| SRC-001 | §25, Z. 1394–1410 | Funktionale Abnahmekriterien | ACC-01 bis ACC-15 | [testing.md](../quality/testing.md) | Übernommen |
| SRC-001 | §26, Z. 1414–1425 | Offene fachliche Entscheidungen | OQ-0001 bis OQ-0010 | [open-questions.md](open-questions.md) | Ungeklärt |
| SRC-001 | §27, Z. 1429–1438 | Wissenschaftliche und fachliche Referenzen | Referenzliste | [references.md](../references.md) | Übernommen |
| SRC-001 | §8.3, Z. 377–379 | Formel für r, wiederholt aus §7.1 | FR-0060 | [heart-rate-zones.md](../specs/heart-rate-zones.md) | Duplikat |
| SRC-001 | §21, Z. 1239 | Externe Synchronisierung optional, deckt sich mit §20.2 | CON-0010, SEC-0003 | [security.md](../quality/security.md) | Duplikat |
| SRC-001 | §21, Z. 1240 | Export und Löschung, deckt sich mit §25 Nr. 15 | SEC-0004 | [security.md](../quality/security.md) | Duplikat |
| SRC-001 | §22, Z. 1252 | Einfache Planung nur mit GPS, deckt sich mit §1.1 Nr. 2 | FR-0155 | [training-plan.md](../specs/training-plan.md) | Duplikat |
| SRC-001 | §23.3, Z. 1328 | Gemessen oder geschätzt, deckt sich mit §22 | FR-0057, FR-0059 | [data-quality.md](../specs/data-quality.md) | Duplikat |
| SRC-001 | Schluss, Z. 1442 | Endmarke des Dokuments | — | — | Nicht übernommen |
