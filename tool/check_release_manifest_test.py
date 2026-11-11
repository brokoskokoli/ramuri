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
uses-permission: name='android.permission.POST_NOTIFICATIONS'
uses-permission: name='android.permission.RECEIVE_BOOT_COMPLETED'
uses-permission: name='android.permission.INTERNET'
"""


def a(depth, name, value):
    return " " * depth + f'A: android:{name}(0x01010003)={value}\n'


def s(v):
    return f'"{v}" (Raw: "{v}")'


FALSE, TRUE = "(type 0x12)0x0", "(type 0x12)0xffffffff"


def component(tag, name, exported=FALSE, actions=("android.intent.action.BOOT_COMPLETED",
                                                  "android.intent.action.MY_PACKAGE_REPLACED")):
    out = f"      E: {tag} (line=100)\n" + a(8, "name", s(name))
    if exported is not None:
        out += a(8, "exported", exported)
    if actions:
        out += "        E: intent-filter (line=101)\n"
        for act in actions:
            out += "          E: action (line=102)\n" + a(12, "name", s(act))
    return out


ACTIVITY = component("activity", PKG + ".MainActivity", TRUE,
                     ("android.intent.action.MAIN",))
SERVICE = component("service", PKG + ".RecordingService", FALSE, ())
PROFILE = component("receiver", "androidx.profileinstaller.ProfileInstallReceiver", TRUE,
                    ("androidx.profileinstaller.action.INSTALL_PROFILE",))
REMINDER = component("receiver", RECV)


def tree(*components):
    return ("N: android=http://schemas.android.com/apk/res/android\n"
            "  E: manifest (line=2)\n"
            f'    A: package={s(PKG)}\n'
            "    E: application (line=50)\n"
            + a(6, "name", s(PKG + ".RunningApplication"))
            + "".join(components))


BASE = (ACTIVITY, SERVICE, REMINDER, PROFILE)

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
    ("leere Rechte-Ausgabe", "", tree(*BASE), "unerwartete Ausgabe"),
    ("leere xmltree-Ausgabe", PERMS, "", "kein manifest-Element"),
]


def run(perms, xml):
    with tempfile.TemporaryDirectory() as d:
        p, t = os.path.join(d, "perms.txt"), os.path.join(d, "tree.txt")
        with open(p, "w", encoding="utf-8") as f:
            f.write(perms)
        with open(t, "w", encoding="utf-8") as f:
            f.write(xml)
        r = subprocess.run([sys.executable, CHECK, p, t], capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr


def main():
    failed = 0
    for name, perms, xml, expect in CASES:
        rc, out = run(perms, xml)
        ok = rc == 0 if expect is None else (rc == 1 and expect in out)
        print(("OK    " if ok else "FALSCH") + f" {name}" + ("" if ok else f" (rc={rc}): {out.strip()}"))
        failed += not ok
    print("Selbsttest grün" if not failed else f"Selbsttest rot: {failed} Fälle")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
