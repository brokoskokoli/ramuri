#!/usr/bin/env python3
"""Gate-Schritt "Netz nur im Kartenadapter" (SEC-0002, SEC-0008, ADR-0009). Aufruf: check_net.py [Repo-Wurzel].

Fail-closed, Freigabeliste statt Sperrliste:
- Jedes Paket aus app/pubspec.lock (auch transitiv), jede direkte Abhängigkeit aller pubspec.yaml sowie jede
  Gradle-Abhängigkeit und jedes Gradle-Plugin muss in tool/net_allowed_packages.txt stehen, mit Netz-Einordnung.
  Neue Einträge sind rot, bis jemand das Paket auf Netzfähigkeit geprüft und eingetragen hat.
- Dart-Direktiven (import, export) werden mit einem kleinen Lexer gelesen (Kommentare und Zeichenketten bewusst);
  jede URI wird geprüft. Netz-APIs im Quelltext, Kartenpakete und src/map/* sind nur im Kartenadapter
  (app/packages/adapters/lib/src/map/) erlaubt. map_testing.dart darf aus keinem Produktivcode kommen.
- Suchpfade: app/ (ohne test, integration_test, build, coverage, assets) und app/packages/* (ohne test, build).
  Fehlende oder leere Suchpfade, unlesbare Dateien, Symlinks und unbekannte Binärdateien sind rot.
Meldungen nennen nur Datei und Zeile, keinen Inhalt."""
import os, re, sys

root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
ALLOWED = "app/packages/adapters/lib/src/map/"
ADAPTERS_LIB = "app/packages/adapters/lib/"
MAP_TESTING = ADAPTERS_LIB + "map_testing.dart"
ADAPTERS_EXPORT = ADAPTERS_LIB + "adapters.dart"
LIST_FILE = "tool/net_allowed_packages.txt"
CLASSES = {"kein-netz", "nur-karte", "nur-entwicklung", "sdk"}

APP_SKIP = {"test", "integration_test", "build", "coverage", "assets", "packages", ".dart_tool"}
PKG_SKIP = {"test", "build", ".dart_tool", "drift_schemas"}
# Erzeugte Ordner nur an diesen genauen Stellen auslassen (nie als Namensmuster, sonst versteckt sich Code darin).
GENERATED = {"app/android/build", "app/android/app/build", "app/android/.gradle"}
BINARY_EXT = {".so", ".aar", ".jar", ".a", ".dylib", ".dll", ".framework", ".jnilib", ".wasm", ".apk", ".aab", ".o"}
BINARY_OK = {"app/android/gradle/wrapper/gradle-wrapper.jar"}

DART_OK = {"core", "async", "collection", "convert", "math", "typed_data", "io", "isolate", "ui", "developer"}
WEB_NAMES = {"html", "js", "js_interop", "js_interop_unsafe", "js_util", "web_audio", "web_gl", "indexed_db", "svg", "ffi"}

DART_API = [
    (r"\b(HttpClient\w*|HttpServer|HttpOverrides|HttpRequest|XMLHttpRequest|Socket|RawSocket|SecureSocket|"
     r"RawSecureSocket|ServerSocket|RawServerSocket|RawDatagramSocket|RawSynchronousSocket|WebSocket|NetworkImage|"
     r"NetworkAssetBundle|InternetAddress|NetworkInterface|ConnectivityResult|Dio)\b", "Netz-Klasse"),
    (r"\bImage\s*\.\s*network\b|\bNetworkImage\b", "Netz-Aufruf (Image.network)"),
]
JVM_API = [
    (r"\b(HttpURLConnection|HttpsURLConnection|URLConnection|Socket|ServerSocket|SocketChannel|DatagramSocket|"
     r"DatagramChannel|ServerSocketChannel|AsynchronousSocketChannel|OkHttpClient|WebSocket|DownloadManager|WebView|"
     r"WebViewClient|InetAddress|Inet4Address|Inet6Address|SocketFactory|socketFactory|CronetEngine|NetworkRequest|"
     r"NetworkCapabilities|ConnectivityManager|ProcessBuilder)\b", "JVM-Netz-Klasse"),
    (r"\b(?:java\.net|javax\.net|okhttp3|okio|retrofit2?|io\.ktor|com\.android\.volley|android\.net\.http|"
     r"com\.google\.firebase|io\.sentry|com\.bumptech)\b", "JVM-Netz-Paket"),
    (r"\bURL\s*\(", "java.net.URL"),
    (r"\bgetRuntime\s*\(\s*\)\s*\.\s*exec\b", "Prozessstart"),
]
NATIVE_API = [
    (r"#\s*include\s*[<\"](?:sys/socket|sys/un|netinet|arpa/inet|netdb|curl/|openssl/|ifaddrs|net/if)", "natives Netz-Include"),
    (r"\b(?:socket|connect|getaddrinfo|gethostbyname|sendto|recvfrom|curl_\w+)\s*\(|"
     r"\b(?:NSURLSession\w*|NSURLConnection|URLSession\w*|CFNetwork\w*|CFStream\w*|nw_connection\w*)\b", "natives Netz-Aufruf"),
]
GRADLE_RISK = [
    (r"\b(?:versionCatalogs|flatDir|fileTree|dependencySubstitution)\b", "Gradle: Quelle außerhalb der Freigabeliste"),
    (r"\bmaven\s*[({]|\bivy\s*[({]|\buri\s*\(|\burl\s*[=(]", "Gradle: eigenes Repository"),
    (r"\bfiles\s*\(", "Gradle: lokale Datei als Abhängigkeit"),
    (r"\bapply\s*(?:\(\s*)?from\b|\bfrom\s*\(\s*files\b", "Gradle: fremdes Skript"),
]
COORD = re.compile(r"^[A-Za-z0-9_.\-]+:[A-Za-z0-9_.\-]+(?::[^:\s]*)?(?:@\w+)?$")
HINT = ("Neues Paket, neue Gradle-Abhängigkeit oder neue Netz-Schnittstelle: zuerst den Quelltext auf Netzfähigkeit prüfen "
        "(dart:io HttpClient/Socket, package:http, web_socket, java.net, okhttp, native Sockets), dann in %s mit Einordnung "
        "eintragen (kein-netz, nur-karte, nur-entwicklung, sdk). Netz gehört nur nach %s." % (LIST_FILE, ALLOWED))

errors = []
def err(rel, line, msg):
    errors.append(f"{rel}:{line}: {msg}" if line else f"{rel}: {msg}")

# --- Lexer -------------------------------------------------------------------------------------------------
PH = re.compile(r"\x01(\d+)\x02")

def lex(text, rel, nested=True, interp=True):
    """Entfernt Kommentare, ersetzt Zeichenketten durch Platzhalter \\x01N\\x02 (Inhalt in strs[N]).
    Zeilenumbrüche bleiben erhalten. Rückgabe: (code, strs). Unterminierte Block-Kommentare oder
    Dreifach-Strings sind rot."""
    code, strs = [], []
    t, n, i, line = text, len(text), 0, 1
    stack, depth = [], 0
    ctx = None  # [quote, triple, raw, buf, startline]
    while i < n:
        c = t[i]
        if ctx is None:
            if t.startswith("//", i):
                j = t.find("\n", i)
                i = n if j < 0 else j
                continue
            if t.startswith("/*", i):
                lvl, j = 1, i + 2
                while j < n and lvl:
                    if nested and t.startswith("/*", j):
                        lvl, j = lvl + 1, j + 2
                    elif t.startswith("*/", j):
                        lvl, j = lvl - 1, j + 2
                    else:
                        j += 1
                if lvl:
                    err(rel, line, "Kommentar nicht beendet (fail-closed)")
                    return "".join(code), strs
                chunk = t[i:j]
                code.append("\n" * chunk.count("\n"))
                line += chunk.count("\n")
                i = j
                continue
            raw = False
            k = i
            if c == "r" and i + 1 < n and t[i + 1] in "'\"" and not (i > 0 and re.match(r"[\w$]", t[i - 1])):
                raw, k = True, i + 1
            if t[k:k + 1] in ("'", '"') and (k == i or raw):
                q = t[k]
                triple = t.startswith(q * 3, k)
                ctx = [q, triple, raw, [], line]
                i = k + (3 if triple else 1)
                continue
            if stack and c == "{":
                depth += 1
            elif stack and c == "}":
                if depth == 0:
                    ctx, depth = stack.pop()
                    i += 1
                    continue
                depth -= 1
            if c == "\n":
                line += 1
            code.append(c)
            i += 1
            continue
        q, triple, raw, buf, sl = ctx
        if c == "\\" and not raw and i + 1 < n:
            buf.append(t[i:i + 2])
            line += t[i:i + 2].count("\n")
            i += 2
            continue
        if interp and not raw and t.startswith("${", i):
            stack.append((ctx, depth))
            ctx, depth = None, 0
            i += 2
            continue
        end = t.startswith(q * 3, i) if triple else (c == q)
        if end or (c == "\n" and not triple):
            body = "".join(buf)
            strs.append(body)
            code.append("\x01%d\x02" % (len(strs) - 1) + "\n" * body.count("\n"))
            i += (3 if triple else 1) if end else 0
            ctx = None
            continue
        buf.append(c)
        if c == "\n":
            line += 1
        i += 1
    if ctx is not None and ctx[1]:
        err(rel, ctx[4], "Zeichenkette nicht beendet (fail-closed)")
    return "".join(code), strs

def line_of(code, pos):
    return code.count("\n", 0, pos) + 1

# --- Freigabeliste ----------------------------------------------------------------------------------------
allowed = {"pub": {}, "gradle": {}, "plugin": {}}
def load_list():
    p = os.path.join(root, LIST_FILE)
    if not os.path.isfile(p):
        err(LIST_FILE, 0, "Freigabeliste fehlt (fail-closed)")
        return
    try:
        lines = open(p, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError):
        err(LIST_FILE, 0, "nicht lesbar (fail-closed)")
        return
    for no, raw in enumerate(lines, 1):
        s = raw.split("#", 1)[0].strip()
        if not s:
            continue
        parts = s.split()
        if len(parts) != 3 or parts[0] not in allowed or parts[2] not in CLASSES:
            err(LIST_FILE, no, "ungültige Zeile (erwartet: pub|gradle|plugin Name Einordnung)")
            continue
        if parts[1] in allowed[parts[0]]:
            err(LIST_FILE, no, "doppelter Eintrag")
        allowed[parts[0]][parts[1]] = parts[2]

# --- Pakete, Lock, pubspec --------------------------------------------------------------------------------
def read(rel):
    try:
        return open(os.path.join(root, rel), encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        err(rel, 0, "nicht lesbar (fail-closed)")
        return None

def pub_class(name):
    return allowed["pub"].get(name)

def unknown_pub(rel, line, name, own):
    if name in own:
        return False
    if pub_class(name) is None:
        err(rel, line, f"Paket '{name}' fehlt in {LIST_FILE} (Netzprüfung nötig)")
        return True
    return False

def check_lock(own):
    t = read("app/pubspec.lock")
    if t is None:
        return
    body = t.split("\nsdks:")[0]
    cur, seen, cnt = None, {}, 0
    for no, l in enumerate(body.splitlines(), 1):
        m = re.match(r"^  ([\w.\-]+):\s*$", l)
        if m:
            cur = m.group(1)
            seen[cur] = {"line": no}
            cnt += 1
            unknown_pub("app/pubspec.lock", no, cur, ())
        elif cur and (l.startswith("    source:")):
            src = l.split(":", 1)[1].strip()
            seen[cur]["source"] = src
            if src not in ("hosted", "sdk"):
                err("app/pubspec.lock", no, f"Paket '{cur}': Quelle '{src}' nicht erlaubt (nur hosted, sdk)")
        elif cur and l.startswith("      url:"):
            if l.split(":", 1)[1].strip().strip("\"'") != "https://pub.dev":
                err("app/pubspec.lock", no, f"Paket '{cur}': fremder Paketserver")
    if cnt == 0:
        err("app/pubspec.lock", 0, "keine Pakete gelesen (fail-closed)")
    for name, c in allowed["pub"].items():
        if name not in seen and name not in own:
            print(f"Hinweis: {LIST_FILE}: '{name}' steht nicht mehr im Lock (Eintrag kann entfallen)")

def pubspec_sections(text):
    """{Abschnitt: [(Name, Zeile, [Unterzeilen])]} für Abschnitte der obersten Ebene."""
    out, sec, cur = {}, None, None
    for no, l in enumerate(text.splitlines(), 1):
        l = re.sub(r"(^|\s)#.*$", "", l)
        if not l.strip():
            continue
        if not l.startswith(" "):
            sec = l.split(":", 1)[0].strip()
            out.setdefault(sec, [])
            cur = None
        elif sec:
            m = re.match(r"^  ([\w.\-]+):\s*(.*)$", l)
            if m:
                cur = (m.group(1), no, [m.group(2)] if m.group(2) else [])
                out[sec].append(cur)
            elif cur:
                cur[2].append(l.strip())
    return out

def check_pubspec(rel, own, is_adapters):
    t = read(rel)
    if t is None:
        return
    secs = pubspec_sections(t)
    if secs.get("dependency_overrides"):
        err(rel, secs["dependency_overrides"][0][1], "dependency_overrides nicht erlaubt")
    for sec in ("dependencies", "dev_dependencies"):
        for name, no, sub in secs.get(sec, []):
            blob = " ".join(sub)
            if re.search(r"\bgit\s*:|\burl\s*:|\bhosted\s*:", blob):
                err(rel, no, f"Abhängigkeit '{name}': git/hosted-Quelle nicht erlaubt")
            m = re.search(r"\bpath\s*:\s*(\S+)", blob)
            if m:
                target = os.path.normpath(os.path.join(os.path.dirname(rel), m.group(1).strip("\"'")))
                if not (name in own and os.path.dirname(target) == "app/packages" or target == "app"):
                    err(rel, no, f"Abhängigkeit '{name}': path-Quelle nicht erlaubt")
            if unknown_pub(rel, no, name, own):
                continue
            c = pub_class(name)
            if sec == "dependencies" and c == "nur-entwicklung":
                err(rel, no, f"'{name}' ist nur für die Entwicklung eingeordnet, nicht unter dependencies")
            if sec == "dependencies" and c == "nur-karte" and not is_adapters:
                err(rel, no, f"'{name}' ist nur im Kartenadapter erlaubt")
            if sec == "dev_dependencies" and c == "nur-karte" and not is_adapters:
                err(rel, no, f"'{name}' ist nur im Kartenadapter erlaubt")

# --- Dateien ----------------------------------------------------------------------------------------------
def collect(rel_dir, skip_top=(), generated=GENERATED):
    """Alle Dateien unter rel_dir. Symlinks (auch Verzeichnisse) sind rot."""
    out, base = [], os.path.join(root, rel_dir)
    if not os.path.isdir(base):
        return None
    for d, dn, fs in os.walk(base):
        reld = os.path.relpath(d, root).replace(os.sep, "/")
        keep = []
        for x in sorted(dn):
            rx = f"{reld}/{x}"
            if os.path.islink(os.path.join(d, x)):
                err(rx, 0, "symbolischer Link auf ein Verzeichnis in einem Suchpfad")
            elif rx in generated or re.fullmatch(r"app/packages/[^/]+/android/(build|\.gradle)", rx) or (reld == rel_dir and x in skip_top):
                continue
            else:
                keep.append(x)
        dn[:] = keep
        out += [f"{reld}/{f}" for f in sorted(fs)]
    return out

scanned = 0
def check_dart(rel, text, own):
    global scanned
    scanned += 1
    code, strs = lex(text, rel)
    in_map = rel.startswith(ALLOWED)
    for m in re.finditer(r"(?<![\w$.])(import|export|part)\s*(?=\x01)([^;]*);", code):
        kind = m.group(1)
        if kind == "part":
            continue
        uris = [strs[int(x)] for x in PH.findall(m.group(2))]
        line = line_of(code, m.start())
        if not uris:
            err(rel, line, f"{kind} ohne lesbare URI (fail-closed)")
        for u in uris:
            msg = check_uri(kind, u, rel, in_map, own)
            if msg:
                err(rel, line, msg)
    if not in_map:
        for pat, what in DART_API:
            for m in re.finditer(pat, code):
                err(rel, line_of(code, m.start()), what)

def check_uri(kind, uri, rel, in_map, own):
    if kind == "export" and in_map and (":" in uri or uri.startswith("/")):
        return "export von Fremdbibliothek aus src/map (würde Netz-API nach außen reichen)"
    if uri.startswith("dart:"):
        lib = uri[5:].split("/")[0]
        if lib in DART_OK or (in_map and lib in WEB_NAMES):
            return None
        return f"dart:{lib} nicht erlaubt (nur im Kartenadapter oder unbekannt)"
    m = re.match(r"package:([^/]+)/(.*)$", uri)
    if m:
        name, path = m.groups()
        if name == "adapters":
            target = ADAPTERS_LIB + path
            if not rel.startswith(ADAPTERS_LIB) and path != "adapters.dart":
                return f"package:adapters/{path}: nur adapters.dart ist die Schnittstelle"
            return check_target(rel, target)
        if name in own:
            return None
        c = pub_class(name)
        if c is None:
            return f"Paket '{name}' fehlt in {LIST_FILE} (Netzprüfung nötig)"
        if c == "nur-entwicklung":
            return f"Paket '{name}' ist nur für die Entwicklung eingeordnet"
        if c == "nur-karte" and not in_map:
            return f"Paket '{name}' ist nur im Kartenadapter erlaubt"
        return None
    if re.match(r"[A-Za-z][\w+.\-]*:", uri) or uri.startswith("/") or "\\" in uri:
        return "URI-Schema nicht erlaubt"
    return check_target(rel, os.path.normpath(os.path.join(os.path.dirname(rel), uri)).replace(os.sep, "/"))

def check_target(rel, target):
    if target == MAP_TESTING:
        return "map_testing.dart nur in Tests (nie aus Produktivcode)"
    if target.startswith(ALLOWED) and not rel.startswith(ALLOWED):
        if rel == ADAPTERS_EXPORT and not os.path.basename(target).startswith("map_test_"):
            return None
        if rel == MAP_TESTING:
            return None
        return "Zugriff auf src/map außerhalb des vorgesehenen Exports"
    return None

def check_jvm(rel, text, ext):
    global scanned
    scanned += 1
    code, strs = lex(text, rel, nested=(ext in (".kt", ".kts")))
    for pat, what in JVM_API:
        for m in re.finditer(pat, code):
            err(rel, line_of(code, m.start()), what)

def check_native(rel, text):
    global scanned
    scanned += 1
    code, strs = lex(text, rel, nested=False, interp=False)
    # #include "x" steht als Platzhalter im Code: Include-Zeilen aus den Zeichenketten rekonstruieren.
    code = PH.sub(lambda m: '"' + strs[int(m.group(1))] + '"' if "#" in code[max(0, m.start() - 40):m.start()] else '""', code)
    for pat, what in NATIVE_API:
        for m in re.finditer(pat, code):
            err(rel, line_of(code, m.start()), what)

def check_gradle(rel, text):
    global scanned
    scanned += 1
    code, strs = lex(text, rel, nested=True)
    for pat, what in GRADLE_RISK:
        for m in re.finditer(pat, code):
            err(rel, line_of(code, m.start()), what)
    for m in re.finditer(r"\bincludeBuild\s*\(\s*\x01(\d+)\x02", code):
        if strs[int(m.group(1))] != "$flutterSdkPath/packages/flutter_tools/gradle":
            err(rel, line_of(code, m.start()), "includeBuild außerhalb des Flutter-Werkzeugs")
    for m in re.finditer(r"\bincludeBuild\s*\(\s*[^\x01\s]", code):
        err(rel, line_of(code, m.start()), "includeBuild nicht lesbar (fail-closed)")
    for m in re.finditer(r"\x01(\d+)\x02", code):
        s = strs[int(m.group(1))]
        if COORD.match(s) and "/" not in s:
            check_gradle_name(rel, line_of(code, m.start()), "gradle", ":".join(s.split("@")[0].split(":")[:2]))
    for m in re.finditer(r"\b(?:id|kotlin)\s*\(\s*\x01(\d+)\x02|\bplugin\s*[:=]\s*\x01(\d+)\x02|\bapply\s+plugin\s*:\s*\x01(\d+)\x02", code):
        s = next(strs[int(g)] for g in m.groups() if g)
        name = ("org.jetbrains.kotlin." + s) if m.group(0).startswith("kotlin") else s
        check_gradle_name(rel, line_of(code, m.start()), "plugin", name)

def check_gradle_name(rel, line, kind, name):
    if name not in allowed[kind]:
        err(rel, line, f"Gradle-{'Plugin' if kind == 'plugin' else 'Abhängigkeit'} '{name}' fehlt in {LIST_FILE} (Netzprüfung nötig)")

def check_toml(rel, text):
    global scanned
    scanned += 1
    sec = None
    for no, raw in enumerate(text.splitlines(), 1):
        l = re.sub(r"""(^|\s)#[^"']*$""", "", raw).strip()
        m = re.match(r"^\[([\w.\-]+)\]$", l)
        if m:
            sec = m.group(1)
            continue
        if not l or "=" not in l or sec not in ("libraries", "plugins"):
            continue
        if sec == "plugins":
            m = re.search(r"""\bid\s*=\s*["']([^"']+)["']""", l)
            if m:
                check_gradle_name(rel, no, "plugin", m.group(1))
            else:
                err(rel, no, "Plugin im Versionskatalog nicht lesbar (fail-closed)")
            continue
        m = (re.search(r"""\bmodule\s*=\s*["']([^"':]+:[^"':]+)["']""", l)
             or re.search(r"""=\s*["']([^"':]+:[^"':]+)(?::[^"']*)?["']""", l))
        g = re.search(r"""\bgroup\s*=\s*["']([^"']+)["']""", l)
        n = re.search(r"""\bname\s*=\s*["']([^"']+)["']""", l)
        if m:
            check_gradle_name(rel, no, "gradle", m.group(1))
        elif g and n:
            check_gradle_name(rel, no, "gradle", f"{g.group(1)}:{n.group(1)}")
        else:
            err(rel, no, "Bibliothek im Versionskatalog nicht lesbar (fail-closed)")

def scan_files(files, own):
    n = 0
    for rel in files:
        ext = os.path.splitext(rel)[1].lower()
        base = os.path.basename(rel)
        p = os.path.join(root, rel)
        if os.path.islink(p):
            err(rel, 0, "symbolischer Link in einem Suchpfad")
            continue
        if ext in BINARY_EXT and rel not in BINARY_OK:
            err(rel, 0, "Binärdatei kann nicht auf Netz geprüft werden")
            continue
        kind = None
        if ext == ".dart":
            kind = "dart"
        elif ext in (".kt", ".java"):
            kind = "jvm"
        elif ext in (".gradle", ".kts"):
            kind = "gradle"
        elif ext == ".toml":
            kind = "toml"
        elif ext in (".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".m", ".mm", ".swift"):
            kind = "native"
        if kind is None:
            continue
        text = read(rel)
        if text is None:
            continue
        n += 1
        if kind == "dart":
            check_dart(rel, text, own)
        elif kind == "jvm":
            check_jvm(rel, text, ext)
        elif kind == "gradle":
            check_gradle(rel, text)
            if ext == ".kts":
                check_jvm(rel, text, ext)
        elif kind == "toml":
            check_toml(rel, text)
        else:
            check_native(rel, text)
    return n

def main():
    load_list()
    app = os.path.join(root, "app")
    if not os.path.isdir(app):
        err("app", 0, "Suchpfad fehlt (fail-closed)")
    pk = os.path.join(root, "app/packages")
    pkgs = sorted(p for p in os.listdir(pk) if os.path.isdir(os.path.join(pk, p))) if os.path.isdir(pk) else []
    if not pkgs:
        err("app/packages", 0, "keine Pakete gefunden (fail-closed)")
    own = set(pkgs) | {"running_app"}
    if os.path.isdir(app):
        top = sorted(x for x in os.listdir(app) if os.path.isdir(os.path.join(app, x)) or os.path.islink(os.path.join(app, x)))
        for x in top:
            if x in APP_SKIP:
                continue
            if os.path.islink(os.path.join(app, x)):
                err(f"app/{x}", 0, "symbolischer Link auf ein Verzeichnis in einem Suchpfad")
                continue
            files = collect(f"app/{x}")
            n = scan_files(files or [], own)
            if x == "lib" and n == 0:
                err("app/lib", 0, "keine prüfbaren Dateien gefunden (fail-closed)")
        if "lib" not in top:
            err("app/lib", 0, "Suchpfad fehlt (fail-closed)")
        # Dateien direkt in app/ (z. B. Gradle- oder Quelltext) ebenfalls prüfen
        scan_files([f"app/{f}" for f in sorted(os.listdir(app)) if os.path.isfile(os.path.join(app, f))], own)
    for p in pkgs:
        files = collect(f"app/packages/{p}", skip_top=PKG_SKIP)
        if files is None:
            continue
        n = scan_files(files, own)
        if not any(f.startswith(f"app/packages/{p}/lib/") and f.endswith(".dart") for f in files):
            err(f"app/packages/{p}/lib", 0, "keine prüfbaren Dateien gefunden (fail-closed)")
    if not os.path.isdir(os.path.join(root, ALLOWED)):
        print("Hinweis: %s existiert noch nicht (erlaubter Ort für Netz-Code)" % ALLOWED)
    check_lock(own)
    for rel in ["app/pubspec.yaml"] + [f"app/packages/{p}/pubspec.yaml" for p in pkgs]:
        if not os.path.isfile(os.path.join(root, rel)):
            err(rel, 0, "fehlt (fail-closed)")
        else:
            check_pubspec(rel, own, rel == "app/packages/adapters/pubspec.yaml")
    if errors:
        print("Netz- oder Kartencode außerhalb von %s bzw. nicht freigegeben:" % ALLOWED)
        uniq = list(dict.fromkeys(errors))
        print("\n".join(uniq[:60]))
        print(HINT)
        sys.exit(1)
    print("%d Dateien geprüft, kein Netz-Code außerhalb von %s, alle Pakete freigegeben" % (scanned, ALLOWED))

main()
