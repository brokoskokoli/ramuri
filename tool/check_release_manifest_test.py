#!/usr/bin/env python3
"""Selbsttest für tool/check_release_manifest.py.

Ein kleines Manifest im Format von `aapt dump xmltree` (wie im Release-APK) ist grün. Jeder Verstoß wird einzeln als
Abwandlung davon geprüft und muss rot sein, mit erwarteter Meldung. Wird eine Regel im Prüfskript entfernt oder
aufgeweicht, wird der zugehörige Fall grün und dieser Test rot."""
import os, subprocess, sys, tempfile

CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_release_manifest.py")
PKG = "io.github.brokoskokoli.ramuri"
RECV = PKG + ".TrainingReminderReceiver"

PERMS = f"""package: {PKG}
uses-permission: name='android.permission.ACCESS_FINE_LOCATION'
uses-permission: name='android.permission.ACTIVITY_RECOGNITION'
uses-permission: name='android.permission.FOREGROUND_SERVICE_HEALTH'
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'
uses-permission: name='android.permission.INTERNET'
""" + "".join(f"uses-permission: name='android.permission.health.{n}'\n" for n in (
    "READ_EXERCISE", "READ_HEART_RATE", "READ_RESTING_HEART_RATE", "READ_HEART_RATE_VARIABILITY", "READ_SLEEP",
    "READ_VO2_MAX"))


def a(depth, name, value):
    return " " * depth + f'A: android:{name}(0x01010003)={value}\n'


def s(v):
    return f'"{v}" (Raw: "{v}")'


FALSE, TRUE = "(type 0x12)0x0", "(type 0x12)0xffffffff"


def component(tag, name, exported=FALSE, actions=("android.intent.action.BOOT_COMPLETED",
                                                  "android.intent.action.MY_PACKAGE_REPLACED"), fgtype=None,
              permission=None, extra=""):
    out = f"      E: {tag} (line=100)\n" + a(8, "name", s(name))
    if exported is not None:
        out += a(8, "exported", exported)
    if permission is not None:
        out += a(8, "permission", s(permission))
    out += extra
    if fgtype is not None:
        out += a(8, "foregroundServiceType", fgtype)
    if actions:
        out += "        E: intent-filter (line=101)\n"
        for act in actions:
            out += "          E: action (line=102)\n" + a(12, "name", s(act))
    return out


ACTIVITY = component("activity", PKG + ".MainActivity", TRUE,
                     ("android.intent.action.MAIN",))
LOC, CONN, HEALTH = 0x8, 0x10, 0x100


def ftype(v):
    return f"(type 0x11)0x{v:x}"


SERVICE = component("service", PKG + ".RecordingService", FALSE, (), ftype(LOC | CONN | HEALTH))
PROFILE = component("receiver", "androidx.profileinstaller.ProfileInstallReceiver", TRUE,
                    ("androidx.profileinstaller.action.INSTALL_PROFILE",), permission="android.permission.DUMP")
REMINDER = component("receiver", RECV)
RATIONALE = component("activity", PKG + ".HealthRationaleActivity", TRUE,
                      ("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE",))
ALIAS = component("activity-alias", PKG + ".ViewPermissionUsageActivity", TRUE,
                  ("android.intent.action.VIEW_PERMISSION_USAGE",),
                  permission="android.permission.START_VIEW_PERMISSION_USAGE")
HC_SDK = component("service", "androidx.health.platform.client.impl.sdkservice.HealthDataSdkService", TRUE,
                   ("androidx.health.platform.client.ACTION_BIND_SDK_SERVICE",))

# Ressourcen: Verweise im Manifest, Ressourcentabelle (aapt dump --values resources) und die Dateien (umbenannt wie im
# Release-APK).
DER_REF, PATHS_REF = "@0x7f0e0000", "@0x7f0e0001"


def file_provider(exported=FALSE, ref=PATHS_REF, name="androidx.core.content.FileProvider", meta=True):
    extra = ""
    if meta:
        extra = ("        E: meta-data (line=110)\n" + a(10, "name", s("android.support.FILE_PROVIDER_PATHS"))
                 + a(10, "resource", ref))
    return component("provider", name, exported, (), extra=extra)


PROVIDER = file_provider()


def resources(entries=(("0x7f0e0000", "data_extraction_rules", "res/4j.xml"),
                       ("0x7f0e0001", "file_paths", "res/8K.xml"))):
    out = "Package Groups (1)\n  Package 0x7f name=" + PKG + "\n    type 13 configCount=1 entryCount=2\n"
    out += "      config (default):\n"
    for rid, name, path in entries:
        out += (f"        resource {rid} {PKG}:xml/{name}: t=0x03 d=0x00000000 (s=0x0008 r=0x00)\n"
                f'          (string8) "{path}"\n')
    return out


DOMAINS = ("root", "file", "database", "sharedpref", "external", "device_root", "device_file", "device_database",
           "device_sharedpref")


def xml_attr(depth, name, value):
    return " " * depth + f'A: {name}="{value}" (Raw: "{value}")\n'


def section(tag, rules):
    out = f"  E: {tag} (line=5)\n"
    for kind, domain, path in rules:
        out += f"    E: {kind} (line=6)\n" + xml_attr(6, "domain", domain)
        if path is not None:
            out += xml_attr(6, "path", path)
    return out


ALL_EXCLUDED = [("exclude", d, None) for d in DOMAINS]


def der(cloud=ALL_EXCLUDED, transfer=ALL_EXCLUDED):
    out = "E: data-extraction-rules (line=4)\n"
    if cloud is not None:
        out += section("cloud-backup", cloud)
    if transfer is not None:
        out += section("device-transfer", transfer)
    return out


def paths(*entries):
    out = "E: paths (line=4)\n"
    for tag, path in entries:
        out += f"  E: {tag} (line=5)\n" + xml_attr(4, "name", "exports") + xml_attr(4, "path", path)
    return out


XML = {"res/4j.xml": der(), "res/8K.xml": paths(("cache-path", "exports/"))}


def tree(*components, allow_backup=FALSE, der_ref=DER_REF):
    app = a(6, "name", s(PKG + ".RunningApplication"))
    if allow_backup is not None:
        app += a(6, "allowBackup", allow_backup)
    if der_ref is not None:
        app += a(6, "dataExtractionRules", der_ref)
    return ("N: android=http://schemas.android.com/apk/res/android\n"
            "  E: manifest (line=2)\n"
            f'    A: package={s(PKG)}\n'
            "    E: application (line=50)\n"
            + app
            + "".join(components))


BASE = (ACTIVITY, SERVICE, REMINDER, PROFILE, RATIONALE, ALIAS, HC_SDK, PROVIDER)


def xml(**changes):
    """XML-Dateien der Ausgangslage, einzelne ersetzt (None = Datei fehlt im APK)."""
    out = dict(XML)
    for key, value in changes.items():
        path = {"der": "res/4j.xml", "paths": "res/8K.xml"}[key]
        if value is None:
            del out[path]
        else:
            out[path] = value
    return out

# (Name, Rechte, xmltree, erwartete Meldung oder None für grün)
CASES = [
    ("Ausgangslage grün", PERMS, tree(*BASE), None),
    ("ohne Boot-Recht und ohne Boot-Empfänger grün",
     PERMS.replace("uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'\n", ""),
     tree(ACTIVITY, SERVICE, PROFILE), None),
    ("zweiter Boot-Empfänger", PERMS,
     tree(*BASE, component("receiver", "com.example.plugin.BootReceiver")), "ist nicht " + RECV),
    ("zweiter Boot-Empfänger gleichen Namens", PERMS,
     tree(*BASE, component("receiver", RECV)), "genau einen Boot-Empfänger"),
    ("exported=true", PERMS, tree(ACTIVITY, SERVICE, component("receiver", RECV, TRUE), PROFILE),
     "nicht ausdrücklich exported=false"),
    ("exported fehlt", PERMS, tree(ACTIVITY, SERVICE, component("receiver", RECV, None), PROFILE),
     "nicht ausdrücklich exported=false"),
    ("Recht ohne Empfänger", PERMS, tree(ACTIVITY, SERVICE, PROFILE), "gefunden: 0"),
    ("Empfänger ohne Boot-Filter, Recht gesetzt", PERMS,
     tree(ACTIVITY, SERVICE, component("receiver", RECV, FALSE, ("io.github.brokoskokoli.ramuri.TRAINING_REMINDER",)),
          PROFILE), "gefunden: 0"),
    ("anderer Klassenname", PERMS,
     tree(ACTIVITY, SERVICE, component("receiver", PKG + ".BootReceiver"), PROFILE), "ist nicht " + RECV),
    ("Boot-Filter an einem Dienst", PERMS,
     tree(*BASE, component("service", PKG + ".BootService")), "Boot-Filter an service"),
    ("LOCKED_BOOT_COMPLETED an anderem Empfänger", PERMS,
     tree(*BASE, component("receiver", "com.example.Other", FALSE, ("android.intent.action.LOCKED_BOOT_COMPLETED",))),
     "ist nicht " + RECV),
    ("Boot-Filter ohne Recht",
     PERMS.replace("uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'\n", ""),
     tree(*BASE), "Boot-Filter ohne"),
    ("SCHEDULE_EXACT_ALARM", PERMS + "uses-permission: name='android.permission.SCHEDULE_EXACT_ALARM'\n",
     tree(*BASE), "SCHEDULE_EXACT_ALARM"),
    ("USE_EXACT_ALARM", PERMS + "uses-permission: name='android.permission.USE_EXACT_ALARM'\n",
     tree(*BASE), "USE_EXACT_ALARM"),
    ("ACCESS_BACKGROUND_LOCATION", PERMS + "uses-permission: name='android.permission.ACCESS_BACKGROUND_LOCATION'\n",
     tree(*BASE), "ACCESS_BACKGROUND_LOCATION"),
    ("SCHEDULE_EXACT_ALARM als sdk-23",
     PERMS + "uses-permission-sdk-23: name='android.permission.SCHEDULE_EXACT_ALARM'\n", tree(*BASE),
     "SCHEDULE_EXACT_ALARM"),
    ("USE_EXACT_ALARM als sdk-m",
     PERMS + "uses-permission-sdk-m: name='android.permission.USE_EXACT_ALARM'\n", tree(*BASE), "USE_EXACT_ALARM"),
    ("ACCESS_BACKGROUND_LOCATION als sdk-23",
     PERMS + "uses-permission-sdk-23: name='android.permission.ACCESS_BACKGROUND_LOCATION'\n", tree(*BASE),
     "ACCESS_BACKGROUND_LOCATION"),
    ("Action als Ressourcenverweis", PERMS,
     tree(ACTIVITY, SERVICE, PROFILE, REMINDER.replace(s("android.intent.action.BOOT_COMPLETED"), "@0x7f0a0001")),
     "action ohne lesbaren Namen"),
    # Typ health (ADR-0005 Nachtrag WP25)
    ("Aufzeichnungsdienst ohne health, ohne Recht und ohne ACTIVITY_RECOGNITION grün (nur GPS)",
     PERMS.replace("uses-permission: name='android.permission.FOREGROUND_SERVICE_HEALTH'\n", "")
     .replace("uses-permission: name='android.permission.ACTIVITY_RECOGNITION'\n", ""),
     tree(component("service", PKG + ".RecordingService", FALSE, (), ftype(LOC | CONN)), ACTIVITY, REMINDER, PROFILE),
     None),
    ("health ohne FOREGROUND_SERVICE_HEALTH",
     PERMS.replace("uses-permission: name='android.permission.FOREGROUND_SERVICE_HEALTH'\n", ""), tree(*BASE),
     "ohne android.permission.FOREGROUND_SERVICE_HEALTH"),
    ("health ohne ACTIVITY_RECOGNITION",
     PERMS.replace("uses-permission: name='android.permission.ACTIVITY_RECOGNITION'\n", ""), tree(*BASE),
     "Typ health an service " + PKG + ".RecordingService ohne android.permission.ACTIVITY_RECOGNITION"),
    ("FOREGROUND_SERVICE_HEALTH ohne ACTIVITY_RECOGNITION",
     PERMS.replace("uses-permission: name='android.permission.ACTIVITY_RECOGNITION'\n", ""),
     tree(*BASE), "FOREGROUND_SERVICE_HEALTH ohne android.permission.ACTIVITY_RECOGNITION"),
    ("FOREGROUND_SERVICE_HEALTH ohne Typ health am Aufzeichnungsdienst", PERMS,
     tree(component("service", PKG + ".RecordingService", FALSE, (), ftype(LOC | CONN)), ACTIVITY, REMINDER, PROFILE),
     "ohne Typ health am Aufzeichnungsdienst"),
    ("FOREGROUND_SERVICE_HEALTH ohne foregroundServiceType am Dienst", PERMS,
     tree(component("service", PKG + ".RecordingService", FALSE, ()), ACTIVITY, REMINDER, PROFILE),
     "ohne Typ health am Aufzeichnungsdienst"),
    ("health an einem anderen Dienst", PERMS,
     tree(*BASE, component("service", "com.example.OtherService", FALSE, (), ftype(HEALTH))),
     "Typ health an service com.example.OtherService"),
    ("Aufzeichnungsdienst mit health ohne location", PERMS,
     tree(component("service", PKG + ".RecordingService", FALSE, (), ftype(HEALTH | CONN)), ACTIVITY, REMINDER,
          PROFILE), "health ohne location"),
    ("foregroundServiceType als Ressourcenverweis", PERMS,
     tree(component("service", PKG + ".RecordingService", FALSE, (), "@0x7f0a0001"), ACTIVITY, REMINDER, PROFILE),
     "foregroundServiceType nicht lesbar"),
    # Health Connect (ADR-0007, WP32)
    ("Health Connect: Schreibrecht", PERMS + "uses-permission: name='android.permission.health.WRITE_SLEEP'\n",
     tree(*BASE), "Schreibrecht android.permission.health.WRITE_SLEEP"),
    ("Health Connect: Schreibrecht als sdk-23",
     PERMS + "uses-permission-sdk-23: name='android.permission.health.WRITE_EXERCISE'\n", tree(*BASE),
     "Schreibrecht android.permission.health.WRITE_EXERCISE"),
    ("Health Connect: Hintergrundlesen",
     PERMS + "uses-permission: name='android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND'\n", tree(*BASE),
     "READ_HEALTH_DATA_IN_BACKGROUND"),
    ("Health Connect: alte Daten",
     PERMS + "uses-permission: name='android.permission.health.READ_HEALTH_DATA_HISTORY'\n", tree(*BASE),
     "READ_HEALTH_DATA_HISTORY"),
    ("Health Connect: weiteres Leserecht (Plugin)",
     PERMS + "uses-permission: name='android.permission.health.READ_STEPS'\n", tree(*BASE),
     "unerwartete Health-Connect-Recht android.permission.health.READ_STEPS"),
    ("Health Connect: Leserecht fehlt",
     PERMS.replace("uses-permission: name='android.permission.health.READ_VO2_MAX'\n", ""), tree(*BASE),
     "Leserecht android.permission.health.READ_VO2_MAX nicht"),
    ("Health Connect: gar keine Rechte", "".join(l + "\n" for l in PERMS.splitlines() if ".health.READ_" not in l),
     tree(*BASE), "READ_EXERCISE nicht"),
    ("leere Rechte-Ausgabe", "", tree(*BASE), "unerwartete Ausgabe"),
    ("leere xmltree-Ausgabe", PERMS, "", "kein manifest-Element"),
    # System-Backups (SEC-0010)
    ("allowBackup fehlt", PERMS, tree(*BASE, allow_backup=None), "allowBackup ist nicht ausdrücklich false"),
    ("allowBackup=true", PERMS, tree(*BASE, allow_backup=TRUE), "allowBackup ist nicht ausdrücklich false"),
    ("allowBackup als Ressourcenverweis", PERMS, tree(*BASE, allow_backup="@0x7f050000"),
     "allowBackup ist nicht ausdrücklich false"),
    ("dataExtractionRules fehlt", PERMS, tree(*BASE, der_ref=None), "dataExtractionRules fehlt"),
    ("dataExtractionRules kein Verweis", PERMS, tree(*BASE, der_ref=s("res/xml/x.xml")),
     "dataExtractionRules: kein lesbarer Ressourcenverweis"),
    ("dataExtractionRules: Ressource nicht in der Tabelle", PERMS, tree(*BASE, der_ref="@0x7f0e0009"),
     "Ressource 0x7f0e0009 nicht in der Ressourcentabelle"),
    ("dataExtractionRules: Datei fehlt im APK", PERMS, tree(*BASE), "res/4j.xml fehlt im APK",
     resources(), xml(der=None)),
    ("dataExtractionRules: andere Wurzel", PERMS, tree(*BASE), "kein data-extraction-rules-Element",
     resources(), xml(der=paths(("cache-path", "exports/")))),
] + [
    (f"dataExtractionRules: {sec} erlaubt die Domäne {d}", PERMS, tree(*BASE),
     f"{sec} schließt die Domäne {d} nicht ganz aus", resources(),
     xml(der=der(**{key: [r for r in ALL_EXCLUDED if r[1] != d]})))
    for sec, key in (("cloud-backup", "cloud"), ("device-transfer", "transfer")) for d in DOMAINS
] + [
    ("dataExtractionRules: cloud-backup fehlt", PERMS, tree(*BASE), "genau ein Abschnitt cloud-backup",
     resources(), xml(der=der(cloud=None))),
    ("dataExtractionRules: device-transfer fehlt", PERMS, tree(*BASE), "genau ein Abschnitt device-transfer",
     resources(), xml(der=der(transfer=None))),
    ("dataExtractionRules: include", PERMS, tree(*BASE), "cloud-backup enthält include (Domäne file)",
     resources(), xml(der=der(cloud=ALL_EXCLUDED + [("include", "file", None)]))),
    ("dataExtractionRules: exclude nur eines Pfads", PERMS, tree(*BASE),
     "device-transfer schließt die Domäne database nicht ganz aus", resources(),
     xml(der=der(transfer=[r if r[1] != "database" else ("exclude", "database", "app.db") for r in ALL_EXCLUDED]))),
    ("dataExtractionRules: zweite Konfiguration erlaubt eine Domäne", PERMS, tree(*BASE),
     "res/4j-v31.xml: cloud-backup schließt die Domäne root nicht ganz aus",
     resources() + "      config v31:\n" + resources(((("0x7f0e0000", "data_extraction_rules", "res/4j-v31.xml"),))
                                                ).split("config (default):\n")[1],
     dict(xml(), **{"res/4j-v31.xml": der(cloud=ALL_EXCLUDED[1:])})),
    # Exportierte Komponenten (SEC-0009)
    ("zusätzliche exportierte Activity", PERMS,
     tree(*BASE, component("activity", PKG + ".ShareActivity", TRUE, ())), "activity " + PKG + ".ShareActivity ist exportiert"),
    ("zusätzlicher exportierter Dienst aus Plugin", PERMS,
     tree(*BASE, component("service", "com.example.plugin.SyncService", TRUE, ())),
     "service com.example.plugin.SyncService ist exportiert"),
    ("zusätzlicher exportierter Provider", PERMS,
     tree(*BASE, component("provider", "com.example.plugin.DataProvider", TRUE, ())),
     "provider com.example.plugin.DataProvider ist exportiert"),
    ("Empfänger mit intent-filter ohne exported", PERMS,
     tree(*BASE, component("receiver", "com.example.plugin.Receiver", None, ("com.example.ACTION",))),
     "receiver com.example.plugin.Receiver ist exportiert"),
    ("exported als Ressourcenverweis", PERMS,
     tree(*BASE, component("activity", PKG + ".OtherActivity", "@0x7f050001", ())),
     "activity " + PKG + ".OtherActivity ist exportiert"),
    ("freigegebener Name mit anderer Art", PERMS,
     tree(*BASE, component("service", PKG + ".MainActivity", TRUE, ())), "service " + PKG + ".MainActivity ist exportiert"),
    ("Alias ohne schützendes Recht", PERMS,
     tree(ACTIVITY, SERVICE, REMINDER, PROFILE, RATIONALE, HC_SDK, PROVIDER,
          component("activity-alias", PKG + ".ViewPermissionUsageActivity", TRUE,
                    ("android.intent.action.VIEW_PERMISSION_USAGE",))),
     "ViewPermissionUsageActivity ist exportiert ohne das Recht android.permission.START_VIEW_PERMISSION_USAGE"),
    ("Profil-Empfänger ohne DUMP", PERMS,
     tree(ACTIVITY, SERVICE, REMINDER, RATIONALE, ALIAS, HC_SDK, PROVIDER,
          component("receiver", "androidx.profileinstaller.ProfileInstallReceiver", TRUE,
                    ("androidx.profileinstaller.action.INSTALL_PROFILE",))),
     "ProfileInstallReceiver ist exportiert ohne das Recht android.permission.DUMP"),
    ("Komponente ohne exported und ohne intent-filter grün", PERMS,
     tree(*BASE, component("service", "com.example.plugin.InternalService", None, ())), None),
    # FileProvider (FR-0201, SEC-0009)
    ("FileProvider exportiert", PERMS,
     tree(ACTIVITY, SERVICE, REMINDER, PROFILE, RATIONALE, ALIAS, HC_SDK, file_provider(TRUE)),
     "FileProvider androidx.core.content.FileProvider ist nicht ausdrücklich exported=false"),
    ("FileProvider ohne exported", PERMS,
     tree(ACTIVITY, SERVICE, REMINDER, PROFILE, RATIONALE, ALIAS, HC_SDK, file_provider(None)),
     "FileProvider androidx.core.content.FileProvider ist nicht ausdrücklich exported=false"),
    ("FileProvider ohne Pfad-Datei", PERMS,
     tree(ACTIVITY, SERVICE, REMINDER, PROFILE, RATIONALE, ALIAS, HC_SDK, file_provider(meta=False)),
     "FILE_PROVIDER_PATHS fehlt"),
    ("FileProvider: anderer Pfad", PERMS, tree(*BASE), "cache-path path=. ist nicht erlaubt", resources(),
     xml(paths=paths(("cache-path", ".")))),
    ("FileProvider: files-path", PERMS, tree(*BASE), "files-path path=exports/ ist nicht erlaubt", resources(),
     xml(paths=paths(("files-path", "exports/")))),
    ("FileProvider: zusätzliche Freigabe", PERMS, tree(*BASE), "root-path path=/ ist nicht erlaubt", resources(),
     xml(paths=paths(("cache-path", "exports/"), ("root-path", "/")))),
    ("FileProvider: leere Pfad-Datei", PERMS, tree(*BASE), "keine Freigabe", resources(), xml(paths=paths())),
    ("FileProvider: Pfad-Datei fehlt im APK", PERMS, tree(*BASE), "res/8K.xml fehlt im APK", resources(),
     xml(paths=None)),
    ("zweiter FileProvider aus Plugin, exportiert", PERMS,
     tree(*BASE, file_provider(TRUE, name="com.example.plugin.ShareFileProvider")),
     "FileProvider com.example.plugin.ShareFileProvider ist nicht ausdrücklich exported=false"),
    ("zweiter FileProvider aus Plugin mit eigenem Pfad", PERMS,
     tree(*BASE, file_provider(name="com.example.plugin.ShareFileProvider", ref="@0x7f0e0005")),
     "FileProvider com.example.plugin.ShareFileProvider res/9z.xml: external-path path=. ist nicht erlaubt",
     resources(((("0x7f0e0000", "data_extraction_rules", "res/4j.xml"), ("0x7f0e0001", "file_paths", "res/8K.xml"),
                 ("0x7f0e0005", "plugin_paths", "res/9z.xml")))),
     dict(xml(), **{"res/9z.xml": paths(("external-path", "."))})),
]


def run(perms, manifest, res_text, xml_files):
    with tempfile.TemporaryDirectory() as d:
        p, t, r = (os.path.join(d, n) for n in ("perms.txt", "tree.txt", "resources.txt"))
        xdir = os.path.join(d, "xml")
        os.mkdir(xdir)
        for path, content in [(p, perms), (t, manifest), (r, res_text)] + [
                (os.path.join(xdir, k.replace("/", "%")), v) for k, v in xml_files.items()]:
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
        proc = subprocess.run([sys.executable, CHECK, p, t, r, xdir], capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr


def main():
    failed = 0
    for case in CASES:
        name, perms, manifest, expect = case[:4]
        res_text, xml_files = case[4:] if len(case) > 4 else (resources(), XML)
        rc, out = run(perms, manifest, res_text, xml_files)
        ok = rc == 0 if expect is None else (rc == 1 and expect in out)
        print(("OK    " if ok else "FALSCH") + f" {name}" + ("" if ok else f" (rc={rc}): {out.strip()}"))
        failed += not ok
    print("Selbsttest grün" if not failed else f"Selbsttest rot: {failed} Fälle")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
