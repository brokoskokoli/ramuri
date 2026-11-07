# Technische Verträge

**Status:** Draft. Die Quelle enthält keine Schemas, Endpunkte oder Versionsangaben. Dieses Dokument hält deshalb nur Bedarf und bekannte Festlegungen fest und erfindet keine Verträge.

| Schnittstelle | Festgelegt in der Quelle | Noch offen | Anforderungen |
|---|---|---|---|
| Dateiexport GPX, TCX, FIT | Die drei Formate; Inhalte je nach Format (Z. 1193–1205) | Vertrag (Vorschläge, OQ-0032): [file-export.md](file-export.md) | FR-0182, FR-0183 |
| Export von Zusatzmetriken | Separat exportierbar (Z. 1207) | Format (OQ-0032) | FR-0184 |
| Gesamtexport | Umfang: Historie, Einstellungen, berechnete Werte (Z. 1231); dokumentiertes Archiv mit Rohdaten und Reimport (OQ-0032) | Vertrag (Formatversion 1 bestätigt, Testvektoren folgen): [archive.md](archive.md) | FR-0192, FR-0198 |
| Bluetooth-Herzfrequenzgeräte | Standardisierte Geräte; die Quelle verweist auf den Heart Rate Service (Z. 76, 1438) | Profilversion; Felder für RR-Intervalle und Batterie | FR-0008, FR-0016, FR-0021 |
| Strava (zurückgestellt, OQ-0049) | Upload, Kontoverknüpfung, Statusanzeige, Duplikatvermeidung, Trennung; die Quelle verweist auf die Upload-API (Z. 1215–1221, 1437) | Datenformat, Berechtigungen, Anzahl der Wiederholungen | FR-0185 bis FR-0191 |
| Gesundheitsplattformen | Datenarten (Z. 117–122) | Abbildung der Daten; Google Health API zurückgestellt (OQ-0047) | FR-0022, FR-0023, FR-0200 |
| Ergänzende Uhrenanwendung | Nur als Möglichkeit genannt (Z. 78) | Erst Phase 4, noch nicht spezifiziert (OQ-0009) | FR-0009 |

Einen konkreten Vertrag erst anlegen, wenn die zugehörige Frage entschieden ist. Die gültige Fassung externer Spezifikationen ist bei der Umsetzung zu prüfen; die Links stehen in [references.md](../references.md).
