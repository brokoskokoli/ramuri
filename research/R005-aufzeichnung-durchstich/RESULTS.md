# R005 – Ergebnis

## Kurzfassung
ADR-0005 Punkt 3 trägt **im Emulator**: Ein Engine im Application-Objekt mit dünnem Foreground-Service schrieb bei gesperrtem Bildschirm und `force-idle` ohne Lücke über 5 s, wenn das System wach blieb (API 36 und 31; auf API 36 auch 60 Minuten am Stück). Ohne eigenen Wake Lock endete die Aufzeichnung in allen 5 Läufen, sobald das System nach Lösen der Emulator-Sperre `emulator_wake_lock` in den Suspend ging; das entscheidet die Wake-Lock-Frage nicht, weil `geo fix` nicht weckt. Mit `synchronous = FULL` ging in 41 harten Kills (`sigkill`, `adb emu kill`) vor dem ersten Checkpoint und in 14 `sigkill`-Läufen danach keine bestätigte Zeile verloren; die Kontrolle `NORMAL` verliert in 25 von 27 bzw. 6 von 6 Läufen. Getrennt davon 26 Prozess-Kills ohne Verlust, die für `FULL` nichts belegen. **Die Checkpoint-Serie hebt die frühere Einschränkung „nur vor dem ersten Checkpoint“ auf, die Empfehlung bleibt gleich;** sie lief mit 10 statt 1000 Frames je Checkpoint auf einer Hauptdatei von 2 Seiten, ein Kill mitten im Checkpoint bleibt offen. **Abweichung vom Auftrag:** `adb emu kill` ist nicht je Transaktionsgröße gemessen (nur tx 1, API 36, `FULL` n = 2), `sigkill` ersetzt es; Begründung unter „Kill“. Das WAL war auf beiden API-Stufen verschlüsselt, der Lizenzbaum enthält keinen Unverträglichkeitsfund (ohne Rechtsprüfung). Das ist kein Beleg für echte Geräte: Akku, Herstellermodi, echtes Schlafverhalten, Stromausfall und FR-0034 im Feld sind ungeprüft. **Nicht beantwortet** ist der Schrittsensor unter Typ `location`: Der Sensor fehlt auf beiden Images.

**Empfehlung, alles vorbehaltlich Feldtest:**
- **Host:** `own` (ADR-0005 Punkt 3). Die Lückenmessung unterscheidet `own` und `ffgt` nicht; den Ausschlag geben die Architektur (ein Engine) und der ungewollte Neustart von `ffgt` nach Kill.
- **Transaktionsgröße:** eine Zeile je Transaktion mit `FULL`. Kein gemessener Verlust bestätigter Zeilen, vor und nach dem ersten Checkpoint (Grenzen unter „Kill nach dem ersten Checkpoint“), Commit p50 unter 7 ms bei 1 Punkt je Sekunde. Differenz zwischen Empfang und DB 0 an den getroffenen Zeitpunkten; rechnerisch bleibt bis zu 1 Zeile in Arbeit, siehe „Kill“. Fallen im Feld Energie oder Schreiblast auf, ist tx 5 der nächste Schritt (rechnerisch bis 4 ungesicherte Zeilen).
- **Wake Lock (Entscheidung des Maintainers, nicht durch Messung belegt):** im Dienst für die Dauer des Laufs einen Partial Wake Lock halten. Das ist eine bewusste Vorsichtsentscheidung: Verlorene Laufdaten kommen nicht wieder, Mehrverbrauch und Android Vitals werden in Kauf genommen. Die Messung entscheidet die Frage nicht, Googles Dokumentation spricht eher dagegen (siehe „Wake Lock“). Ausstieg: Zeigt der Feldtest den Lock als überflüssig, entfällt er.

### Antwort je Kriterium
| Kriterium | Antwort im Emulator | Belastbarkeit |
| --- | --- | --- |
| Keine Datenlücke bei Sperre und Idle | **Erfüllt, wenn das System wach ist** (kein Abstand über 5 s, Tabelle 1 und 2 mit Wake Lock). Nach gelöster Emulator-Sperre endet die Aufzeichnung ohne Wake Lock, **das sagt aber nichts über Geräte**, weil `geo fix` nicht weckt: Ohne-Lock-Betrieb ist offen. Der Lock ist Entscheidung des Maintainers, keine Messfolge. Die Abstände bis 2,01 s auf API 36 zählen nicht dagegen, siehe „Abstände auf API 36“ | kleine n je Zelle, Langlauf ein Einzellauf; Suspend nur nach Eingriff |
| Gesicherte Daten überstehen den Kill | **Erfüllt, außer ungeprüft: Kill mitten im Checkpoint.** `FULL`: 41 harte Kills vor dem ersten Checkpoint und 14 `sigkill` danach (Tabelle 5, 8) ohne Verlust, keine Löcher, Integrität immer ok; `NORMAL` verliert in 31 von 33; `proc` (26 Läufe) getrennt und ohne Beweiskraft für `FULL`. `sigkill` ersetzt `adb emu kill` je Transaktionsgröße (Abweichung, Begründung unter „Kill“). `sigkill` ist kein Stromausfall | einseitige obere 95-%-Grenze für den Anteil betroffener Läufe, empfohlene Zelle (`FULL`, tx 1, hart): API 36 `own` 22 % (n = 12), mit `ffgt` 18 % (n = 15), API 31 `own` 45 % (n = 5), `emu` allein 78 % (n = 2). Nach dem Checkpoint je API 35 % (n = 7), zusammen 19 % (n = 14), nur 10 Frames je Checkpoint und 2 Seiten Hauptdatei |
| WAL nachweislich verschlüsselt | **Erfüllt:** kein Marker, kein Double, kein Header, χ² wie Zufall, Positivkontrolle trifft; am Rechner und auf API 31 und 36 | hoch; Laufzeitprüfung am Rechner und je 1 Lauf je API |
| Abhängigkeiten GPL-3.0-verträglich | **Kein Hindernis gefunden.** Permissive Lizenzen, dazu MPL-2.0 (`bluez`, `dbus`), die nach MPL 3.3 mit der GPL verbunden werden darf. Kein `play-services` | Einschätzung ohne Rechtsprüfung; Prüfstand ist der Prototyp, nicht `app/` |

## Lauf
- **Datum:** 2026-11-04. Phase A 13:30 bis 14:23, Proben natural bis 15:27, Matrix 15:29 bis 21:01, Langlauf 21:03 bis 22:05, Wiederholungen und Probe 22:09 bis 22:41, zusammen etwa 8 h 40 min Lauf. Wiederholbarkeitsprobe der Skripte 22:52. Nachbesserung nach Review Runde 1 am selben Abend ohne neue Messung, alle Zahlen aus den vorhandenen Rohdaten. Checkpoint-Serie am 2026-11-05, 08:01 bis 08:42, 41 min, ohne Änderung an Harness oder Prototyp.
- **Commits:** Prototyp und APK unverändert seit `54e21e8`. Harness: Matrix `31e85c8`, Langlauf `3103df7`, Wiederholungen `d0aa551`, Checkpoint-Serie `db84450`. Auswertung und Skripte: dieser Stand, Verlauf per `git log`. Der Harness danach (`rm_runs` vor jedem Lauf, `--autock`, `--seed`) hat von diesen Läufen nur die Checkpoint-Serie erzeugt.
- **Kommandos:** `./init.sh`, `./run.sh phase-a`, `./run.sh matrix`, `./run.sh long`, `./run.sh rerun`, `./run.sh vorlaeufe`, `./run.sh wal-host`, `./run.sh licenses`, Auswertung `./run.sh report`. `vorlaeufe` enthält die anfangs von Hand bzw. über Hilfsskripte gestarteten Läufe mit den Befehlen laut `meta.json`: API 31 `_smoke` (`own`, `none`), `_pausectl`, API 36 `_nat`, `_forced`. Die Bedingung `-show-kernel` steht unter „Bewertung und Zweifel“. Dazu `./run.sh checkpoint`.
- **Zahlen nachrechnen:** `./run.sh report` schreibt nach `$RESEARCH_DATA/work/R005/report/`: `tables.md` (Tabellen 1 bis 8), `analyze-*.out` (Einzelläufe, WAL im Emulator, Schreibkosten), `longrun.out`, `abstand.out`. WAL am Rechner: `wal-host/run3.log`. Dezimaltrenner hier Komma, in den Ausgaben Punkt. Alle Tabellen unten habe ich aus diesen Ausgaben übernommen und die Stichproben aus den Rohdaten nachgerechnet.
- **Rechner:** Apple M3 Pro, 11 Kerne, 18 GB, macOS 27.2. Last im Langlauf im Mittel 3,8, Spitze 19,3. Daneben lief ein fremder Emulator einer anderen Sitzung (`emulator-5610`), etwa 22 % eines Kerns.
- **Emulator:** 36.6.11.0, AVD Pixel 6, 4 Kerne, 3 GB, Images `google_apis;arm64-v8a` Revision 7 (API 36, `16/BE2A.250530.026.F3`) und 11 (API 31). Flutter 3.47.7, Dart 3.13.5, AGP 9.1.0, Gradle 9.3.1, JBR 21, Profil-Build. sqlite3mc 2.6.1, SQLite 3.54.0, Verfahren chacha20. **Grenze der Wiederholbarkeit:** `init.sh` holt die jeweils aktuelle Image-Revision und stellt 7 und 11 nicht fest ein; eine Wiederholung kann auf einem anderen Image laufen. Der Kill `proc` lief auf API 36 in Phase A und Matrix per `run-as`, der heutige Harness tötet immer per root; beide belegen die Wirkung über den PID, eine Wiederholung misst an dieser Stelle aber anders.

## Ergebnisse

Alle Tabellen getrennt nach API. Spannen sind Minimum bis Maximum über die Läufe einer Zelle. „Abstand“ ist der Abstand aufeinanderfolgender in der DB gesicherter Punkte an `trecv`, mit Rändern zur Phase. **Lücke heißt Abstand über 5 s**, eine Messdefinition, kein Produktgrenzwert. Zeilen enthalten nur die Idle-Phase.

### Lücken: Standardbedingung (System bleibt wach)
Die Emulator-Sperre `emulator_wake_lock` bleibt, also kein Suspend (Spalte Suspend-Erfolge 0); das misst Host, Doze und Einfrieren.

Tabelle 1.

| API | Host | Läufe | Idle-s | Zeilen | Rate/s | Abdeckung | p99-Abstand-s | max-Abstand-s | max-Positionswechsel-s | >2s | >5s | >30s | Herzschlag-max-s | Commit-p50-ms | Commit-p99-ms | Suspend-Erfolge |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 36 | own | 3 | 1344 | 1254 | 0,932 bis 0,936 | 0,93 bis 0,94 | 1,82 bis 1,94 | 2,0 | 3,0 | 4 | 0 | 0 | 1,0 | 3,3 bis 6,3 | 10,4 | 0 (gelesen in 2 von 3) |
| 36 | ffgt | 3 | 1342 | 1266 | 0,934 bis 0,944 | 0,92 bis 0,94 | 1,81 bis 1,90 | 2,0 | 2,0 | 0 | 0 | 0 | 1,0 | 4,8 bis 6,4 | 12,5 | 0 (gelesen in 2 von 3) |
| 31 | own | 2 | 731 | 731 | 0,999 bis 1,000 | 0,99 bis 1,00 | 1,04 bis 1,06 | 1,1 | 2,0 | 0 | 0 | 0 | 1,0 | 3,8 bis 4,0 | 10,4 | 0 (gelesen in 1 von 2) |
| 31 | ffgt | 1 | 609 | 609 | 1,001 | 0,99 | 1,03 | 1,0 | 2,0 | 0 | 0 | 0 | 1,0 | 3,6 | 7,6 | 0 (gelesen in 1 von 1) |

### Lücken: Bedingung natural (Eingriff, Suspend möglich)
`emulator_wake_lock` per root gelöst, Wake-Lock-Zählung bleibt in Kraft, kein `echo mem`. Läufe ohne Wake Lock enden mit SIGKILL und Neustart, die Zeilen stammen dann aus der DB, der Schlaf aus dem Kernel-Log (`kernel-pm.txt`). Spalte Suspend-Erfolge entfällt dort, weil der Kernelzähler den Neustart nicht übersteht.

Tabelle 2.

| API | Host | Wake-Lock | Läufe | Idle-s | Zeilen | Rate/s | Abdeckung | max-Abstand-s | max-Positionswechsel-s | Läufe-mit->5s | Summe->5s | Suspend-Erfolge | suspend-entry-je-Lauf |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 36 | own | ja | 4 | 4081 | 3867 | 0,939 bis 0,976 | 0,94 bis 0,97 | 2,0 | 2,0 | 0/4 | 0 | 0 | – |
| 36 | own | nein | 2 | 352 | 18 | 0,045 bis 0,057 | 0,05 bis 0,06 | 150,2 | 1,0 | 2/2 | 4 | – | 9 |
| 36 | ffgt | ja | 2 | 352 | 335 | 0,939 bis 0,967 | 0,93 bis 0,97 | 2,0 | 2,0 | 0/2 | 0 | 0 | – |
| 36 | ffgt | nein | 2 | 352 | 17 | 0,046 bis 0,051 | 0,05 bis 0,05 | 138,7 | 1,0 | 2/2 | 4 | – | 8 bis 9 |
| 31 | own | ja | 1 | 176 | 175 | 0,995 | 0,98 | 1,0 | 2,0 | 0/1 | 0 | 0 | – |
| 31 | own | nein | 1 | 176 | 58 | 0,330 | 0,32 | 82,1 | 36,8 | 1/1 | 2 | – | 8 |
| 31 | ffgt | ja | 1 | 176 | 176 | 1,001 | 0,99 | 1,1 | 2,0 | 0/1 | 0 | 0 | – |

Die Zeilen ohne Wake Lock stammen fast nur aus der Zeit bis zum ersten Schlaf; nach dem ersten Aufwachen kamen in den angesehenen Läufen nur noch 1 bis 8 Zeilen (`a31_own_w0`: 1 Zeile nach 36,8 s, dann 82,1 s bis Phasenende). API 31 schlief im Einzellauf später ein als API 36, 58 gegen 8 bis 10 Zeilen; warum, habe ich nicht geklärt. Im Kernel-Log steht je Lauf eine `suspend entry` mehr als `suspend exit`: Aus dem letzten Suspend kam der Emulator nie zurück.

### Kontrollen (Einzelläufe)
Tabelle 3.

| Lauf | Zeilen | Idle-s | Abdeckung | max-Abstand-s | max-Positionswechsel-s | >5s | Herzschlag-max-s | Suspend-Erfolge |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| a31_none_w0_i1_120s_smoke_r0 | 0 | 122 | 0,0 | 121,8 | None | 1 | 1,0 | None |
| a31_none_w0_i1_300s_r0 | 0 | 305 | 0,0 | 304,7 | None | 1 | 1,0 | 0 |
| a31_own_w0_i1_120s_forced_r0 | 28 | 116 | 0,2273 | 88,3 | 1,0 | 1 | 21,6 | 1 |
| a31_own_w0_i1_120s_pausectl_r0 | 121 | 122 | 1,0 | 1,4 | 31,5 | 0 | 5,4 | None |
| a31_own_w0_i1_120s_stopctl2_r0 | 121 | 122 | 1,0 | 30,5 | 30,5 | 1 | 30,5 | 0 |
| a36_none_w0_i1_120s_ctl_r0 | 0 | 122 | 0,0 | 122,0 | None | 1 | 57,0 | None |
| a36_none_w0_i1_600s_r0 | 0 | 610 | 0,0 | 610,3 | None | 1 | 544,7 | 0 |
| a36_own_w0_i1_120s_forced_r0 | 62 | 116 | 0,5 | 52,4 | 52,4 | 1 | 90,2* | 1 |
| a36_own_w0_i1_120s_pausectl_r0 | 118 | 122 | 0,9765 | 2,0 | 31,1 | 0 | 1,0 | None |
| a36_own_w0_i1_120s_stopctl2_r0 | 114 | 122 | 0,9138 | 30,2 | 30,2 | 1 | 30,3 | 0 |

\* Rand durch den Abbruch von logcat beim Suspend (76 von 115 Zeilen im Log), kein gemessener Herzschlag-Abstand.

- **Negativkontrolle `none`** (ohne Dienst, kein Standort): 0 Zeilen in der Idle-Phase auf beiden API-Stufen, also ist „keine Lücke“ nicht wertlos. Das letzte `R005RCV` liegt 0,0 bis 0,6 s nach `locked_start`, also vor Sperre und `force-idle`: Der Standort endet mit dem Verlassen des Vordergrunds. Die Kontrolle zeigt damit, dass der Dienst den Standort im Hintergrund hält und die Messung einen Ausfall sieht. **Sie prüft nicht Sperre oder Doze:** Kein Lauf zeigt eine eigene Wirkung von `force-idle` auf den Standort, „kein Abstand“ heißt also nicht „Doze hätte gewirkt und wurde abgewehrt“. Der Zustand `IDLE` selbst ist belegt. Auf API 36 enden die Herzschläge etwa 65 s nach Beginn der Idle-Phase, der Prozess bleibt bestehen (vermutlich App-Freezer, das Log zeigt `Unable to freeze binder`, nicht direkt belegt). Auf API 31 laufen sie weiter.
- **Pause 30 s:** Der reine Abstand bleibt bei 2,0 bzw. 1,4 s, weil der Emulator die letzte Position wiederholt. Gefunden wird sie über den Positionswechsel (31,1 und 31,5 s). Deshalb gibt es beide Spalten. Der API-31-Lauf ist am Ende durch ein `adb root` von mir verunreinigt (Herzschlag 5,4 s).
- **SIGSTOP 30 s:** Abstand und Herzschlag finden es (30,2 und 30,5 s). Danach kommen 26 bzw. 29 Punkte als Stoß in 0 s an, sie waren im Binder-Puffer. Die Abdeckung bleibt deshalb hoch (0,91 und 1,0): Sie ist blind für Einfrieren, der Abstand nicht. Darum zählt der Abstand als Kriterium.
- **Erzwungener Suspend** (`echo mem`, kein Beleg zum Wake Lock): API 36 Standorte kommen nach 52,4 s zurück. API 31 nach 88 s nicht mehr, und ein nächster Lauf in derselben Boot-Sitzung lieferte 0 Zeilen (`invalid/a31-nat-w0-nach-forced`, n=1, nach frischem Boot normal). Ursache offen.

### Abstände auf API 36: Ursache und Bewertung
Auf API 36 sind in der Idle-Phase etwa 7 bis 13 % der Abstände 1,1 bis 2,01 s, in der Referenz 6 bis 24 % (`abstand.out`), die Abdeckung liegt bei 0,92 bis 0,97, auf API 31 bei 0,98 bis 1,0. Das trat in Referenz und Idle auf, bei allen Hosts. **Die Probe bestätigt die Vermutung GNSS-HAL:**

Tabelle 4.

| Einspeisung | HAL-Eingang(311) | HAL-verworfen(321) | HAL-weiter(333) | DB-Zeilen | Idle-Zeilen | Anteil->1,1s | max-s | lange-Abstände-mit-Verwerfung | kurze-Abstände-mit-Verwerfung | Median-Abstand-Verworfener-zum-letzten-Fix-s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ohne Einspeisung im Idle | 404 | 122 | 282 | 282 | 227 | 6,6 % | 2,01 | 15/15 | 0/211 | 0,999 |
| alle 10 s | 338 | 64 | 274 | 274 | 217 | 13,0 % | 2,01 | 28/28 | 22/188 | 0,996 |
| jede Sekunde | 615 | 331 | 284 | 284 | 228 | 11,9 % | 1,98 | 27/27 | 196/200 | 0,420 |

Die Zeilennummern beziehen sich auf die Debug-Ausgaben in `hals/gnss/Gnss.cpp` [1]: Zeile 311 Eingang, 321 Verwerfen durch `now < mLastFix + mMinInterval`, 333 Weitergabe. Das Image passt: `android.hardware.gnss-service.ranchu`, das Log enthält genau diese Nummern.

- **Keine Verluste hinter dem HAL:** Jeder weitergegebene Fix landet in der DB, je Lauf 282=282, 274=274, 284=284. Tragend ist die Bilanz: Eingang = verworfen + weiter (404 = 122 + 282, 338 = 64 + 274, 615 = 331 + 284), und weiter = DB-Zeilen.
- **Verwerfung und langer Abstand:** Jeder lange Abstand enthält eine Verwerfung (70 von 70), das allein unterscheidet bei 1 s Einspeisung aber nichts, denn dort enthalten auch 196 von 200 kurzen Abständen eine. Trennscharf sind ohne Einspeisung 15 von 15 gegen 0 von 211 und bei 10 s 28 von 28 gegen 22 von 188.
- **Ohne Einspeisung ist die Verteilung zweigipflig**, nur 1,0 s (211) und 2,0 s (15). Der Takt des Wiederholers im Emulator trifft den Filter gelegentlich knapp davor (verworfen 0,995 bis 1,000 s nach dem letzten Fix), dann fehlt ein Takt. Die stetige Verteilung bei 1 s Einspeisung erklärt vermutlich das Zusammenspiel zweier unabhängiger Takte, `geo fix` plus Wiederholer; das ist nicht geprüft.
- **API 31 hat diesen Filter nicht:** Der API-12-HAL ignoriert das Intervall (`(void)minIntervalMs` [2]), passend dazu 2,3 % der Abstände unter 0,97 s, auf API 36 keiner.

**Bewertung gegen das Kriterium: zählt nicht dagegen.** Die Abstände liegen unter der Lückendefinition (Maximum 2,01 s) und entstehen vor der App; sie traten mit `own`, `ffgt` und `none` auf (`none` in der Referenz 14 und 20 % über 1,1 s, `abstand.out`), die HAL-Probe selbst lief nur mit `own`, ohne Lock, in der Standardbedingung. **Sie sind nicht unabhängig von der App:** Der Filterwert ist die eigene Anfrage, `mMinInterval = options.minIntervalMs` [1], `location.txt` zeigt `@+1s0ms`. **Offen:** Eine Probe mit Anfrage unter 1000 ms würde den Zusammenhang durch Eingriff belegen und zeigen, ob die Toleranz nur am Prototyp hängt; sie lief nicht. Abdeckung unter 1 auf API 36 ist damit kein Fehler im Schreibpfad, und zugleich sagt 1 s Takt im Emulator nichts über ein echtes GNSS. Für die Tests in WP08 heißt das: auf API 36 bei einer Anfrage von 1 s Abstände bis etwa 2 s tolerieren, die Abdeckung nicht als 1,0 erwarten.

### Langlauf (Einzellauf)
API 36, `own`, Wake Lock, tx 1, `FULL`, natural, force-idle, gesperrt, 3613 s. Zustand: `IDLE` in 59 von 60 Abfragen (letzte `IDLE_MAINTENANCE`), ein PID, Suspend-Erfolge 0.

| Minute | Zeilen | Abstand p50 / p99 / max s | Commit p50 / p99 / max ms | PSS MB (Anon) | WAL kB | DB kB |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 572 | 1,004 / 1,912 / 1,99 | 6,45 / 11,11 / 13,0 | 97,2 (46,2) | 338 bis 2643 | 4 |
| 10 | 574 | 1,004 / 1,827 / 1,94 | 6,30 / 10,28 / 13,5 | 97,6 (46,6) | 2760 bis 4023 | 104 |
| 20 | 562 | 1,004 / 1,928 / 1,99 | 5,95 / 10,05 / 13,0 | 98,7 (47,8) | 4023 | 104 |
| 30 | 568 | 1,004 / 1,936 / 2,00 | 6,07 / 10,08 / 15,9 | 99,7 (48,8) | 4023 | 196 |
| 40 | 570 | 1,004 / 1,889 / 1,97 | 5,91 / 9,75 / 15,8 | 100,1 (49,2) | 4023 | 288 |
| 50 | 563 | 1,004 / 1,925 / 2,01 | 6,03 / 9,63 / 11,6 | 100,3 (49,4) | 4023 | 288 |

Insgesamt 3420 Zeilen in der Phase, 0 Abstände über 5 s, Maximum 2,01 s, 0 Löcher, alle empfangenen Punkte in der DB (3489 von 3489). PSS 95,9 auf 100,5 MB, lineare Steigung 4,2 MB/h, in den letzten 20 Minuten flach; ob das ein Leck ist, sagt ein Lauf nicht. Der Commit zeigt keinen Trend. Das WAL bleibt bei 4023 kB, also 1000 Frames bis zum Autocheckpoint (Standard), und passt zur Rechnung 1 Frame zu 4120 Byte je Commit.

### Kill
`lost_acked` = bestätigte Zeilen, die in der DB fehlen. `rcv_not_db` = zuletzt empfangene minus höchste gesicherte Nummer, der Preis der Transaktionsgröße. „Gerätecheck-fehlt“: kein `R005VERIFY` auf dem Gerät, die Prüfung auf dem Rechner ist trotzdem vorhanden.

Tabelle 5.

| API | Art | Host | Sync | tx | n | Läufe-mit-Verlust | max-lost_acked | Summe | rcv_not_db | mittel | Löcher | integrity-nicht-ok | Gerätecheck-fehlt |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 36 | proc | ffgt | FULL | 1 | 3 | 0/3 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 36 | proc | own | FULL | 1 | 7 | 0/7 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 36 | proc | own | FULL | 5 | 5 | 0/5 | 0 | 0 | 0 bis 1 | 0,6 | 0 | 0 | 0 |
| 36 | proc | own | FULL | 30 | 5 | 0/5 | 0 | 0 | 9 bis 27 | 18,0 | 0 | 0 | 0 |
| 36 | proc | own | NORMAL | 1 | 5 | 0/5 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 36 | proc | own | NORMAL | 5 | 5 | 0/5 | 0 | 0 | 0 bis 4 | 2,2 | 0 | 0 | 0 |
| 36 | proc | own | NORMAL | 30 | 5 | 0/5 | 0 | 0 | 3 bis 25 | 12,8 | 0 | 0 | 0 |
| 36 | emu | own | FULL | 1 | 2 | 0/2 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 36 | emu | own | NORMAL | 1 | 5 | 5/5 | 29 | 111 | 15 bis 29 | 22,2 | 0 | 0 | 0 |
| 36 | sigkill | ffgt | FULL | 1 | 3 | 0/3 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 36 | sigkill | own | FULL | 1 | 10 | 0/10 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 36 | sigkill | own | FULL | 5 | 8 | 0/8 | 0 | 0 | 1 bis 2 | 1,6 | 0 | 0 | 0 |
| 36 | sigkill | own | FULL | 30 | 8 | 0/8 | 0 | 0 | 3 bis 20 | 12,6 | 0 | 0 | 0 |
| 36 | sigkill | own | NORMAL | 1 | 9 | 9/9 | 27 | 160 | 2 bis 27 | 17,8 | 0 | 0 | 1 |
| 36 | sigkill | own | NORMAL | 5 | 4 | 4/4 | 25 | 70 | 9 bis 29 | 20,2 | 0 | 0 | 0 |
| 36 | sigkill | own | NORMAL | 30 | 3 | 3/3 | 30 | 90 | 44 bis 52 | 47,3 | 0 | 0 | 0 |
| 31 | proc | own | FULL | 1 | 3 | 0/3 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 31 | proc | own | FULL | 30 | 3 | 0/3 | 0 | 0 | 3 bis 23 | 10,0 | 0 | 0 | 0 |
| 31 | proc | own | NORMAL | 1 | 3 | 0/3 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 31 | proc | own | NORMAL | 30 | 3 | 0/3 | 0 | 0 | 6 bis 29 | 17,3 | 0 | 0 | 0 |
| 31 | sigkill | own | FULL | 1 | 5 | 0/5 | 0 | 0 | 0 | 0,0 | 0 | 0 | 0 |
| 31 | sigkill | own | FULL | 30 | 5 | 0/5 | 0 | 0 | 1 bis 20 | 10,6 | 0 | 0 | 0 |
| 31 | sigkill | own | NORMAL | 1 | 3 | 3/3 | 24 | 60 | 17 bis 24 | 20,0 | 0 | 0 | 0 |
| 31 | sigkill | own | NORMAL | 30 | 3 | 1/3 | 30 | 30 | 10 bis 31 | 17,3 | 0 | 0 | 0 |

- **`FULL` verliert nichts, soweit getroffen:** 41 harte Kills (API 36 31, API 31 10) ohne Verlust, 0 auch in jeder einzelnen Zelle. **Grenzen einseitig 95 %** nach `1 - 0,05^(1/n)`, für die empfohlene Zelle `FULL`, tx 1, hart: API 36 `own` 22 % (n = 12), mit `ffgt` 18 % (n = 15), API 31 `own` 45 % (n = 5), `emu` allein 78 % (n = 2). Über alle harten Kills gemischt 7 %; das setzt voraus, dass die Dauerhaftigkeit nach dem Bestätigen nicht von tx oder Host abhängt, was plausibel, aber nicht gemessen ist.
- **`proc` getrennt:** 26 Läufe, 0 Verluste. `NORMAL` verliert bei `proc` nichts, das sagt auch SQLite („durable across application crashes“ [3]); `proc` taugt also nicht als Beleg für `FULL`.
- **Die Kontrolle trägt:** `NORMAL` verliert bei `sigkill` und `emu` in 25 von 27 Läufen, bis 30 Zeilen; in 20 von 27 ist die Tabelle danach leer, der Gast hatte in 20 bis 65 s meist nichts weggeschrieben.
- **`adb emu kill` ist ersetzt, nicht je Transaktionsgröße gemessen.** ADR-0005 und der Auftrag verlangen Verlust „nach Prozess-Kill und `adb emu kill` je Transaktionsgröße“. Vorhanden ist nur tx 1 auf API 36 (`FULL` n = 2, `NORMAL` n = 5), kein tx 5 oder 30, nichts auf API 31. An seine Stelle tritt `sigkill` je tx (API 36 tx 1, 5, 30; API 31 tx 1, 30). Begründung: `sigkill` beendet qemu ohne jede Abschaltlogik und ist damit die härtere Prüfung; beide lassen `NORMAL` in tx 1 gleich verlieren (5 von 5 bis 29 Zeilen, 9 von 9 bis 27 Zeilen). Das ist mein Urteil, keine Messung der Gleichwertigkeit. Der Maintainer hat entschieden, die Ersetzung offen zu begründen, statt nachzumessen. ADR-0003 führt `adb emu kill` als Näherung an den Stromausfall; die Grenze „kein Stromausfall“ gilt für beide.
- **tx:** Rechnerisch bleiben mit `FULL` höchstens tx - 1 Zeilen bei 1 Punkt je Sekunde ungesichert, dazu die eine in Arbeit. Gemessen (`rcv_not_db`) tx 1 0, tx 30 bis 27. **Bei tx 1 sagt die 0 wenig:** Das Commit-Fenster beträgt etwa 6 ms je Sekunde, ein Treffer über die 20 harten Läufe hatte nur rund 10 % Chance und blieb aus; das bestätigte Ende lag in allen 20 höchstens 1,1 s vor dem Kill. „Keine Differenz“ gilt also für die getroffenen Zeitpunkte, rechnerisch bleibt bis zu 1 Zeile in Arbeit. **Bei tx 5 gilt der rechnerische Wert:** Gemessen lag `FULL` in 13 Läufen nie bei 3 oder 4, bei Gleichverteilung wäre das 0,6^13 = 0,13 %, nach der Beobachtung gewählt und mit 5 möglichen Fenstern rund 0,6 %. Die Logs zeigen keinen Fehler, das letzte `R005RCV` liegt je Lauf höchstens 1,5 s vor dem Kill, einen Mechanismus habe ich nicht gefunden. Die Wartezeiten hängen über `random.Random(run)` am Laufnamen, eine Wiederholung liefert also dieselben.
- **Gültigkeit der 12 `a31_proc_*`:** Kill per root, `pid_after_kill` leer in allen 12, keine `R005RCV` danach; `lost_acked` 0 und `rcv_not_db` wie erwartet. Die 12 alten Läufe mit `run-as` lagen daneben (Prozess lebte weiter). `a31_own_w0_i1_180s_nat_r0`: frischer Boot, 56 Zeilen Referenz (1,0 je Sekunde), 8 × `suspend entry`, Host und Sperre belegt, damit gültig.

### Kill nach dem ersten Checkpoint
Alle 115 Läufe aus Tabelle 5 haben eine Hauptdatei von 4096 Byte und höchstens 39 WAL-Frames. Bei tx 1 läuft das WAL aber erst nach etwa 18 min voll (Langlauf), ein Lauf von 60 min verbringt also rund 70 % seiner Zeit in einem Zustand, den dort kein harter Kill getroffen hat: Hauptdatei mit Daten, wiederverwendetes WAL mit neuem Salt. Diese Serie stellt den Zustand mit `wal_autocheckpoint` 10 her (Aufbau in der README): 20 Läufe, Kill nach 28 bis 45 s, keiner ungültig, kein Abbruch der Vorprüfung auf einer der beiden API-Stufen.

Tabelle 8.

| API | Sync | n gültig | Läufe mit Verlust | max-lost_acked | Summe | rcv_not_db | Löcher | integrity nicht ok | Hauptdatei Byte | WAL-ckpt_seq | WAL-Frames aktuell | WAL-Frames alt | ungültig | Verlust in ungültigen |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 36 | FULL | 7 | 0/7 | 0 | 0 | 0 | 0 | 0 | 8192 | 2 bis 3 | 1 bis 9 | 1 bis 9 | 0 | 0 |
| 36 | NORMAL | 3 | 3/3 | 6 | 14 | 4 bis 6 | 0 | 0 | 8192 | 3 bis 4 | 0 | 10 | 0 | 0 |
| 31 | FULL | 7 | 0/7 | 0 | 0 | 0 | 0 | 0 | 8192 | 2 bis 4 | 3 bis 10 | 0 bis 7 | 0 | 0 |
| 31 | NORMAL | 3 | 3/3 | 8 | 15 | 1 bis 8 | 0 | 0 | 8192 | 2 bis 3 | 0 bis 3 | 7 bis 10 | 0 | 0 |

- **`FULL` verliert auch nach dem Checkpoint nichts, soweit getroffen:** 14 Läufe, 0 Verluste, keine Löcher, Integrität ok, die Gerätegegenprüfung `R005VERIFY` nennt in allen dieselbe höchste Nummer. **Grenzen einseitig 95 %:** je API 35 % (n = 7), beide zusammen 19 % (n = 14, unter der Annahme, dass die Dauerhaftigkeit nicht von der API-Stufe abhängt). Tabelle 5 und 8 sind getrennt zu lesen, die Bedingungen unterscheiden sich.
- **Die Kontrolle trägt:** `NORMAL` verliert in 6 von 6 Läufen 1 bis 8 bestätigte Zeilen. Das ist weniger als in Tabelle 5 (bis 30) und genau die vorab genannte Erwartung: Der Checkpoint synchronisiert, verloren gehen höchstens die Commits seit dem letzten. Rechnerisch reicht dieser Verlust beim Standard von 1000 Frames bis zu etwa 18 min; das ist nicht gemessen, nur die Obergrenze aus dem Mechanismus, denn der Gast schreibt auch von selbst zurück (zwei Läufe auf API 31 behielten 2 und 3 Frames der laufenden Generation).
- **Bilanz je Lauf, unabhängig von `analyze.py` aus `logcat.txt`, `rows.tsv`, `meta.json` nachgerechnet:** Mit 3 Frames für das Schema gilt in allen 20 Läufen `höchste Zeile in der DB = 10 × ckpt_seq - 3 + WAL-Frames aktuell`. Bei `FULL` ist das in allen 14 auch das bestätigte Ende. Bei `NORMAL` stimmt der Verlust in allen 6 mit `bestätigte Frames seit dem letzten Checkpoint - überlebende Frames` überein (zum Beispiel `a31_..._NORMAL_r1`: 4 - 3 = 1, `a36_..._NORMAL_r0`: 6 - 0 = 6). Die Köpfe des WAL und die Zeilen passen also ohne Ausnahme zusammen.
- **Die Zeilen kamen wirklich aus der Hauptdatei:** Das WAL hielt höchstens 10 gültige Frames, die DB aber 17 bis 41 Zeilen, also lagen mindestens 17 Zeilen je Lauf nur in der Hauptdatei. Das Maß ist die Größe beim Ziehen, vor dem ersten Öffnen. Die liegen gebliebenen Frames der Vorgeneration (`WAL-Frames alt`, bis 10) wurden nicht eingespielt: keine Zeile über das bestätigte Ende hinaus, Integrität ok.
- **Gültigkeit:** in allen 20 Hauptdatei über 4096 Byte, `autock` 10 in `meta.json` und wirksam (WAL-Datei in allen 41 232 Byte, also 32 + 10 × 4120, bei `ckpt_seq` 2 bis 4), Neustart nach SIGKILL mit leerem PID, kein `R005RCV` nach dem Kill, kein `SqliteException`, `trecv` DB gleich Log. Stichprobe in den Rohdaten: `a36_..._NORMAL_r0` (letztes `R005ACK` 33, DB und `R005VERIFY` 27, `frames_cur` 0) und `a31_..._FULL_r3` (35, 35, 35). `rcv_not_db` ist bei `FULL` 0, mit derselben Einschränkung wie bei Tabelle 5: Das bestätigte Ende lag höchstens 1,3 s vor dem Kill, das Commit-Fenster ist klein.
- **Zeitstempel:** In 2 Läufen liegt das letzte `R005ACK` bis 0,31 s nach `tkill`, weil der Harness `tkill` vor dem `pidof` per adb nimmt, der Kill also etwas später fällt. Die Auswertung zählt bis `tkill + 1 s`, das Ergebnis ändert sich dadurch nicht.
- **Grenzen, gemessen ist nur der kleine Fall:** Jeder Checkpoint überträgt hier 10 statt 1000 Frames. Größe und Häufigkeit sind andere, die Art des Zustands (Hauptdatei mit Daten, wiederverwendetes WAL, neuer Salt, Reste der Vorgeneration) dieselbe. Die Hauptdatei hat in allen Läufen genau 2 Seiten (8192 Byte), bei 41 Zeilen und etwa 80 Byte je Zeile also keine Seitenteilung und kein Commit über mehrere Seiten; der Langlauf erreichte 288 kB, auf einer solchen Datei lief kein harter Kill. **Ein Kill mitten im Checkpoint ist offen:** weder gesucht noch ausgeschlossen, das Zeitfenster ist klein. `sigkill` bleibt kein Stromausfall.

**`ffgt` nach `kill -9` (API 36, 3 von 3):** ActivityManager `Scheduling restart of crashed service`, neuer PID (3707, 4083, 4301), der Dienst zeichnet von selbst wieder auf (hier mit Primärschlüssel-Fehlern `SqliteException(1555)`, weil die Nummerierung des Prototyps neu beginnt). Quelle: `ForegroundService.kt` in 11.0.3 gibt `START_STICKY` zurück, außer bei `stopWithTask`, und setzt in `onTaskRemoved` **unabhängig von `allowAutoRestart`** einen Alarm mit 1 s; `allowAutoRestart` wirkt nur in `onDestroy` [4]. Die Wirkung des Alarms ist nicht gemessen, beim Wischen blieb der PID gleich. `allowAutoRestart: false` reicht also nicht für ADR-0005 Punkt 6. `own` (`START_NOT_STICKY`): kein Neustart, API 31 und 36. Auf API 31 lief `ffgt` nicht im Kill.

### Wischen aus den letzten Apps
Tabelle 6.

| Lauf | Zeilen | PID | Recents | max-Abstand-s | >5s |
| --- | --- | --- | --- | --- | --- |
| a31_ffgt_r0 | 124 | gleich | 10→0 | 1,04 | 0 |
| a31_own_r0 | 125 | gleich | 10→0 | 1,01 | 0 |
| a36_ffgt_b_r0 | 112 | gleich | 10→0 | 1,98 | 0 |
| a36_ffgt_b_r1 | 116 | gleich | 10→0 | 1,79 | 0 |
| a36_own_b_r0 | 111 | gleich | 10→0 | 1,96 | 0 |
| a36_own_b_r1 | 112 | gleich | 10→0 | 1,99 | 0 |
| a36_own_r0 | 112 | gleich | 10→0 | 1,77 | 0 |

Recents gehen in allen Läufen auf 0, die Geste wirkte also. `own` meldet `onTaskRemoved`, gleicher PID, Dienst bleibt im Vordergrund. Der Engine überlebt die Activity damit im Emulator.

### Schreibkosten (Emulator, nur relativ)
n = 280 je Zelle, ein Lauf, Einlauf verworfen. p50 / p95 ms je Transaktion.

| tx | API 36 FULL | API 36 NORMAL | API 31 FULL | API 31 NORMAL |
| --- | --- | --- | --- | --- |
| 1 | 1,72 / 2,77 | 1,09 / 1,30 | 1,45 / 1,65 | 1,06 / 1,26 |
| 5 | 2,44 / 3,47 | 1,97 / 2,21 | 2,17 / 2,67 | 1,88 / 2,04 |
| 30 | 7,28 / 8,51 | 7,25 / 7,64 | 7,55 / 12,48 | 6,83 / 7,45 |

Im Lauf mit echter Rate ist der Commit langsamer (Tabelle 1, p50 3,3 bis 6,4 ms), vermutlich weil Prozess und Isolate zwischen den Punkten ruhen. Der Vorsprung von `NORMAL` ist klein, doch fsync im Emulator trifft den Rechner, nicht Flash, also überträgt sich das nicht. Bei tx 1 etwa 1 WAL-Frame je Commit (2041 Frames auf 2000 Transaktionen), rund 15 MB/h ins WAL, gerechnet. Energie ungemessen.

### Verschlüsseltes WAL
| Ort, Lauf | Datei | Größe Byte | Frames | Marker | Double | SQLite-Header | χ² (255 FG) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Rechner, verschlüsselt | WAL | 8 408 952 | 2041 | 0 | 0 | 0 | 273 |
| Rechner, verschlüsselt | DB | 4096 | – | 0 | 0 | 0 | 264 |
| Rechner, Klartext (Kontrolle) | WAL | 8 408 952 | 2041 | 103 299 | 103 299 | 20 | 600 279 084 |
| API 36 `a36_enc_b` | WAL | 482 072 | 117 | 0 | 0 | 0 | 268 |
| API 36 `a36_enc_b` | DB | 4096 | – | 0 | 0 | 0 | 236 |
| API 36 `a36_plain` (Kontrolle) | WAL | 477 952 | 116 | 3135 | 2058 | 3 | 34 354 174 |
| API 36 `a36_plain_b` (Kontrolle) | WAL | 482 072 | 117 | 2921 | 1861 | 4 | 37 675 187 |
| API 31 `a31_enc` | WAL | 515 032 | 125 | 0 | 0 | 0 | 253 |
| API 31 `a31_enc` | DB | 4096 | – | 0 | 0 | 0 | 276 |
| API 31 `a31_plain` (Kontrolle) | WAL | 515 032 | 125 | 2981 | 1836 | 4 | 42 246 127 |

Double: am Rechner fester Wert, im Emulator Summe über die ersten 50 Breitengrade. χ² bei WAL auf den Seiteninhalten; zweiseitig etwa 212 bis 300 wären bei Zufall üblich. Beleg, dass das WAL Inhalt hatte (Rechner): Kopie mit Schlüssel 2000 Zeilen, falscher oder kein Schlüssel Fehler 26, Datei ohne WAL keine Tabelle. Auch nach dem Checkpoint: 90 112 Byte, 0 Treffer, χ² 244. `TEMP_STORE=2` (temporäre Daten im Speicher, soweit nicht `PRAGMA temp_store` anderes sagt). **Sichtbare Metadaten:** Die Frame-Köpfe bleiben Klartext (`src/walhdr.py`): WAL-Magic, Seitennummer, Commit-Kennung, Salt. In `a36_enc_b` sind es 111 Commit-Frames bei 111 `R005ACK`. Die Zahl der Commits und das Schreibmuster sind also ohne Schlüssel lesbar, Inhalte nicht. Für SEC-0009 vermutlich unkritisch, gehört aber zu „nachweislich verschlüsselt“ dazu.

**FAQ-Fall „must not be in WAL“.** Der Satz steht in der FAQ von SQLite3MultipleCiphers nur beim **Ändern der Seitengröße** [5]. Im Versuch (`run3.log`): `VACUUM` mit neuer Seitengröße läuft im WAL-Modus ohne Fehler und ohne Wirkung; die FAQ-Prozedur entfernt zuerst den Schlüssel und bricht dann beim letzten `rekey` ab („Rekeying an unencrypted database is not supported in WAL journal mode“). **Die Datei bleibt danach im Klartext**, 200 von 200 Markern, lesbar ohne Schlüssel. Im Modus `DELETE` geht es (Seitengröße 8192). Die Pragma-Doku nennt die Grenze genau so [6].

**Schlüsselwechsel:** im WAL-Modus mit ungecheckpointeten Daten möglich, ab 2.4.0 [6][7], der Salt bleibt, was der Changelog als geringe Einbuße beschreibt [7]. Im Versuch: Salt gleich, neue Kopie mit neuem Schlüssel 501 Zeilen, alter Schlüssel Fehler 26, auch nach dem Schließen. Ob Reste mit altem Schlüssel im WAL bleiben, nicht geprüft. ADR-0003 braucht weder Seitengrößenwechsel noch Rekey.

**Stand der Bibliothek:** Geprüft ist 2.6.1. Der Changelog `[Unreleased]` nennt danach Korrekturen wie „Encryption errors on writing not propagated“, „Legacy WAL frame write discarded write result code“ und Prüfungen zu Hot Journals (#291 bis #294) [7]. Die zwei gelesenen Issues (#291, #293) betreffen den Rollback-Journal-Modus, nicht diesen Aufbau, #292 und #294 sind nicht gelesen. Bei einem Wechsel der Version ist das zu berücksichtigen.

**Nebenbefund:** Ein gekipptes Byte im ersten WAL-Frame: SQLite verwirft das WAL ab dort ohne Fehlermeldung beim Öffnen (die Tabelle fehlt danach einfach, weil sie im WAL lag). Manipulation führt also auch zu stillem Abschneiden, nicht nur zu einem Fehler. Bewertung offen.

### Wake Lock
- **Messung nur nach Eingriff:** Im Goldfish-Image hält der Kernel `emulator_wake_lock` ab etwa 13 s nach dem Boot (`cat /sys/power/wake_lock`, `dumpsys suspend_control_internal`). Damit schläft der Emulator nie, und jeder Vergleich mit und ohne Wake Lock unter Standardbedingung ist wertlos. Woher der Schreibbefehl kommt, habe ich nicht gefunden: `init.ranchu.rc` macht in den gelesenen Ständen nur `chown` [8]. Erst nach `echo emulator_wake_lock > /sys/power/wake_unlock` (root) schaltet `mHalAutoSuspendModeEnabled` auf `true`, und `system_suspend` schläft von selbst (`PM: suspend entry (s2idle)`).
- **`geo fix` weckt nicht, die Messung entscheidet die Frage also nicht:** Standorte vom Rechner lösen keinen Wakeup aus, der Emulator kam aus dem letzten Suspend nie zurück. Gemessen ist nur: Mit Lock kein Suspend. Der Befund „ohne Wake Lock endet die Aufzeichnung“ ist **kein Beleg für Geräte**. Auch Konsolen-Ereignisse und RTC-Alarm holten den Emulator in den Proben nicht zuverlässig zurück. Ohne-Lock-Betrieb bleibt für Geräte offen.
- **Wake Lock in Doze:** Google schreibt „Ignores wake locks“ für Doze [9]. In den Läufen hielt `r005:rec` das System trotz `force-idle` (Suspend 0, `IDLE`). Das passt zur Quelle: `PowerManagerService` sperrt Partial Wake Locks im Idle nur für Prozesszustände unterhalb von `BOUND_FOREGROUND_SERVICE` [10], ein Foreground-Service bleibt also ausgenommen. Quelle für den Zweig von Android 16 gelesen, auf API 31 nur gemessen.
- **Gegenposition von Google, vollständig:** Die Android-Doku zum Standort sagt: „Avoid acquiring a separate, continuous wake lock for caching location data, as this is redundant and should be removed. When requesting location updates using the `FusedLocationProvider` or `LocationManager` APIs, the system automatically triggers a device wake-up during the location event callback.“ [15] AOSP bestätigt den Teil zur Zustellung: `LocationProviderManager` hält je Zustellung für nicht passive Anfragen die Sperre `*location*` mit bis zu 30 s [16]; der Prototyp nutzt `LocationManager`. Die Kosten nennt Google deutlich [11]. Die allgemeine Regel [12] sagt, bei einem Foreground-Service, dem ein Schlaf schadet, „you might need to use a wake lock. However, you should still check to see if you're already using an API or doing an action that declares a wake lock on your behalf“. Für den Standort weist diese Prüfung laut [15] gegen einen eigenen Lock.
- **Android Vitals:** Ein eigener Lock wie `r005:rec` zählt, denn Vitals erfasst Locks auch beim Lauf eines Foreground-Service und nimmt nur solche aus, die Audio-, Standort- und JobScheduler-APIs selbst anlegen. Übermäßig sind 2 h oder mehr in 24 h, über 5 % der Sitzungen in 28 Tagen können die Sichtbarkeit auf Play mindern [17]. Lange Läufe liegen in Reichweite, der Vertriebsweg ist offen (ADR-0002). Vitals kennt Ausnahmen bei klarem Nutzen für den Nutzer [17], ob eine Aufzeichnung darunter fällt, ist nicht geprüft.
- **Warum das den Lock nicht ausschließt:** [15] spricht vom Zwischenspeichern, und der Commit läuft asynchron in Dart nach dem Rückruf, also womöglich nach Ende der kurzen Sperre. Ob das auf einem Gerät reicht, ist nicht gemessen. Foren und ein Flutter-Paket raten aus Erfahrung zum Lock, andere berichten von Geräten, die trotz Lock aussetzen, beides nur anekdotisch. Der Stand ist offen.
- **Entscheidung des Maintainers (2026-11-04): Lock an, als Abwägung.** Partial Wake Lock für die Laufdauer als bewusste Vorsichtsentscheidung: Verlorene Laufdaten kommen nicht wieder, Mehrverbrauch und Vitals werden in Kauf genommen. Das ist ausdrücklich nicht durch Messung belegt. **Ausstieg:** Zeigt der Feldtest den Lock als überflüssig, entfällt er.

### Bau und `universal_ble`
Profil-Build mit `universal_ble` 3.2.0, minSdk 31, target 36, compileSdk 36 (per `aapt2` geprüft), AGP 9.1.0, Gradle 9.3.1. Das Plugin selbst setzt `compileSdkVersion 34`, das stört nicht. Klassen von `universal_ble` sind in der APK (`dexdump`, 4820 Treffer). **Der Dart-Teil ist nicht importiert, also nicht mitkompiliert;** belegt ist der Bau, nicht das Laufen (R006).

### Lizenzbaum
`flutter pub deps` samt Lizenzdatei im Pub-Cache, Gradle samt POM, einschließlich Dev-Abhängigkeiten und `hcProbe` (`connect-client` 1.1.0, ADR-0007). Ohne Rechtsprüfung.

Tabelle 7.

| Ökosystem | Lizenz | Einträge |
| --- | --- | --- |
| dart | Apache-2.0 | 2 |
| dart | BSD-2-Clause | 1 |
| dart | BSD-3-Clause | 93 |
| dart | MIT | 9 |
| dart | MPL-2.0 | 2 |
| gradle | Apache-2.0 | 122 |
| gradle | BSD-3-Clause | 2 |
| gradle | KEINE ANGABE IM POM | 8 |
| gradle | MIT | 1 |

| Fund | Einordnung (ohne Rechtsprüfung) |
| --- | --- |
| **MPL-2.0: `bluez` 0.9.0, `dbus` 0.8.0**, transitiv über `universal_ble`, für Linux | Verträglich. MPL 3.3 erlaubt die Verbindung mit GPL zu einem „Larger Work“, solange der Code nicht als „Incompatible With Secondary Licenses“ markiert ist [13][14]; in beiden `lib/` kein solcher Vermerk, im `LICENSE` nur die Mustervorlage. Pflicht bleibt: MPL-Dateien bleiben unter MPL, Hinweise erhalten, Quellen zugänglich. `universal_ble.dart` importiert den Linux-Teil ohne Bedingung; ob er im Android-AOT landet, ist nicht geprüft, ich nehme es an |
| `io.flutter:*` (8 Einträge) ohne POM-Angabe | BSD laut Flutter-Lizenz, Drittanteile in `libflutter.so` nicht je Datei geprüft |
| BSD-2-Clause (`recase`), BSD-3 (Protobuf), MIT (`checker-qual`, nur `hcProbe`) | permissiv, unkritisch |
| Native `.so` in der APK | `libflutter`, `libapp`, `libvmservice_snapshot` (nur Profil), `libsqlite3mc` (SQLite Public Domain, SQLite3MC MIT, ADR-0003), `libdartjni` (`jni`, BSD, über `path_provider_android`, `shared_preferences_android`), `libdatastore_shared_counter` (androidx, Apache) |

**Prüfstand `play-services`:** 0 Treffer für `gms`, `firebase`, `play-services` in `profileRuntimeClasspath`, `releaseRuntimeClasspath`, `hcProbe`; `dexdump` aller 13 DEX-Dateien der APK 0 Treffer `com/google/android/gms`, `com/google/firebase`. Geprüft ist der Satz Pakete des Prototyps (drift, sqlite3, flutter_secure_storage, universal_ble, cryptography, flutter_foreground_task, dazu Dev-Pakete), nicht `app/`. Das Image selbst bringt GMS mit; davon hängt die App nicht ab. `flutter_foreground_task` bringt Boot-Empfänger und `RECEIVE_BOOT_COMPLETED`, wie ADR-0005 nennt.

## Bewertung und Zweifel
**Selbst angesehen und nachgerechnet:** Rohzeilen der Stichproben (Rows gegen HAL-Log, Kernel-Logs, Log nach Kill je Lauf, Pufferstoß nach SIGSTOP), Handrechnungen für Frames je Commit und WAL-Größe, Quellen gelesen. Seit der Nachbesserung gleicht `analyze.py` jeden Lauf gegen das Log ab (`R005ACK` vorhanden, kein `SqliteException`, `trecv` DB gleich Log); die Prüfung erkennt den bekannten Fehlerfall (Gegenprobe vor dem Verschieben: `a36_own_w0_i1_120s_nat_r0` ungültig, 56 von 56 abweichend) und meldet sonst nur den Lauf ohne Commit unten.

**Was das Ergebnis begrenzt:**
- **Kleines n je Zelle:** 1 bis 4 Läufe bei den Lücken, 2 bis 10 beim Kill. „0 Verluste“ heißt: für die empfohlene Zelle bis 22 % je Lauf nicht ausgeschlossen (API 36), auf API 31 bis 45 %, jeweils einseitig 95 %.
- **Langlauf ist ein Einzellauf,** nur API 36 und `own`. Auf API 31 und mit `ffgt` höchstens 600 s.
- **Wake-Lock-Vergleich nur nach Eingriff** in den Emulator (`emulator_wake_lock` gelöst), `geo fix` weckt nicht, kein Beleg für Geräte. Keine Prüfung, ob der Eingriff weiteres verändert.
- **`-show-kernel`:** ab den Proben natural und in der Matrix an, Phase A ohne (`_smoke`, `_ctl`, `_pausectl`, `a36_own_r0`, `_probe`). Sichtbarer Unterschied: keiner (`a36_own` Abdeckung 0,94 gegen 0,93). Phase-A- und Matrixläufe gemeinsam ausgewertet, z. B. `sigkill tx1 FULL` 2 + 8.
- **`sigkill` ist kein Stromausfall:** Der Rechner läuft weiter, Host-Cache bleibt. Es zeigt, dass der Gast-Pagecache verloren geht und `FULL` ihn vorher verlässt, nicht dass Daten auf Flash sind. Echter Stromausfall bleibt offen, ADR-0003 sagte das schon.
- **Kill trifft nur frühe Läufe:** 20 bis 65 s, ohne Sperre. Tabelle 5 ohne Checkpoint, Tabelle 8 nach Checkpoints von 10 Frames auf 2 Seiten Hauptdatei; große Hauptdateien und Checkpoints von 1000 Frames sind nicht direkt getroffen. Die Art des Prozess-Kills unterscheidet sich: API 36 `run-as`, API 31 root; Wirkung in beiden belegt.
- **Rate 1 Hz vom Rechner, 3 m je Schritt,** keine echte GPS-Qualität, Einspeisung per `adb` mit Latenz. Keine Aussage zu BLE zugleich (R006).
- **Fremder Emulator daneben** und Host-Lastspitzen bis 19: Kein Lauf zeigt dadurch Lücken, könnte aber Commit-Zeiten beeinflussen.
- **Abdeckung ist kein Kriterium:** Toleranz wegen NMEA-Rundung, blind für Einfrieren, auf API 36 durch den HAL begrenzt.
- **Herzschlag** erfasst nur, was `adb logcat` mitbekommt; im Schlaf ist adb offline, dort zählt die DB.

**Eigene Aufbaufehler, Läufe verworfen (`invalid/`, Rohdaten erhalten):**
| Ordner | Fehler | Folge |
| --- | --- | --- |
| `a31-proc-runas-wirkungslos` (12 Läufe) | `kill -9` per `run-as` wirkte auf API 31 nicht, Prozess schrieb weiter | neu per root mit PID-Prüfung |
| `a31-nat-w0-nach-forced` | lief in derselben Boot-Sitzung nach erzwungenem Suspend, keine Zeile | neu, frisch gebootet |
| `stopctl-pid-leer` | `pidof` direkt nach `am start` leer, SIGSTOP wirkte nie | Harness korrigiert, `_stopctl2` |
| `wal-enc-befehl-verloren` | Befehl beim ersten Start nach Installation verloren, `x.db` war eine Fehlermeldung | `R005START` wird geprüft, `a36_enc_b` |
| `swipe-ffgt-geste-wirkungslos` | Geste wirkte nicht (Recents 10 → 10) | Wiederholung, `swipe_tries`, `_b` |
| `nat-*-versuch-*` (3), `forced-w1-kam-nicht-zurueck` | Emulator wachte nicht auf (Weckversuche über Konsole und RTC) | Ende per SIGKILL, DB nach Neustart lesen |
| `nat-w0-120s-veraltete-db` | `a36_own_w0_i1_120s_nat_r0`: 56 × `SqliteException(1555)`, 0 × `R005ACK`, die Zeilen stammten aus einem abgebrochenen Vorversuch mit gleichem Namen, der vor `rm_runs` abbrach. Stand als gültig in Tabelle 2, `analyze.py` zählte nur `R005ERR` | verschoben, Zelle `36 own nein` jetzt 2 Läufe; `rm_runs` vor jedem Lauf, Gültigkeit um Log-Abgleich ergänzt. Der Schluss zum Suspend ändert sich nicht, `kernel-pm.txt` bleibt erhalten |
| `tx30-kein-commit-vor-kill` | `a36_sigkill_tx30_NORMAL_r0`: Kill nach 28 Zeilen, vor dem ersten Commit, kein `R005ACK`, prüft also nichts. Fiel erst durch die neue Gültigkeit auf | verschoben; `NORMAL` hart jetzt 25 von 27, nicht 25 von 28. Dieser Lauf war der eine „ohne Verlust“ auf API 36 |

Außerdem: Die erste Fassung der README nahm `elapsedRealtime - uptimeMillis` als Schlaf-Beleg, was die Probe widerlegte (bleibt auch bei belegtem Suspend 0). Ersetzt durch Kernelzähler und Kernel-Log. `analyze.py` meldete zuerst `kill` als gültig, ohne den PID zu prüfen; das fiel beim Durchsehen auf. Ein Lauf ohne `R005VERIFY` (`a36_sigkill_tx1_NORMAL_r3`: die Gegenprüfung auf dem Gerät fehlt, Rechner-Prüfung `integrity_check` ok).

**Auffällig, aber nicht geklärt:** API 31 nach erzwungenem Suspend ohne Standort bis zum Neustart. Zeitpunkt des ersten Schlafs streut zwischen API 31 und 36. `tx 30 NORMAL` auf API 31: 2 von 3 Läufen ohne Verlust mit je 30 bestätigten Zeilen in der DB, vermutlich schrieb der Gast rechtzeitig zurück; nicht untersucht. Auf API 36 ist der entsprechende Lauf als ungültig entfallen.

### Ungeprüft
Hersteller-Energiesparmodi; Akku und Energie; echter Stromausfall; echtes Schlafverhalten eines Geräts samt Wecken durch GNSS; **Schrittsensor (fehlt auf API 31 und 36: `stepCounter=false stepDetector=false`, die Frage aus ADR-0005 und WP08 ist nicht beantwortbar)**; FR-0034 im Feld; Laufzeit von `universal_ble` (R006); hardwaregebundener Keystore; Kill im Checkpoint; `ffgt` mit `stopWithTask`; Speicher von `ffgt`; HAL-Filter bei Anfrage unter 1000 ms; das Verhalten von `adb emu kill` außer tx 1 auf API 36.

## Vorschläge für die ADRs (nicht geändert)
**ADR-0005**
- Punkt 3 vom Vorbehalt befreien, mit dem Zusatz „im Emulator, FR-0034 im Feld offen“.
- Konsequenz zum Wake Lock ersetzen: Dienst hält für den Lauf einen Partial Wake Lock, **als Entscheidung des Maintainers**: nicht durch Messung belegt, Abwägung Datenverlust gegen Akku und Vitals, Gegenposition von Google und Vitals-Regel im Text genannt, Ausstieg, wenn der Feldtest ihn als überflüssig zeigt. Unter „Im Emulator nicht belegbar“ aufnehmen: echtes Schlafverhalten, Wecken durch GNSS, Ohne-Lock-Betrieb.
- Punkt 5 konkretisieren: eine Zeile je Transaktion als Startwert, keine Produktvorgabe.
- Alternative `flutter_foreground_task` ergänzen: `allowAutoRestart: false` verhindert den Neustart nicht (`START_STICKY`, Alarm in `onTaskRemoved`). Als Rückfallweg bräuchte er einen Patch oder eine Prüfung mit `stopWithTask`, sonst verletzt er Punkt 6.
- `health`-Typ: **Frage nicht beantwortbar,** der Schrittsensor fehlt auf beiden Images. Die Bedingung aus ADR-0005 Punkt 2 („entfällt, sofern R005 keinen Bedarf zeigt“) bleibt offen, Prüfung im Feldtest. Fehlende Messung löst sie nicht aus.
- Messauftrag zu `adb emu kill` je Transaktionsgröße: durch `sigkill` ersetzt, Begründung in diesem Ergebnis.
- Testhinweis für WP08: `emulator_wake_lock` hält den Emulator wach, Kill auf API 31 per root, HAL-Abstände bis 2 s auf API 36 bei Anfrage 1 s (Abhängigkeit von der Anfrage nicht geprüft).

**ADR-0003**
- Offenen Punkt zum WAL schließen: im Stand sqlite3mc 2.6.1, SQLite 3.54.0 nachweislich verschlüsselt (Rechner, API 31, 36), Frame-Köpfe bleiben Klartext.
- Punkt 5 um Messung ergänzen: `FULL` im Emulator 0 Verluste, vor dem ersten Checkpoint und danach (`wal_autocheckpoint` 10, 14 `sigkill`-Läufe, Kontrolle `NORMAL` verliert in 6 von 6), Kosten klein, gilt nur relativ. Kill mitten im Checkpoint und Checkpoints von 1000 Frames sind nicht gemessen. Unter „nicht belegbar“: `adb emu kill` und `sigkill` nähern sich dem Stromausfall nur an.
- Warnung ergänzen: Seitengrößenwechsel nur außerhalb von WAL, die FAQ-Prozedur hinterlässt sonst eine **Klartextdatei**. Die Laufzeitprüfung aus Punkt 1 ist also auch nach Wartungsschritten nötig. Rekey geht im WAL ab 2.4.0, Salt bleibt.
- Stilles Abschneiden des WAL bei Manipulation aufnehmen, Bewertung offen; bisher gilt „Authentifizierung je Seite“, das fängt verworfene WAL-Enden nicht ab.

**ADR-0006**
- Konsequenz streichen: Bau mit Target 36 ist belegt (AGP 9.1.0, compileSdk 36), Laufzeit nicht (R006).
- Lizenz ergänzen: `universal_ble` zieht `bluez`, `dbus` (MPL-2.0), Pflichten aus MPL beim Vertrieb.

Am Rande: In ADR-0002 steht Bau und Lizenzbaum noch als unbelegt, das erledigt dieses Ergebnis für den Prototyp.

## Offene Punkte und Folgeanalysen
- Feldtest auf echten Geräten (Sache des Maintainers): Sperre, Doze, mit und ohne Wake Lock samt Ausstieg aus dem Lock, Akku, Herstellermodi, Schrittsensor unter Typ `location`. FR-0034 bleibt offen.
- R006 für `universal_ble` unter dem Dienst. Lizenzprüfung wiederholen, sobald `app/` steht (`./run.sh licenses` zeigt, wie).
- Falls wichtig: Kill im Checkpoint, Kill auf großer Hauptdatei mit Standard-`wal_autocheckpoint` (ein Lauf braucht über 18 min), Stromausfall am echten Gerät, Speichertrend über mehrere Stunden, HAL-Probe mit Anfrage unter 1000 ms, `emu` nachmessen (API 36 tx 5 und 30, API 31 tx 1 und 30).

## Quellen (Abruf 2026-11-04)
[1] https://android.googlesource.com/device/generic/goldfish/+/refs/heads/main/hals/gnss/Gnss.cpp ·
[2] https://android.googlesource.com/device/generic/goldfish/+/refs/heads/android12-release/gnss/gnss.cpp ·
[3] https://www.sqlite.org/pragma.html#pragma_synchronous ·
[4] https://pub.dev/packages/flutter_foreground_task (`ForegroundService.kt` im Archiv 11.0.3) ·
[5] https://utelle.github.io/SQLite3MultipleCiphers/docs/faq/faq_overview/ ·
[6] https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/ ·
[7] https://github.com/utelle/SQLite3MultipleCiphers/blob/main/CHANGELOG.md (2.4.0) ·
[8] https://android.googlesource.com/device/generic/goldfish/+/refs/heads/android14-release/init.ranchu.rc ·
[9] https://developer.android.com/training/monitoring-device-state/doze-standby ·
[10] https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/power/PowerManagerService.java ·
[11] https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/set ·
[12] https://developer.android.com/develop/background-work/background-tasks/awake ·
[13] https://www.mozilla.org/en-US/MPL/2.0/ (Abschnitt 3.3, auch `LICENSE` der Pakete) ·
[14] https://www.mozilla.org/en-US/MPL/2.0/FAQ/ ·
[15] https://developer.android.com/develop/background-work/background-tasks/awake/wakelock/identify-wls#location ·
[16] https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/services/core/java/com/android/server/location/provider/LocationProviderManager.java (Zeilen 155 bis 156, 1002 bis 1016) ·
[17] https://developer.android.com/topic/performance/vitals/excessive-wakelock
