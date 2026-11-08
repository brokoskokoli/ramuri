#!/usr/bin/env python3
"""Gate-Schritt "Netz nur im Kartenadapter" (SEC-0002, SEC-0008, ADR-0009). Aufruf: check_net.py [Repo-Wurzel].

Netz-APIs und die Kartenbibliotheken dürfen nur unter app/packages/adapters/lib/src/map/ vorkommen. Gesucht wird in
app/lib, app/packages/*/lib (Dart) und app/android (Kotlin, Java, Gradle). Fail-closed: Fehlt ein Suchpfad oder
liefert er keine Dateien, ist der Schritt rot; unlesbare Dateien sind rot. Kommentare werden vor der Suche entfernt.
Meldungen nennen nur Datei und Zeile, keinen Inhalt."""
import os, re, sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
ALLOWED = "app/packages/adapters/lib/src/map/"
ALLOWED_PUBSPEC = "app/packages/adapters/pubspec.yaml"  # nur hier dürfen Netz- und Kartenpakete stehen
SKIP_DIRS = {".dart_tool", "build", ".gradle", ".git", ".idea"}

DART = [
    (r"\b(HttpClient|HttpServer|HttpOverrides|Socket|RawSocket|SecureSocket|RawSecureSocket|ServerSocket|"
     r"RawServerSocket|RawDatagramSocket|WebSocket|NetworkImage)\b", "dart:io/Flutter-Netz-Klasse"),
    (r"\bImage\.network\b|\bInternetAddress\.lookup\b", "Netz-Aufruf"),
    (r"""\b(?:import|export)\s+['"](?:package:(?:http|http2|http_parser|dio|retrofit|chopper|web_socket|web_socket_channel|"""
     r"""socket_io_client|grpc|cronet_http|cupertino_http|flutter_map\w*|vector_map_tiles\w*|vector_tile_renderer|"""
     r"""maplibre\w*|mapbox\w*|latlong2|cached_network_image\w*|firebase\w*|sentry\w*|connectivity_plus|"""
     r"""internet_connection_checker\w*)\b|dart:(?:html|js_interop))""", "Netz- oder Kartenpaket"),
]
JVM = [
    (r"\b(HttpURLConnection|HttpsURLConnection|URLConnection|Socket|ServerSocket|SocketChannel|DatagramSocket|"
     r"OkHttpClient|WebSocket|DownloadManager|WebView)\b", "JVM-Netz-Klasse"),
    (r"\b(?:java\.net|javax\.net|okhttp3|okio|retrofit2?|io\.ktor|com\.android\.volley|android\.net\.http)\b", "JVM-Netz-Paket"),
    (r"\bURL\s*\(", "java.net.URL"),
]
GRADLE = [(r"okhttp|retrofit|volley|ktor|cronet|maplibre|mapbox", "Netz-Abhängigkeit in Gradle")]
PUBSPEC = [(r"^\s+(?:http|http2|dio|retrofit|chopper|web_socket\w*|socket_io_client|grpc|cronet_http|cupertino_http|"
            r"flutter_map\w*|vector_map_tiles\w*|vector_tile_renderer|maplibre\w*|mapbox\w*|cached_network_image\w*|"
            r"firebase\w*|sentry\w*):", "Netz- oder Kartenpaket in pubspec")]

def strip_c(t):
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S))

def walk(rel):
    base = os.path.join(root, rel)
    if not os.path.isdir(base):
        return None
    out = []
    for d, dn, fs in os.walk(base):
        dn[:] = [x for x in dn if x not in SKIP_DIRS]
        for f in fs:
            out.append(os.path.relpath(os.path.join(d, f), root).replace(os.sep, "/"))
    return sorted(out)

errors, scanned = [], 0
def scan(files, ext_rules):
    global scanned
    for rel in files:
        ext = os.path.splitext(rel)[1]
        base = os.path.basename(rel)
        rules = ext_rules(ext, base)
        if not rules:
            continue
        if os.path.islink(os.path.join(root, rel)):
            errors.append(f"{rel}: symbolischer Link in einem Suchpfad")
            continue
        scanned += 1
        if rel.startswith(ALLOWED) or rel == ALLOWED_PUBSPEC:
            continue
        try:
            text = open(os.path.join(root, rel), encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            errors.append(f"{rel}: nicht lesbar (fail-closed)")
            continue
        text = text if base == "pubspec.yaml" else strip_c(text)
        if base == "pubspec.yaml":
            text = re.sub(r"#[^\n]*", "", text)
        for pat, what in rules:
            for m in re.finditer(pat, text, re.M):
                errors.append(f"{rel}:{text.count(chr(10), 0, m.start()) + 1}: {what}")

dart_rules = lambda ext, base: DART if ext == ".dart" else (PUBSPEC if base == "pubspec.yaml" else None)
jvm_rules = lambda ext, base: JVM if ext in (".kt", ".java") else (GRADLE if base.endswith((".gradle", ".gradle.kts")) else None)

pk = walk("app/packages")
pkgs = sorted(p for p in (os.listdir(os.path.join(root, "app/packages")) if pk is not None else [])
              if os.path.isdir(os.path.join(root, "app/packages", p)))
if not pkgs:
    errors.append("app/packages/*: keine Pakete gefunden (fail-closed)")
for rel in ["app/lib", "app/android"] + ["app/packages/%s/lib" % p for p in pkgs]:
    files = walk(rel)
    before = scanned
    if files is None:
        errors.append(f"{rel}: Suchpfad fehlt (fail-closed)")
        continue
    scan(files, jvm_rules if rel == "app/android" else dart_rules)
    if scanned == before:
        errors.append(f"{rel}: keine prüfbaren Dateien gefunden (fail-closed)")
for rel in ["app/pubspec.yaml"] + ["app/packages/%s/pubspec.yaml" % p for p in pkgs]:
    if not os.path.isfile(os.path.join(root, rel)):
        errors.append(f"{rel}: fehlt (fail-closed)")
    else:
        scan([rel], dart_rules)
if not os.path.isdir(os.path.join(root, ALLOWED)):
    print("Hinweis: %s existiert noch nicht (erlaubter Ort für Netz-Code)" % ALLOWED)
if errors:
    print("Netz- oder Kartencode außerhalb von %s:" % ALLOWED)
    print("\n".join(errors[:60]))
    sys.exit(1)
print("%d Dateien geprüft, kein Netz-Code außerhalb von %s" % (scanned, ALLOWED))
