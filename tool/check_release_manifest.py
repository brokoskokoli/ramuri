#!/usr/bin/env python3
"""Rechte und Boot-Empfänger des Release-APK (ADR-0005 Punkt 6 mit Nachtrag WP22, ADR-0009).

Aufruf: check_release_manifest.py <permissions.txt> <xmltree.txt>
  permissions.txt: Ausgabe von `aapt dump permissions <apk>`
  xmltree.txt:     Ausgabe von `aapt dump xmltree <apk> AndroidManifest.xml`

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
Der Selbsttest tool/check_release_manifest_test.py belegt jede Regel als rot."""
import re, sys

PACKAGE = "io.github.brokoskokoli.ramuri"
BOOT_RECEIVER = PACKAGE + ".TrainingReminderReceiver"
FORBIDDEN = (
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.SCHEDULE_EXACT_ALARM",
    "android.permission.USE_EXACT_ALARM",
)
BOOT_PERMISSION = "android.permission.RECEIVE_BOOT_COMPLETED"
RECORDING_SERVICE = PACKAGE + ".RecordingService"
HEALTH_SERVICE_PERMISSION = "android.permission.FOREGROUND_SERVICE_HEALTH"
ACTIVITY_PERMISSION = "android.permission.ACTIVITY_RECOGNITION"
# ServiceInfo.FOREGROUND_SERVICE_TYPE_*
TYPE_LOCATION = 0x8
TYPE_HEALTH = 0x100

_ELEMENT = re.compile(r"^(\s*)E: (\S+) \(line=\d+\)$")
_ATTR = re.compile(r"^(\s*)A: (?:([\w-]+):)?([\w-]+)(?:\(0x[0-9a-f]+\))?=(.*)$")


class Node:
    def __init__(self, tag, depth):
        self.tag, self.depth, self.attrs, self.children = tag, depth, {}, []

    def walk(self):
        yield self
        for c in self.children:
            yield from c.walk()


def parse_tree(text):
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
    if root is None or root.tag != "manifest":
        raise ValueError("kein manifest-Element in der xmltree-Ausgabe")
    return root


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


def check(perms_text, tree_text):
    errors = []
    if not re.search(r"^package: " + re.escape(PACKAGE) + r"$", perms_text, re.M):
        return ["aapt dump permissions: unerwartete Ausgabe (package-Zeile fehlt)"]
    perms = set(re.findall(r"^uses-permission(?:-sdk-23|-sdk-m)?: name='([^']+)'", perms_text, re.M))
    for p in FORBIDDEN:
        if p in perms:
            errors.append(f"Release-APK fordert {p}")
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
    same = [c for c in apps[0].children if string_value(c.attrs.get("name")) == BOOT_RECEIVER]
    if len(same) > 1:
        errors.append(f"{BOOT_RECEIVER} ist {len(same)}-mal deklariert")
    return errors


def main(argv):
    if len(argv) != 3:
        print(__doc__.splitlines()[2])
        return 2
    with open(argv[1], encoding="utf-8") as f:
        perms = f.read()
    with open(argv[2], encoding="utf-8") as f:
        tree = f.read()
    errors = check(perms, tree)
    for e in errors:
        print(e)
    if not errors:
        print("Rechte und Boot-Empfänger in Ordnung (kein exakter Wecker, kein Hintergrundstandort, "
              f"Boot nur {BOOT_RECEIVER} exported=false)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
