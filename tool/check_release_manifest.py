#!/usr/bin/env python3
"""Rechte und Boot-Empfänger des Release-APK (ADR-0005 Punkt 6 mit Nachtrag WP22, ADR-0009).

Aufruf: check_release_manifest.py <permissions.txt> <xmltree.txt> <resources.txt> <xml-ordner>
  permissions.txt: Ausgabe von `aapt dump permissions <apk>`
  xmltree.txt:     Ausgabe von `aapt dump xmltree <apk> AndroidManifest.xml`
  resources.txt:   Ausgabe von `aapt dump --values resources <apk>` (löst Verweise wie @0x7f0e0000 auf Dateien auf)
  xml-ordner:      je Datei res/<x>.xml des APK die Ausgabe von `aapt dump xmltree <apk> res/<x>.xml`, abgelegt unter
                   dem Pfad im APK mit "/" durch "%" ersetzt (res%4j.xml)

Geprüft wird das gemergte Manifest im gebauten APK, nicht das Quell-Manifest (Plugins können per Merge Rechte und
Empfänger hinzufügen). Fail-closed: unlesbare oder unerwartete Ausgabe ist rot.

Regeln:
- Verboten: ACCESS_BACKGROUND_LOCATION (ADR-0005), SCHEDULE_EXACT_ALARM und USE_EXACT_ALARM (Erinnerungen nur inexakt).
- RECEIVE_BOOT_COMPLETED nur, wenn genau ein Empfänger auf einen Boot-Broadcast hört und das genau
  TrainingReminderReceiver ist, mit android:exported="false" (Entscheidung des Maintainers 2026-11-10: ein nicht
  exportierter Empfänger, der nur Erinnerungs-Wecker neu plant; ein Boot-Empfänger, der einen Dienst oder die
  Aufzeichnung startet, bleibt verboten).
- Ein Boot-Filter an einer anderen Komponente (Dienst, Activity, zweiter Empfänger) ist immer rot.
- Typ health (ADR-0005 Nachtrag WP25, K57; nur Laufbandmodus): Ein Dienst mit foregroundServiceType health braucht
  FOREGROUND_SERVICE_HEALTH und ACTIVITY_RECOGNITION. Das Recht FOREGROUND_SERVICE_HEALTH ist nur zusammen mit
  ACTIVITY_RECOGNITION erlaubt und nur, wenn der Aufzeichnungsdienst (RecordingService) den Typ health trägt, und zwar
  zusammen mit location (GPS-Läufe bleiben location). Kein anderer Dienst darf health tragen. Ein unlesbarer
  Diensttyp ist rot.
- Health Connect (ADR-0007 Punkt 2, WP32): genau die sechs Leserechte READ_EXERCISE, READ_HEART_RATE,
  READ_RESTING_HEART_RATE, READ_HEART_RATE_VARIABILITY, READ_SLEEP und READ_VO2_MAX, nichts darüber hinaus. Rot bei
  jedem WRITE_*-Recht, READ_HEALTH_DATA_IN_BACKGROUND, READ_HEALTH_DATA_HISTORY, jedem weiteren Recht unter
  android.permission.health. (auch aus einem Plugin) und bei jedem fehlenden der sechs.
- System-Backups aus (SEC-0010, ADR-0003 Punkt 3): android:allowBackup ist am application-Element ausdrücklich false.
  android:dataExtractionRules ist gesetzt; jede Datei, auf die der Verweis zeigt, hat die Abschnitte cloud-backup und
  device-transfer, beide ohne include und mit exclude ohne path für jede Domäne aus BACKUP_DOMAINS.
- Exportierte Komponenten (SEC-0009): Jede activity, activity-alias, service, receiver und provider, die nicht
  ausdrücklich exported=false ist und exported gesetzt oder einen intent-filter hat, muss in EXPORTED_ALLOWED stehen
  (Art, Name und, wo angegeben, das schützende Recht). Jede weitere ist rot.
- FileProvider (FR-0201, SEC-0009): Jeder provider mit FILE_PROVIDER_PATHS (oder der Klasse FileProvider) ist
  ausdrücklich exported=false, und jede Pfad-Datei gibt nur cache-path mit path="exports/" frei.
Der Selbsttest tool/check_release_manifest_test.py belegt jede Regel als rot."""
import os, re, sys

PACKAGE = "io.github.brokoskokoli.ramuri"
BOOT_RECEIVER = PACKAGE + ".TrainingReminderReceiver"
FORBIDDEN = (
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.USE_EXACT_ALARM",
)
HEALTH_PREFIX = "android.permission.health."
HEALTH_READ = frozenset(HEALTH_PREFIX + n for n in (
    "READ_EXERCISE", "READ_HEART_RATE", "READ_RESTING_HEART_RATE", "READ_HEART_RATE_VARIABILITY", "READ_SLEEP",
    "READ_VO2_MAX"))
BOOT_PERMISSION = "android.permission.RECEIVE_BOOT_COMPLETED"
RECORDING_SERVICE = PACKAGE + ".RecordingService"
HEALTH_SERVICE_PERMISSION = "android.permission.FOREGROUND_SERVICE_HEALTH"
ACTIVITY_PERMISSION = "android.permission.ACTIVITY_RECOGNITION"
# Domänen der Datensicherung (data-extraction-rules, Android 12+). Jede muss in beiden Abschnitten ganz ausgeschlossen sein.
BACKUP_DOMAINS = ("root", "file", "database", "sharedpref", "external", "device_root", "device_file", "device_database",
                  "device_sharedpref")
BACKUP_SECTIONS = ("cloud-backup", "device-transfer")
# Freigabeliste der exportierten Komponenten im gemergten Manifest: (Art, Name, verlangtes android:permission oder None).
# Startbildschirm, Health-Connect-Rationale (ADR-0007 Punkt 5) samt Alias und zwei Komponenten aus AndroidX-Bibliotheken
# (Bindungsdienst des Health-Connect-Clients, Profil-Empfänger nur mit dem Systemrecht DUMP).
EXPORTED_ALLOWED = (
    ("activity", PACKAGE + ".MainActivity", None),
    ("activity", PACKAGE + ".HealthRationaleActivity", None),
    ("activity-alias", PACKAGE + ".ViewPermissionUsageActivity", "android.permission.START_VIEW_PERMISSION_USAGE"),
    ("service", "androidx.health.platform.client.impl.sdkservice.HealthDataSdkService", None),
    ("receiver", "androidx.profileinstaller.ProfileInstallReceiver", "android.permission.DUMP"),
)
COMPONENTS = ("activity", "activity-alias", "service", "receiver", "provider")
FILE_PROVIDER_PATHS = "android.support.FILE_PROVIDER_PATHS"
FILE_PROVIDER_CLASS = "androidx.core.content.FileProvider"
# Erlaubte Freigaben einer Pfad-Datei des FileProviders: (Element, path).
FILE_PROVIDER_ALLOWED = (("cache-path", "exports/"),)
# ServiceInfo.FOREGROUND_SERVICE_TYPE_*
TYPE_LOCATION = 0x8
TYPE_HEALTH = 0x100

_ELEMENT = re.compile(r"^(\s*)E: (\S+) \(line=\d+\)$")
_RES_ENTRY = re.compile(r"^\s*resource (0x[0-9a-f]{8}) \S+: t=0x03 ")
_RES_FILE = re.compile(r'^\s*\(string8\) "([^"]+)"$')
_REF = re.compile(r"^@(0x[0-9a-f]{8})$")
_ATTR = re.compile(r"^(\s*)A: (?:([\w-]+):)?([\w-]+)(?:\(0x[0-9a-f]+\))?=(.*)$")


class Node:
    def __init__(self, tag, depth):
        self.tag, self.depth, self.attrs, self.children = tag, depth, {}, []

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def parse_tree(text, root_tag="manifest"):
    """Baut aus der Textausgabe von `aapt dump xmltree` einen Elementbaum (über die Einrückung)."""
    root, stack = None, []
    for line in text.splitlines():
        m = _ELEMENT.match(line)
        if m:
            node = Node(m.group(2), len(m.group(1)))
            while stack and stack[-1].depth >= node.depth:
                stack.pop()
            if stack:
                stack[-1].children.append(node)
            elif root is None:
                root = node
            else:
                raise ValueError("mehr als ein Wurzelelement")
            stack.append(node)
            continue
        m = _ATTR.match(line)
        if m and stack:
            stack[-1].attrs[m.group(3)] = m.group(4)
    if root is None or root.tag != root_tag:
        raise ValueError(f"kein {root_tag}-Element in der xmltree-Ausgabe")
    return root


def parse_resources(text):
    """Ordnet jeder Ressourcen-ID aus `aapt dump --values resources` die Dateien im APK zu (alle Konfigurationen)."""
    files, last = {}, None
    for line in text.splitlines():
        m = _RES_ENTRY.match(line)
        if m:
            last = m.group(1)
            continue
        m = _RES_FILE.match(line)
        if m and last:
            files.setdefault(last, []).append(m.group(1))
        last = None
    return files


def resolve_xml(raw, what, resources, xml_files, root_tag):
    """Liest die Dateien hinter einem Ressourcenverweis (@0x…) als Elementbäume. Fail-closed: (Bäume, Fehler)."""
    m = _REF.match(raw or "")
    if not m:
        return [], [f"{what}: kein lesbarer Ressourcenverweis ({raw})"]
    paths = resources.get(m.group(1))
    if not paths:
        return [], [f"{what}: Ressource {m.group(1)} nicht in der Ressourcentabelle"]
    trees, errors = [], []
    for path in paths:
        text = xml_files.get(path)
        if text is None:
            errors.append(f"{what}: {path} fehlt im APK")
            continue
        try:
            trees.append((path, parse_tree(text, root_tag)))
        except ValueError as e:
            errors.append(f"{what}: {path}: {e}")
    return trees, errors


def check_backup(app, resources, xml_files):
    """SEC-0010: allowBackup=false und data-extraction-rules schließen in beiden Abschnitten alle Domänen aus."""
    errors = []
    if not is_false(app.attrs.get("allowBackup")):
        errors.append("application: android:allowBackup ist nicht ausdrücklich false (SEC-0010)")
    raw = app.attrs.get("dataExtractionRules")
    if raw is None:
        return errors + ["application: android:dataExtractionRules fehlt (SEC-0010)"]
    trees, errs = resolve_xml(raw, "dataExtractionRules", resources, xml_files, "data-extraction-rules")
    errors += errs
    for path, root in trees:
        for section in BACKUP_SECTIONS:
            nodes = [c for c in root.children if c.tag == section]
            if len(nodes) != 1:
                errors.append(f"dataExtractionRules {path}: genau ein Abschnitt {section} erwartet, gefunden: "
                              f"{len(nodes)}")
                continue
            excluded = set()
            for rule in nodes[0].children:
                domain = string_value(rule.attrs.get("domain"))
                if rule.tag == "exclude" and "path" not in rule.attrs:
                    excluded.add(domain)
                elif rule.tag == "include":
                    errors.append(f"dataExtractionRules {path}: {section} enthält include (Domäne {domain})")
            for domain in BACKUP_DOMAINS:
                if domain not in excluded:
                    errors.append(f"dataExtractionRules {path}: {section} schließt die Domäne {domain} nicht ganz aus")
    return errors


def is_exported(comp):
    """Fail-closed: exportiert, sofern nicht ausdrücklich false und (exported gesetzt oder ein intent-filter da)."""
    raw = comp.attrs.get("exported")
    if is_false(raw):
        return False
    return raw is not None or any(c.tag == "intent-filter" for c in comp.children)


def check_exported(app):
    """SEC-0009: Nur die Komponenten aus EXPORTED_ALLOWED sind exportiert."""
    errors = []
    allowed = {(tag, name): perm for tag, name, perm in EXPORTED_ALLOWED}
    for comp in app.children:
        if comp.tag not in COMPONENTS or not is_exported(comp):
            continue
        name = string_value(comp.attrs.get("name"))
        key = (comp.tag, name)
        if key not in allowed:
            errors.append(f"{comp.tag} {name} ist exportiert und steht nicht in der Freigabeliste (SEC-0009)")
        elif allowed[key] is not None and string_value(comp.attrs.get("permission")) != allowed[key]:
            errors.append(f"{comp.tag} {name} ist exportiert ohne das Recht {allowed[key]}")
    return errors


def check_file_providers(app, resources, xml_files):
    """FileProvider nicht exportiert; Pfad-Dateien geben nur cacheDir/exports/ frei."""
    errors = []
    for comp in app.children:
        if comp.tag != "provider":
            continue
        name = string_value(comp.attrs.get("name"))
        paths_meta = [m for m in comp.children if m.tag == "meta-data"
                      and string_value(m.attrs.get("name")) == FILE_PROVIDER_PATHS]
        if not paths_meta and name != FILE_PROVIDER_CLASS:
            continue
        if not is_false(comp.attrs.get("exported")):
            errors.append(f"FileProvider {name} ist nicht ausdrücklich exported=false (SEC-0009)")
        if not paths_meta:
            errors.append(f"FileProvider {name}: {FILE_PROVIDER_PATHS} fehlt")
        for meta in paths_meta:
            trees, errs = resolve_xml(meta.attrs.get("resource"), f"FileProvider {name}", resources, xml_files,
                                      "paths")
            errors += errs
            for path, root in trees:
                if not root.children:
                    errors.append(f"FileProvider {name} {path}: keine Freigabe")
                for entry in root.children:
                    shared = (entry.tag, string_value(entry.attrs.get("path")))
                    if shared not in FILE_PROVIDER_ALLOWED:
                        errors.append(f"FileProvider {name} {path}: {entry.tag} path={shared[1]} ist nicht erlaubt "
                                      "(nur cache-path exports/)")
    return errors


def string_value(raw):
    m = re.match(r'^"([^"]*)"', raw or "")
    return m.group(1) if m else None


def is_false(raw):
    return raw is not None and re.fullmatch(r"\(type 0x12\)0x0", raw) is not None


def int_value(raw):
    """Ganzzahl aus `(type 0x11)0x108` (aapt-Ausgabe für Flags); None, wenn nicht lesbar."""
    m = re.fullmatch(r"\(type 0x1[0-9a-f]\)0x([0-9a-f]+)", raw or "")
    return int(m.group(1), 16) if m else None


def is_boot_action(name):
    return name is not None and (name.endswith("BOOT_COMPLETED") or "QUICKBOOT_POWERON" in name)


def check_health(perms, application):
    """Typ health und FOREGROUND_SERVICE_HEALTH nur zusammen, nur mit ACTIVITY_RECOGNITION, nur am Aufzeichnungsdienst."""
    errors = []
    health_services = []
    for comp in application.children:
        if comp.tag != "service":
            continue
        name = string_value(comp.attrs.get("name"))
        raw = comp.attrs.get("foregroundServiceType")
        if raw is None:
            continue
        types = int_value(raw)
        if types is None:
            errors.append(f"service {name}: foregroundServiceType nicht lesbar ({raw})")
            continue
        if types & TYPE_HEALTH:
            health_services.append((name, types))
    for name, types in health_services:
        if name != RECORDING_SERVICE:
            errors.append(f"Typ health an service {name} (nur der Aufzeichnungsdienst darf ihn tragen)")
        elif not types & TYPE_LOCATION:
            errors.append(f"{RECORDING_SERVICE} trägt health ohne location (GPS-Läufe starten mit location)")
        for p in (HEALTH_SERVICE_PERMISSION, ACTIVITY_PERMISSION):
            if p not in perms:
                errors.append(f"Typ health an service {name} ohne {p}")
    if HEALTH_SERVICE_PERMISSION in perms:
        if ACTIVITY_PERMISSION not in perms:
            errors.append(f"{HEALTH_SERVICE_PERMISSION} ohne {ACTIVITY_PERMISSION}")
        if not any(n == RECORDING_SERVICE for n, _ in health_services):
            errors.append(f"{HEALTH_SERVICE_PERMISSION} ohne Typ health am Aufzeichnungsdienst")
    return errors


def check_health_connect(perms):
    """Genau die sechs Health-Connect-Leserechte; kein Schreib-, Hintergrund- oder Verlaufsrecht, kein weiteres."""
    errors = []
    found = {p for p in perms if p.startswith(HEALTH_PREFIX)}
    for p in sorted(found - HEALTH_READ):
        name = p[len(HEALTH_PREFIX):]
        if name.startswith("WRITE_"):
            errors.append(f"Release-APK fordert das Health-Connect-Schreibrecht {p}")
        elif name in ("READ_HEALTH_DATA_IN_BACKGROUND", "READ_HEALTH_DATA_HISTORY"):
            errors.append(f"Release-APK fordert {p} (kein Hintergrundlesen, keine alten Daten)")
        else:
            errors.append(f"Release-APK fordert das unerwartete Health-Connect-Recht {p}")
    for p in sorted(HEALTH_READ - found):
        errors.append(f"Release-APK fordert das Health-Connect-Leserecht {p} nicht")
    return errors


def check(perms_text, tree_text, resources_text="", xml_files=None):
    errors = []
    if not re.search(r"^package: " + re.escape(PACKAGE) + r"$", perms_text, re.M):
        return ["aapt dump permissions: unerwartete Ausgabe (package-Zeile fehlt)"]
    perms = set(re.findall(r"^uses-permission(?:-sdk-23|-sdk-m)?: name='([^']+)'", perms_text, re.M))
    for p in FORBIDDEN:
        if p in perms:
            errors.append(f"Release-APK fordert {p}")
    errors += check_health_connect(perms)
    try:
        root = parse_tree(tree_text)
    except ValueError as e:
        return errors + [f"aapt dump xmltree: {e}"]
    apps = [n for n in root.children if n.tag == "application"]
    if len(apps) != 1:
        return errors + ["aapt dump xmltree: genau ein application-Element erwartet"]
    # Jede Komponente mit Boot-Filter, gleich welcher Art.
    boot = []
    for comp in apps[0].children:
        actions = [string_value(a.attrs.get("name")) for f in comp.children if f.tag == "intent-filter"
                   for a in f.children if a.tag == "action"]
        if any(a is None for a in actions):
            # Ressourcenverweis oder unlesbar: fail-closed, sonst könnte ein Boot-Filter unerkannt bleiben.
            errors.append(f"{comp.tag} {string_value(comp.attrs.get('name'))}: action ohne lesbaren Namen "
                          "(Ressourcenverweis?)")
        if any(is_boot_action(a) for a in actions):
            boot.append(comp)
    for comp in boot:
        name = string_value(comp.attrs.get("name"))
        if comp.tag != "receiver":
            errors.append(f"Boot-Filter an {comp.tag} {name} (nur der Erinnerungs-Empfänger darf ihn haben)")
        elif name != BOOT_RECEIVER:
            errors.append(f"Boot-Empfänger {name} ist nicht {BOOT_RECEIVER}")
        elif not is_false(comp.attrs.get("exported")):
            errors.append(f"{BOOT_RECEIVER} ist nicht ausdrücklich exported=false")
    receivers = [c for c in boot if c.tag == "receiver"]
    if BOOT_PERMISSION in perms:
        if len(receivers) != 1:
            errors.append(f"{BOOT_PERMISSION} verlangt genau einen Boot-Empfänger ({BOOT_RECEIVER}), "
                          f"gefunden: {len(receivers)}")
    elif boot:
        errors.append(f"Boot-Filter ohne {BOOT_PERMISSION}")
    errors += check_health(perms, apps[0])
    resources = parse_resources(resources_text)
    errors += check_backup(apps[0], resources, xml_files or {})
    errors += check_exported(apps[0])
    errors += check_file_providers(apps[0], resources, xml_files or {})
    same = [c for c in apps[0].children if string_value(c.attrs.get("name")) == BOOT_RECEIVER]
    if len(same) > 1:
        errors.append(f"{BOOT_RECEIVER} ist {len(same)}-mal deklariert")
    return errors


def main(argv):
    if len(argv) != 5:
        print(__doc__.splitlines()[2])
        return 2
    with open(argv[1], encoding="utf-8") as f:
        perms = f.read()
    with open(argv[2], encoding="utf-8") as f:
        tree = f.read()
    with open(argv[3], encoding="utf-8") as f:
        resources = f.read()
    xml_files = {}
    for entry in sorted(os.listdir(argv[4])):
        with open(os.path.join(argv[4], entry), encoding="utf-8") as f:
            xml_files[entry.replace("%", "/")] = f.read()
    errors = check(perms, tree, resources, xml_files)
    for e in errors:
        print(e)
    if not errors:
        print("Rechte und Boot-Empfänger in Ordnung (kein exakter Wecker, kein Hintergrundstandort, "
              f"Boot nur {BOOT_RECEIVER} exported=false); System-Backups aus, nur freigegebene Komponenten "
              "exportiert, FileProvider nur cache-path exports/")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
