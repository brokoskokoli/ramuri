# R008 – Ergebnis

## Kurzfassung
Alle drei Kandidaten zeigen ohne Einwilligung keine Verbindung zu einem Kartenhost und mit Einwilligung nur `tiles.openfreemap.org` (Cloudflare); `maplibre_gl` spricht keine fremden Kartenhosts (Mapbox, MapTiler, MapLibre-Demo) an. Den Randbedingungen von ADR-0009 genügt ohne Eingriff in fremden Code nur **`flutter_map` 8.3.2 + `flutter_map_vector_tiles` 2.11.0** (Mini-App `fmvt`): Ein eigener `http.Client` sieht jede Anfrage (Einwilligung, Host-Liste, verschlüsselte Ablage), der Plattencache der Bibliothek ist abschaltbar, die Miniatur entsteht als Bild einer unsichtbaren Karte samt Route und wird danach ohne Netz angezeigt, APK +2,6 MB (arm64). `maplibre_gl` 0.28.0 lädt über natives OkHttp am Dart-Code vorbei, kann Kacheln nur im Klartext-SQLite-Cache oder gar nicht speichern (dann jede Ansicht neu aus dem Netz: Detailkarte 1,0 MB je Öffnen, 50 Miniaturen 22,8 MB), seine Snapshot-Funktion zeigt die Route nicht, und es kostet +13,3 MB APK und im Emulator das 3,5-Fache der CPU-Zeit von `fmvt` auf der Live-Seite. `vector_map_tiles` (Mini-App `fm`) braucht einen Patch, ist Beta und „minimally maintained“, und die Live-Karte wurde im Emulator unter API 36 nur zu einem Teil gezeichnet (unter API 31 vollständig, Ursache offen). OpenFreeMap ist für eine verteilte App zulässig (Apps ausdrücklich erlaubt, kein Schlüssel, keine Limits), aber ohne SLA und mit drei Ausfällen in 15 Monaten; die Karte muss deshalb ohne Kacheln weiter funktionieren.

**Empfehlung (ADR-0009 Punkt 6):** Bibliothek `flutter_map` + `flutter_map_vector_tiles` (Vektorkacheln, Stil „liberty“ o. ä. von OpenFreeMap), Anbieter OpenFreeMap, Ausweichanbieter als austauschbare Stil-URL hinter demselben Tor (VersaTiles ohne Schlüssel; langfristig selbst gehostete Protomaps-PMTiles, die `flutter_map_vector_tiles` direkt lesen kann). Speicherweg: eigener `http.Client` als Tor (Einwilligung, nur GET https auf freigegebene Hosts, jede Antwort AES-GCM verschlüsselt im eigenen Speicher), `StyleReader(httpClient:, cache: false, resolveProvider:)`, Plattencache der Bibliothek 0. Miniaturweg: unsichtbare Karte, `RepaintBoundary.toImage` nach Ladeende, PNG verschlüsselt ablegen, in der Historie nur Bilder zeigen; ohne Einwilligung nur die Linie. Hinweise für WP13 unten unter „Hinweise für WP13“. Belastbar sind Netz- und Speicheraussagen (Mitschnitt mit Positivkontrolle, Host-Tests mit Gegenprobe); Bildrate und CPU sind Emulatorwerte mit Software-GL und nur als Rangfolge zu lesen.

## Lauf
- Datum: 2026-11-07/08 · Rechner: Mac, Apple Silicon (arm64), macOS 27.2, Flutter 3.47.7 · Emulator: AVD `running_app_api36` bzw. `running_app_api31` (google_apis, arm64), `-read-only`, Software-GL (SwiftShader auf dem Host, „memory pressure“, 4 GB frei)
- Code-Stand der Läufe: `21db1f0` mit uncommitteten Änderungen an `src/emu.sh`, `src/apps/*`, die in `1a83f9c` committet sind (`run.info`: `dirty=1`); Auswertung `src/emu_eval.py` und die Korrektur in `src/emu.sh` (siehe „Fehler im eigenen Aufbau“) im Commit dieses Ergebnisses.
- Läufe (Ausgaben unter `$RESEARCH_DATA/work/R008/`):

| Schritt | Lauf | Kommando | Laufzeit |
| --- | --- | --- | --- |
| Testvorlagen | `fixtures/` | `./init.sh` | < 1 min |
| Host-Tests | `host-20261108-001527` | `./run.sh host` | ~1 min |
| Build | `build-20261108-001232` | `./run.sh build` | ~10 min |
| Lizenzen | `licenses-20261108-001501` | `./run.sh licenses --apps "fm fmvt ml"` | ~2 min |
| Netz statisch | `netstatic-20261108-001508` | `./run.sh netstatic` | < 1 min |
| Emulator API 36 | `emu-20261108-003341` | `./run.sh emu --api 36 --apps "fm fmvt ml"` | 42 min |
| Auswertung API 36 | `emu-20261108-003341/eval.json` | `python3 -I src/emu_eval.py <emu-ordner>` | < 1 min |
| Emulator API 31 (Start-Smoke) | `emu-20261108-012618` (erster Versuch `-012021` abgebrochen) | `./run.sh emu --api 31 --apps "fm fmvt ml"` | 6 min |

Der erste Emulatorlauf `emu-20261108-001612` ist ungültig (Mitschnitt sah das WLAN nicht, nur Nullen) und wurde abgebrochen.

## Ergebnisse

### Kandidaten und Versionen
| Mini-App | Bibliothek | Kachelweg | Speicher-Hook | Miniatur |
| --- | --- | --- | --- | --- |
| `fm` | `flutter_map` 8.3.2 + `vector_map_tiles` 9.0.0-beta.13 (`vector_tile_renderer` 6.1.0) | Dart, `http` 1.6.0 | nur per Patch (26 Zeilen, `src/patch_vmt.py`: `cacheStorage` statt Klartext-Dateicache) | `RepaintBoundary.toImage` |
| `fmvt` | `flutter_map` 8.3.2 + `flutter_map_vector_tiles` 2.11.0 | Dart, `http` 1.6.0 | ohne Patch: `StyleReader(httpClient:, cache: false, resolveProvider:)`, `diskCacheMaximumSizeInBytes: 0` | unsichtbare Karte + `RepaintBoundary.toImage` nach Ladeende |
| `ml` | `maplibre_gl` 0.28.0, MapLibre Android 13.7.1 | nativ (OkHttp 5.4.0) | keiner möglich ohne nativen Eingriff; Ambient-Cache 0 (`setMaximumAmbientCacheSize(0)`) | `takeSnapshot` (MapSnapshotter) |

### APK-Größe (Release, `build-20261108-001232`)
| App | arm64-v8a | Zuwachs | x86_64 | Zuwachs | universal | Zuwachs |
| --- | --- | --- | --- | --- | --- | --- |
| base | 15,31 MB | – | 16,74 MB | – | 43,25 MB | – |
| fm | 17,44 MB | +2,14 MB | 18,86 MB | +2,12 MB | 49,73 MB | +6,48 MB |
| fmvt | 17,91 MB | +2,61 MB | 19,46 MB | +2,72 MB | 51,41 MB | +8,16 MB |
| ml | 28,65 MB | +13,34 MB | 30,44 MB | +13,70 MB | 78,60 MB | +35,36 MB |

Einzelmessung je Build (deterministisch; zwei Builds von base/fm/ml byte-gleich). Die Mini-Apps enthalten neben der Bibliothek ~100–300 Zeilen eigenen Code und `cryptography`-Pakete für den Speicher, der Zuwachs ist also eine obere Schranke für die Bibliothek.

### Lizenzbaum (`licenses-20261108-001501`)
| App | Dart ausgeliefert | Gradle (`releaseRuntimeClasspath`) | zu prüfen |
| --- | --- | --- | --- |
| fm | 63 von 74 im Lock: BSD-3 47, MIT 10, Apache-2.0 4, BSD-2 1, Engine 1 | 49: Apache-2.0 45, BSD-3 4 (io.flutter) | nichts |
| fmvt | 56 von 67: BSD-3 43, MIT 8, Apache-2.0 4, Engine 1 | 49 wie fm | nichts |
| ml | 44 von 44: BSD-3 36, MIT 5, Apache-2.0 2, Engine 1 | 58: Apache-2.0 52, BSD-3 4, BSD-2 2 (MapLibre android-sdk-opengl 13.7.1, gestures) | nichts |

Alle Lizenzen sind mit GPL-3.0 verträglich (BSD, MIT, Apache-2.0). „Engine“ = `sky_engine` mit der Sammel-LICENSE der Flutter-Engine (BSD-3 plus Dritte). Keine Google-Play-Services-Artefakte in `ml`.

### Netz statisch (`netstatic-20261108-001508`)
- **fm:** Netz-APIs in `flutter_map` (`TileLayer`, ungenutzt), `http`, `vector_map_tiles`; fest eingebaut `api.mapbox.com` (`vector_map_tiles`), `api.maptiler.com` (`vector_tile_renderer`), nur für ausdrücklich so geschriebene Stil-URLs.
- **fmvt:** `flutter_map_vector_tiles` (`NetworkVectorTileProvider`, `StyleReader`, Glyphen, PMTiles), `http`; `api.mapbox.com` nur für `mapbox://`-URLs. **Befund:** `StyleReader(httpClient: X)` ohne `resolveProvider` baut für die Kacheln einen `NetworkVectorTileProvider` mit eigenem `http.Client()` – Kacheln gehen dann am Tor vorbei (`style_reader.dart` ~Z. 427; Host-Test `bypass`: Tor sah style/tilejson/sprite/glyph, aber keine Kachel). Mit `resolveProvider` (eigener Provider mit dem Tor-Client) läuft alles über das Tor.
- **ml:** Netz nur nativ (`MapLibreHttpRequestUtil`, OkHttp); Konstanten `demotiles.maplibre.org`, `tiles.openfreemap.org` in `maplibre_gl` (Stil-Konstanten, `demotiles` nicht im AOT von ml), in `libmaplibre.so` `api.mapbox.com`, `api.maptiler.com`, `demotiles.maplibre.org` (URL-Schemata `mapbox://`, `maptiler://`), in `classes.dex` `apps.mapbox.com`, `www.mapbox.com` (Links der Attributions-Oberfläche). Telemetrie ist in MapLibre seit 9.4.0 entfernt.

### Host-Tests (`host-20261108-001527`, je 6/6 bestanden)
| Test | fm (gepatcht) | fmvt (Tor) | Gegenprobe Standardwerte |
| --- | --- | --- | --- |
| Anfragen über Hook/Tor | 12 Kacheln bereitgestellt, 12 verschlüsselt geschrieben | style 1, tilejson 1, sprite 2, glyph 3, tile 6, sonstige 2 (Rasterquelle `ne2_shaded`, 404) | – |
| Dateien außerhalb des verschlüsselten Speichers | 0 | 0 | fm ungepatcht: 12 Klartextdateien; fmvt Standard: 9 Dateien in `support/flutter_map_vector_tiles`, 12 Klartext-Treffer (PBF-Ebenennamen) |
| ohne Einwilligung | keine Anfrage, Linie ohne Karte | keine Anfrage, Linie ohne Karte | – |
| Miniatur am Host | 182 ms, 99 kB PNG | 480 × 240, 44,7 kB PNG (angesehen: Tempelhofer Feld, rote Runde korrekt) | – |

### Emulator API 36: Netz (`emu-20261108-003341`, Auswertung `eval.json`)
Mitschnitt geräteweit über das emulierte Mobilfunknetz (`eth0`), WLAN aus; Positivkontrolle `ping example.com` vor den Phasen im Mitschnitt gesehen. Gegenstellen zugeordnet über DNS-Antworten aus allen Mitschnitten des Laufs, SNI und Cloudflare-Adressbereiche. `tiles.openfreemap.org` löste auf 104.26.6.23, 104.26.7.23, 172.67.74.56 (und die IPv6-Gegenstücke in 2606:4700::/32) auf, alles Cloudflare; jede Cloudflare-Gegenstelle im Lauf außer der Positivkontrolle trägt diesen Namen per DNS und SNI.

| Phase (Dauer) | fm | fmvt | ml |
| --- | --- | --- | --- |
| ohne Einwilligung, Live (45 s) | kein Kartenhost, 0 Bytes Cloudflare | kein Kartenhost | kein Kartenhost |
| ohne Einwilligung, Historie (60 s) | kein Kartenhost | kein Kartenhost | kein Kartenhost |
| Live, erster Aufruf (120 s) | SNI/DNS nur tiles.openfreemap.org, 1,79 MB herein, App: 19 Anfragen, 2,72 MB | nur tiles.openfreemap.org, 1,57 MB, App: 17 Anfragen, 2,32 MB | nur tiles.openfreemap.org, 0,64 MB |
| Live, zweiter Aufruf (120 s, Kacheln schon gespeichert) | 0 Bytes, 0 Anfragen | 0 Bytes, 0 Anfragen | 0,64 MB (kein Kachelspeicher) |
| Miniaturen erzeugen | 10 Stück: 2,10 MB, 23 Anfragen | 10 Stück: 1,41 MB, 19 Anfragen | 50 Stück: **22,8 MB** |
| Miniaturen gespeichert anzeigen (60 s) | 0 Bytes | 0 Bytes | 1,02 MB (Fehler der Mini-App, siehe Zweifel) |
| Detailkarte (20 s) | 0,60 MB, 4 Anfragen | 0,27 MB, 6 Anfragen | 1,04 MB, beim zweiten Öffnen wieder 1,04 MB |
| fremde Hosts mit Einwilligung | keine | keine | **keine** (kein mapbox, maptiler, maplibre, keine App-Verbindung zu Google) |

„Herein“ = IP-Bytes von Cloudflare-Adressen im Mitschnitt; die App-Zahl zählt Antwortkörper nach dem Entpacken (gzip), daher größer. Neben den Kartenhosts stehen in fast allen Phasen, auch ohne App (`os-idle`: `www.google.com`, QUIC), dieselben Systemverbindungen: `www.google.com`, `infinitedata-pa.googleapis.com`, `digitalassetlinks.googleapis.com` und unaufgelöste Google-Adressen (zusammen 0,1–22 kB je Phase). Sie treten mit und ohne Einwilligung und in der Leerlaufphase der Apps auf und werden dem System zugeordnet; ein Mitschnitt je App (UID) liegt nicht vor.

### Emulator API 36: Speicher
| Scan | fm | fmvt | ml |
| --- | --- | --- | --- |
| nach den Phasen ohne Einwilligung | 0 Treffer; nur verschlüsselte Linien-Miniaturen | 0 Treffer | `mbgl-offline.db` (SQLite, leer: 0 Zeilen in `tiles`/`resources`) |
| nach den Phasen mit Einwilligung | 1 Treffer, Fehlalarm (s. u.); 21 verschlüsselte Kacheldateien 3,26 MB, 20 Miniaturen (10 Karte, 10 Linie) 0,66 MB | 0 Treffer; 42 verschlüsselte Kacheldateien 4,66 MB, 20 Miniaturen 0,72 MB | `mbgl-offline.db` leer (0 Zeilen), 50 verschlüsselte Miniaturen 2,0 MB |

Der eine fm-Treffer ist ein Zufall: Die Signatur `1f 8b 08` (gzip) steht mitten in einer 431-kB-Datei (Offset 264 528), die Entropie der Datei ist 8,00 Bit/Byte, Entpacken ab dort scheitert; bei 3,26 MB Zufallsbytes sind 3,26 MB / 2^24 ≈ 0,2 solcher Treffer zu erwarten. Der Treffer „sqlite“ bei ml ist die leere Cache-Datenbank, die MapLibre bei jedem Start anlegt (64 kB, nur Schema). Das ist die Antwort auf die Frage nach `bytes=234409`: Das ist die Summe aller gezogenen Dateien der Gegenprobe (vor allem `base.art` 168 kB und die leere `mbgl-offline.db` 64 kB), nicht eine Kachelmenge. Die Gegenproben im Emulator (fm/fmvt Klartext-Cache, ml Ambient-Cache an) haben **nicht gegriffen** (siehe Fehler im eigenen Aufbau); die Klartext-Gegenproben stehen nur am Host.

### Emulator API 36: Miniaturen, Live-Seite, Last
| Kennzahl | fm | fmvt | ml |
| --- | --- | --- | --- |
| Zeit je Miniatur erzeugen, Median (Spanne), n | 1515 ms (1214–1915), n = 10 | 1804 ms (1783–2535), n = 10 | 675 ms (348–1447), n = 50 |
| Größe je Miniatur (PNG, Median) | 64 kB | 72 kB | 41 kB |
| Linien-Miniatur ohne Einwilligung | 213 ms, 3,3 kB | 797 ms, 2,7 kB | – |
| Miniaturen gespeichert anzeigen: CPU | 0,08 % eines Kerns | 0,13 % | 0,15 % |
| Live-Seite: CPU der App (Mittel über 120 s, zwei Aufrufe) | 2,9 % / 2,9 % | 7,2 % / 7,3 % | 25,4 % / 28,2 % |
| Live-Seite: Flutter-Bilder je Sekunde (Mittel über 120 s) | 1,2 / 1,1 | 5,9 / 6,0 | 4,5 / 4,5 (nur Flutter-Ebene, die Karte selbst zeichnet nativ) |
| Live-Seite gezeichnet (Bildschirmfoto) | **nur Teil der Karte** (Kacheln rechts und unten fehlen, in beiden Aufrufen gleich) | vollständig | vollständig, Positionspunkt nicht sichtbar |
| Miniatur enthält die Route | ja | ja | **nein** (s. u.) |
| Leerlauf `/idle` | 0,08 % | 0,06 % | 0,05 % |

CPU = Ticks aus `/proc/<pid>/stat` (utime + stime, 100 Hz) über die Phase geteilt durch die Dauer. Die Position wandert mit 1 Hz; Bilder je Sekunde zeigt also die Zeichenlast, nicht die mögliche Bildrate (`dumpsys gfxinfo` zählt Flutter-Bilder nicht, 0 in allen Phasen).

Bildschirmfotos (verkleinert): [fm Live](figures/emu36-fm-live.jpg), [fmvt Live](figures/emu36-fmvt-live.jpg), [ml Live](figures/emu36-ml-live.jpg), [fmvt Miniaturen](figures/emu36-fmvt-thumbs.jpg), [ml Miniaturen ohne Route, mit eingebrannter Namensnennung](figures/emu36-ml-thumbs.jpg).

**ml-Snapshot:** `takeSnapshot` in `maplibre_gl` 0.28.0 (`MapLibreMapController.mapTakeSnapshot`) baut einen neuen `MapSnapshotter` mit der Stil-URL und der Kameraposition der Karte. Er rendert getrennt von der sichtbaren Karte: zur Laufzeit hinzugefügte Ebenen (die Route) fehlen, Stil und Kacheln werden erneut geladen (mit Ambient-Cache 0 aus dem Netz, daher 22,8 MB für 50 Miniaturen), und der Snapshotter brennt Logo/Namensnennung ins Bild.

### Emulator API 31: Start-Smoke (`emu-20261108-012618`)
Kommando `./run.sh emu --api 31 --apps "fm fmvt ml"`, Code-Stand `1a83f9c` plus die Korrekturen in `src/emu.sh` (Anführung der Route, force-stop, Flugmodus aus), 6 min. Ein erster Versuch `emu-20261108-012021` brach an der Positivkontrolle ab (`ping: unknown host`): Im AVD `running_app_api31` war der **Flugmodus an**, WLAN und Mobilfunk aus (Zustand aus früheren Läufen; mit `-read-only` nur in der Sitzung geändert). `emu.sh` schaltet ihn jetzt aus; danach Positivkontrolle ok.

| App (Live-Seite mit Einwilligung, 30 s) | Prozess läuft | Karte gezeichnet | Netz (Cloudflare herein, SNI) | App-Anfragen | CPU | Flutter-Bilder/s |
| --- | --- | --- | --- | --- | --- | --- |
| fm | ja | vollständig | 1,79 MB, nur tiles.openfreemap.org | 19, 2,72 MB | 7,2 % | 1,6 |
| fmvt | ja | vollständig | 1,57 MB, nur tiles.openfreemap.org | 16, 2,18 MB | 16,7 % | 5,5 |
| ml | ja | vollständig | 0,53 MB, nur tiles.openfreemap.org | – | 28,9 % | 4,8 |

Alle drei starten unter Android 12 (API 31) und zeigen die Karte; keine Abstürze, nur die bekannten harmlosen Impeller-Zeilen `EGL Error: Success`. Die CPU-Werte enthalten hier das Laden der Kacheln in den ersten 30 s und sind nicht mit den 120-s-Werten von API 36 vergleichbar. Im Leerlauf des API-31-Abbilds (vor jeder App) stehen Verbindungen zu `www.googleadservices.com`, `ad.doubleclick.net`, `adservice.google.com`, `youtubei.googleapis.com` – Systemverkehr des Google-APIs-Abbilds, der die Zuordnung des Google-Verkehrs zum System stützt.

### OpenFreeMap und Alternativen (Vorrecherche)
| Anbieter | Schlüssel/Konto | Bedingungen für Apps | Verfügbarkeit | Eignung |
| --- | --- | --- | --- | --- |
| OpenFreeMap | nein | Apps ausdrücklich erlaubt, keine Limits; automatisiertes Abrufen nur als Offline-Download (≤ 3000 Kacheln/50 MB, ≤ 4 parallel, eigener User-Agent); Einstellung jederzeit ohne Ankündigung möglich | Einzelperson (Hyperknot Software Kft.), Cloudflare-Sponsoring, kein SLA; Ausfälle 2025-02 (DNS, Issue #64), 2025-08 (Überlast), 2026-05 (403/CORS, #112/#113) | **Erstwahl** |
| VersaTiles | nein | frei, ohne Garantie | gemeinnützig, kein SLA | Ausweich |
| Protomaps PMTiles, selbst gehostet | eigener Speicher | eigene Kosten, ODbL | so gut wie das eigene Hosting | langfristige Ausweich-/Offline-Option |
| OSM France | nein | nicht kommerziell, schwache Garantie | – | nein |
| OpenTopoMap | nein | Raster, geringe Kapazität | – | nein |
| CARTO, Stadia, Thunderforest, MapTiler | ja | Konto/Schlüssel in der App | SLA je nach Tarif | nein (Schlüssel im öffentlichen Repo) |
| OSMF-Server (`tile.openstreetmap.org`) | – | laut Auftrag ausgeschlossen | – | – |

Datenschutz OpenFreeMap: keine IP-Adressen in Zugriffslogs, Fehlerlogs 7 Tage. Namensnennung: „OpenFreeMap © OpenMapTiles Data from OpenStreetMap“ (in den Mini-Apps auf Deutsch neben jeder Miniatur und auf der Karte). Kacheln werden wöchentlich neu erzeugt und sind versioniert; der Kachelpfad enthält ein Datum, daher Speicherschlüssel ohne Datumspfad (in `fmvt` so umgesetzt).

## Hinweise für WP13
1. **`resolveProvider` ist Pflicht:** `StyleReader(httpClient: tor, cache: false, resolveProvider: …)`, der Provider bekommt denselben Tor-Client. Ohne `resolveProvider` gehen die Kacheln am Tor vorbei. Ein Test im Gate muss das abdecken (Tor zählt `tile`-Anfragen > 0; Muster im Host-Test `bypass` von `fmvt`).
2. **Plattencache der Bibliothek aus:** `diskCacheMaximumSizeInBytes: 0` am Layer; mit Standardwerten schreibt `flutter_map_vector_tiles` PBF im Klartext nach `support/flutter_map_vector_tiles`. Gate-Test: nach einer Kartenansicht keine Datei außerhalb des verschlüsselten Speichers (Muster `scan_plain.py`).
3. **Speicher im Prozess:** `VectorTileLayer` hält einen prozessweiten Speicher-Cache; Tests müssen ihn je Test leeren (`clearMemoryCache()`), sonst verfälschen sie sich gegenseitig.
4. **Tor:** nur GET, nur https, nur die freigegebenen Hosts (Stil, TileJSON, Sprites, Glyphen, Kacheln); vor der Einwilligung keine Anfrage, auch nicht für Stil oder Sprites; ohne Einwilligung oder bei Netzfehler Linie ohne Karte. Rasterquellen im Stil (`ne2_shaded`, 404) sollten aus dem Stil entfernt werden.
5. **Miniaturen:** unsichtbare Karte außerhalb des Bildschirms, Ladeende = Netz 400 ms ruhig und zwei Bilder 250 ms auseinander pixelgleich (Zeitgrenze 15 s), dann `RepaintBoundary.toImage`, PNG verschlüsseln. 72 kB je Miniatur im Emulator, also ~3,6 MB für 50; ein kleineres Format (JPEG/WebP) prüfen. Erzeugen ~1,8 s je Miniatur im Emulator, deshalb nacheinander und nur einmal je Lauf, danach nur Bild.
6. **OpenFreeMap-Bedingungen:** kein Vorabladen ganzer Gebiete über die Grenzen der ToS, eigener User-Agent, Namensnennung sichtbar; Anbieter-URL zentral und austauschbar (Ausweichanbieter ohne Code-Änderung).
7. **Offen für WP13:** Live-Seite und Detailkarte auf einem echten Gerät (Bildrate, Akku), siehe Offene Punkte.

## Bewertung und Zweifel
- **Netz (belastbar):** Positivkontrolle im Mitschnitt, je Phase DNS, SNI und Gegenstellen; ohne Einwilligung bei keinem Kandidaten ein Kartenhost, mit Einwilligung nur `tiles.openfreemap.org`. Einschränkung: Der Mitschnitt ist geräteweit; Google-Verbindungen werden dem System zugeordnet, weil sie auch ohne App und ohne Einwilligung auftreten, nicht weil sie je App gemessen wurden. Eine App-Verbindung zu Google wäre davon nicht sicher zu trennen; statisch gibt es in keinem Kandidaten Google-Bibliotheken. DNS-Antworten sind im Gerät gecacht, deshalb fehlt der DNS-Eintrag in manchen Phasen; SNI steht in jeder Phase mit Kartenverkehr.
- **Speicher (belastbar für fmvt, am Host mit Gegenprobe):** Im Emulator 0 Klartext-Treffer bei fmvt. Die Klartext-Gegenproben im Emulator haben nicht gegriffen (Fehler unten); dass der Scan Klartext findet, ist nur am Host belegt (12 Treffer bzw. 12 Dateien). Der Scan sucht Signaturen (PBF-Ebenennamen, PNG, gzip, SQLite), verschlüsselte oder anders komprimierte Formate würde er nicht erkennen.
- **ml-Cache:** `mbgl-offline.db` blieb mit Ambient-Cache 0 leer (0 Zeilen). Dass MapLibre mit eingeschaltetem Ambient-Cache Kacheln im Klartext ablegt, stammt aus der Dokumentation (Quellen) und ist hier nicht gemessen.
- **Last und Bildrate (nur Rangfolge):** Emulator mit Software-GL auf dem Host; die GL-Arbeit fällt im Emulatorprozess an, nicht in der App, daher sind die App-CPU-Werte untere Schranken und nicht auf Geräte übertragbar. Je Wert ein Lauf von 120 s, zwei Aufrufe je App lagen nah beieinander (fm 2,91/2,92 %, fmvt 7,22/7,25 %, ml 25,4/28,2 %). fm ist auch deshalb billig, weil es nur einen Teil der Karte gezeichnet hat. Akku nicht gemessen.
- **fm-Darstellung:** Warum `vector_map_tiles` (gepatcht) auf der Live-Seite unter API 36 nach 125 s nur einen Teil zeichnete (in beiden Aufrufen gleich), ist nicht geklärt; die Detailkarte war vollständig, und im API-31-Smoke war die Live-Karte nach 35 s (andere Position auf der Route) vollständig. Möglich ist ein Fehler abhängig von Position bzw. Kachelgrenze. Ob der Patch oder die Bibliothek schuld ist, wurde nicht untersucht, weil fm ohnehin nicht empfohlen wird.
- **Miniaturen ungleich verglichen:** fm/fmvt erzeugten nur die 10 sichtbaren Miniaturen (kein automatisches Scrollen, Fehler unten), ml alle 50; bei fm/fmvt halfen schon gespeicherte Kacheln aus der Live-Phase (gleicher Park). Bytes je Miniatur sind deshalb nicht direkt vergleichbar; der Kern (ml lädt für jede Miniatur Stil und Kacheln neu) folgt aus dem Code und den 22,8 MB.

### Fehler im eigenen Aufbau (Lauf `emu-20261108-003341`)
1. **Route-Parameter abgeschnitten:** `adb shell am start … --es route "/x?a=1&b=2"` wird auf dem Gerät von einer Shell gelesen; `&` beendet dort den Befehl. Angekommen ist nur der erste Parameter (`consent`). Folgen: `page=0` (Werte-Seite) fehlte, die Phase „values“ war ein **zweiter Aufruf der Live-Karte** (oben so ausgewiesen); `auto=1` (automatisches Scrollen der Historie) fehlte, fm/fmvt erzeugten nur 10 Miniaturen; `plaincache=1` und `ambient=1` fehlten, die Gegenproben im Emulator liefen deshalb mit Standard-Tor bzw. Ambient-Cache 0 (Logs: `plain=false`, `ambient_cache=0`). Behoben in `src/emu.sh` (Route in einfachen Anführungszeichen für die Geräte-Shell); `consent` kam an, die Netz-Aussagen sind davon nicht betroffen.
2. **Apps liefen im Hintergrund weiter:** `launch` beendete nur die gerade gemessene App; fm und fmvt liefen bis Laufende mit (Logs: ihre `stats`-Zeilen mit unveränderten Zählern, `net_req=0`). Ihr Netz blieb still, ihre CPU zählt nicht in die gemessene PID, Speicherdruck ist möglich. Behoben in `src/emu.sh` (force-stop am Ende je App).
3. **ml-Historie lädt trotz gespeicherter Miniaturen:** Die Generator-Karte der Mini-App wird gebaut, bevor das Lesen der gespeicherten Bilder fertig ist (Log: `thumbs_loaded=50`, danach `MAP_DISPOSED`), daher 1,02 MB in der Phase „gespeichert“. Fehler der Mini-App, nicht der Bibliothek; nicht behoben (ml wird nicht empfohlen).

## Offene Punkte und Folgeanalysen
- **Ergänzungslauf (Rückfrage):** Mit der Korrektur in `src/emu.sh` ließen sich im Emulator nachholen: fmvt Historie mit 50 Miniaturen und Scrollen, Werte-Seite (Karte nicht sichtbar), Klartext-Gegenprobe; ml Ambient-Gegenprobe. Kostet ~15 bis 25 min und ~5–25 MB Kachelverkehr; laut Auftrag sind keine weiteren Kachelanfragen erlaubt.
- Bildrate, CPU und Akku der Live-Seite auf einem echten Gerät (Feldtest, nicht im Rahmen).
- Mitschnitt je App (UID) statt geräteweit, z. B. `dumpsys netstats detail` vor und nach jeder Phase.
- Ursache der unvollständigen fm-Live-Karte (nur falls `vector_map_tiles` doch in Frage kommt).
- Ausweichanbieter VersaTiles mit demselben Tor kurz im Emulator prüfen (Stil-Kompatibilität), bevor WP13 ihn als Rückfallebene einbaut.

## Quellen
- OpenFreeMap: https://openfreemap.org, Nutzungsbedingungen https://openfreemap.org/tos/, Datenschutz https://openfreemap.org/privacy/, https://openfreemap.org/quick_start/; Repository und Issues https://github.com/hyperknot/openfreemap (README, Issues #64, #112, #113); Betrieb https://hyperknot.com/blog/openfreemap-survived-100000-requests/; Stil-Lizenz https://github.com/hyperknot/openfreemap-styles (LICENSE.md).
- Alternativen: https://versatiles.org, https://protomaps.com/api, https://www.openstreetmap.fr/usage, https://opentopomap.org/about.
- MapLibre Native: CHANGELOG (Telemetrie entfernt 9.4.0), `OfflineManager.kt` (Ambient-Cache, `setMaximumAmbientCacheSize`), `HttpRequestUtil.java` (OkHttp) im Repository https://github.com/maplibre/maplibre-native; `maplibre_gl` 0.28.0 `MapLibreMapController.java` (`mapTakeSnapshot`) im Pub-Cache.
- `vector_map_tiles`: https://github.com/greensopinion/flutter-vector-map-tiles (README: „minimally maintained“); `flutter_map_vector_tiles`: https://pub.dev/packages/flutter_map_vector_tiles (Quellen 2.11.0, `style_reader.dart`).
- Cloudflare-Adressbereiche: https://www.cloudflare.com/ips/.
