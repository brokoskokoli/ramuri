#!/usr/bin/env python3
"""Gate-Schritt "Architektur": Zyklen-Ratsche für core-Module und App-Features. Aufruf: check_architecture.py [Repo-Wurzel].

Modulbegriff (Regel in docs/architecture/code-map.md):
- core: Ordner unter app/packages/core/lib/src/<modul>/. ports, fakes, testing und Barrels (core.dart, fakes.dart …)
  liegen außerhalb von src/ und sind keine Module. Dateien direkt in src/ (z. B. algorithm_category.dart) sind keine
  Module; Kanten über sie hinweg werden durchgereicht (A → src/x.dart → B zählt als A → B).
- App: Ordner unter app/lib/features/<feature>/.
- Kante: import, export oder part einer Datei des anderen Moduls, relativ oder über package:core/src/… bzw.
  package:running_app/features/…; bedingte Importe zählen mit jeder URI. Erzeugte Dateien (*.g.dart) zählen mit.

Ratsche: Gezählt werden Module in starken Zusammenhangskomponenten mit mehr als einem Knoten (Tarjan). Mehr als die
Grundlinie ist rot (mit Komponente, Modulnamen und je Modul der Kante Datei:Zeile, die seinen Zyklus schließt), weniger
ebenfalls rot mit "Grundlinie auf <n> senken" - so sinkt sie mit jedem Fix.

Blattmodule (CORE_LEAF_MODULES): importieren kein anderes core-Modul, auch nicht über Dateien direkt in src/. Fehlt
ein Blattmodul im Baum, ist das rot.

Fail-closed: fehlende Suchpfade, unlesbare Dateien, symbolische Links, Direktiven ohne lesbare URI, unbekannte
URI-Schemata und der Barrel-Import package:core/core.dart innerhalb von core/lib/src sind rot."""
import os, re, sys

# Grundlinie: gemessener Stand. Nur senken (der Hinweis nennt den neuen Wert), nie erhöhen.
CORE_CYCLE_MODULES = 12
APP_CYCLE_FEATURES = 16

# Blattmodule in core: keine Kante zu einem anderen Modul unter src/ (Regel in docs/architecture/code-map.md).
CORE_LEAF_MODULES = ("calendar",)

CORE_SRC = "app/packages/core/lib/src/"
APP_FEATURES = "app/lib/features/"
APP_PACKAGE = "running_app"

errors = []

def err(rel, line, msg):
    errors.append(f"{rel}:{line}: {msg}" if line else f"{rel}: {msg}")

# --- Lexer: Kommentare entfernen, Zeichenketten durch Platzhalter ersetzen ----------------------------------
PH = re.compile(r"\x01(\d+)\x02")

def lex(text, rel):
    """Rückgabe (code, strs): Kommentare entfernt, Zeichenketten als \\x01N\\x02 (Inhalt in strs[N], ein Ausdruck
    ${…} als \\x03). Zeilenumbrüche bleiben erhalten. Unbeendete Kommentare oder Zeichenketten sind rot."""
    code, strs = [], []
    t, n, i, line = text, len(text), 0, 1
    stack, depth, ctx = [], 0, None  # ctx = [quote, triple, raw, buf, startline]
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
                    if t.startswith("/*", j):
                        lvl, j = lvl + 1, j + 2
                    elif t.startswith("*/", j):
                        lvl, j = lvl - 1, j + 2
                    else:
                        j += 1
                if lvl:
                    err(rel, line, "Kommentar nicht beendet (fail-closed)")
                    return "".join(code), strs
                k = t.count("\n", i, j)
                code.append("\n" * k)
                line += k
                i = j
                continue
            raw, k = False, i
            if c == "r" and t[i + 1:i + 2] in ("'", '"') and not (i > 0 and re.match(r"[\w$]", t[i - 1])):
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
        q, triple, raw, buf, _ = ctx
        if c == "\\" and not raw and i + 1 < n:
            buf.append(t[i:i + 2])
            line += t[i:i + 2].count("\n")
            i += 2
            continue
        if not raw and t.startswith("${", i):
            buf.append("\x03")
            stack.append((ctx, depth))
            ctx, depth = None, 0
            i += 2
            continue
        if not raw and c == "$" and re.match(r"[A-Za-z_]", t[i + 1:i + 2]):
            buf.append("\x03")
        end = t.startswith(q * 3, i) if triple else (c == q)
        if end or (c == "\n" and not triple):
            if not end:
                err(rel, ctx[4], "Zeichenkette nicht beendet (fail-closed)")
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
    if ctx is not None or stack:
        err(rel, ctx[4] if ctx else line, "Zeichenkette nicht beendet (fail-closed)")
    return "".join(code), strs

DIRECTIVE = re.compile(r"(?<![\w$.])(import|export|part)(?!\s+of\b)\s*(?=\x01)([^;]*);")

def directives(rel, text):
    """[(Zeile, URI)] aller import/export/part-Direktiven."""
    code, strs = lex(text, rel)
    out = []
    for m in DIRECTIVE.finditer(code):
        kind, body = m.groups()
        line = code.count("\n", 0, m.start()) + 1
        uris = [strs[int(x)] for x in PH.findall(body)]
        if re.search(r"\x02\s*\x01", body):
            err(rel, line, f"{kind}: aneinandergereihte Zeichenketten im URI (fail-closed)")
            continue
        if not uris or any("\x03" in u for u in uris):
            err(rel, line, f"{kind} ohne lesbare URI (fail-closed)")
            continue
        out += [(line, u) for u in uris]
    # Direktive am Zeilenanfang (dart format setzt sie in Spalte 0) ohne Zeichenkette als URI ist unbekannt.
    for m in re.finditer(r"^(import|export)\b(?!\s*\x01)", code, re.M):
        err(rel, code.count("\n", 0, m.start()) + 1, f"{m.group(1)}: unbekannte Form (fail-closed)")
    return out

# --- Dateien ------------------------------------------------------------------------------------------------
def collect(root, rel_dir):
    base = os.path.join(root, rel_dir)
    if os.path.islink(base.rstrip("/")) or not os.path.isdir(base):
        err(rel_dir, 0, "Suchpfad fehlt (fail-closed)")
        return []
    out = []
    for d, dn, fs in os.walk(base):
        reld = os.path.relpath(d, root).replace(os.sep, "/")
        for x in list(dn):
            if os.path.islink(os.path.join(d, x)):
                err(f"{reld}/{x}", 0, "symbolischer Link auf ein Verzeichnis in einem Suchpfad (fail-closed)")
                dn.remove(x)
        dn.sort()
        for f in sorted(fs):
            p = os.path.join(d, f)
            if f.endswith(".dart"):
                if os.path.islink(p):
                    err(f"{reld}/{f}", 0, "symbolischer Link (fail-closed)")
                else:
                    out.append(f"{reld}/{f}")
    if not out:
        err(rel_dir, 0, "keine Dart-Dateien gefunden (fail-closed)")
    return out

def resolve(rel, line, uri, package_uri):
    """Zielpfad relativ zur Wurzel oder None (außerhalb des Graphen). package_uri: (Paketname, Pfadpräfix im Repo)."""
    if uri.startswith("dart:"):
        return None
    m = re.match(r"package:([^/]+)/(.*)$", uri)
    if m:
        name, path = m.groups()
        pkg, base = package_uri
        return base + path if name == pkg else None
    if re.match(r"[A-Za-z][\w+.\-]*:", uri) or uri.startswith("/") or "\\" in uri:
        err(rel, line, f"URI-Schema nicht erlaubt: {uri!r} (fail-closed)")
        return None
    return os.path.normpath(os.path.join(os.path.dirname(rel), uri)).replace(os.sep, "/")

def module_of(path, prefix):
    if not path.startswith(prefix):
        return None
    rest = path[len(prefix):]
    return rest.split("/", 1)[0] if "/" in rest else ("." + rest)  # ".datei.dart" = Datei direkt im Präfix

def build_graph(root, prefix, package_uri, barrel=None):
    """Kanten {Modul: {Zielmodul: (Datei, Zeile)}} zwischen Modulen; Dateien direkt im Präfix werden durchgereicht."""
    raw = {}  # Knoten (Modul oder .datei) -> {Ziel: (Datei, Zeile)}
    files = collect(root, prefix)
    for rel in files:
        try:
            text = open(os.path.join(root, rel), encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            err(rel, 0, "nicht lesbar (fail-closed)")
            continue
        src = module_of(rel, prefix)
        raw.setdefault(src, {})
        for line, uri in directives(rel, text):
            if barrel and uri == barrel:
                err(rel, line, f"Barrel {uri} innerhalb der Module verdeckt Kanten; Datei direkt importieren")
                continue
            target = resolve(rel, line, uri, package_uri)
            if target is None:
                continue
            if target.startswith(prefix) and not target.endswith(".dart"):
                err(rel, line, f"Ziel ist keine Dart-Datei: {uri!r} (fail-closed)")
                continue
            dst = module_of(target, prefix)
            if dst is not None and dst != src:
                raw[src].setdefault(dst, (rel, line))
    modules = sorted(m for m in raw if not m.startswith("."))
    graph = {}
    for m in modules:
        out, seen, todo = {}, set(), [(t, loc) for t, loc in raw[m].items()]
        while todo:
            t, loc = todo.pop(0)
            if t in seen:
                continue
            seen.add(t)
            if t.startswith("."):
                todo += [(u, loc) for u in raw.get(t, {})]
            elif t != m:
                out.setdefault(t, loc)
        graph[m] = out
    return graph, len(files)

def sccs(graph):
    """Tarjan (iterativ). Liste der Komponenten, jede sortiert."""
    index, low, on, stack, out, counter = {}, {}, set(), [], [], [0]
    for start in sorted(graph):
        if start in index:
            continue
        work = [(start, iter(sorted(graph[start])))]
        index[start] = low[start] = counter[0]; counter[0] += 1
        stack.append(start); on.add(start)
        while work:
            v, it = work[-1]
            w = next(it, None)
            if w is not None:
                if w not in graph:
                    continue
                if w not in index:
                    index[w] = low[w] = counter[0]; counter[0] += 1
                    stack.append(w); on.add(w)
                    work.append((w, iter(sorted(graph[w]))))
                elif w in on:
                    low[v] = min(low[v], index[w])
                continue
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[v])
            if low[v] == index[v]:
                comp = []
                while True:
                    w = stack.pop(); on.discard(w); comp.append(w)
                    if w == v:
                        break
                out.append(sorted(comp))
    return sorted(out, key=lambda c: (-len(c), c))

def closing_cycle(graph, comp, m):
    """Kürzester Zyklus m → … → m innerhalb der Komponente (Breitensuche)."""
    members, prev, queue = set(comp), {}, [m]
    while queue:
        v = queue.pop(0)
        for w in sorted(graph[v]):
            if w not in members:
                continue
            if w == m:
                path = [v]
                while path[-1] != m:
                    path.append(prev[path[-1]])
                return [m] + list(reversed(path[:-1])) + [m] if v != m else [m, m]
            if w not in prev:
                prev[w] = v
                queue.append(w)
    return [m]

def check(name, graph, comps, baseline, const):
    cyc = [c for c in comps if len(c) > 1]
    n = sum(len(c) for c in cyc)
    print(f"{name}: {len(graph)} Module, {n} in Zyklen (Grundlinie {const} = {baseline})")
    for c in cyc:
        print(f"  Komponente ({len(c)}): {', '.join(c)}")
    if n > baseline:
        err(name, 0, f"{n} Module in Zyklen, Grundlinie {baseline}: neuer Zyklus. Kante entfernen oder Code verschieben "
                     f"(Regeln: docs/architecture/code-map.md)")
        for c in cyc:
            print(f"  Zyklus in {name}: {', '.join(c)}")
            for m in c:
                path = closing_cycle(graph, c, m)
                if len(path) < 2:
                    continue
                f, l = graph[m][path[1]]
                print(f"    {m} → {path[1]}: {f}:{l} (zurück über {' → '.join(path[1:])})")
    elif n < baseline:
        err(name, 0, f"{n} Module in Zyklen, weniger als die Grundlinie: Grundlinie auf {n} senken "
                     f"({const} in tool/check_architecture.py)")

def check_leaves(name, graph, leaves, const):
    for m in leaves:
        if m not in graph:
            err(name, 0, f"Blattmodul {m} fehlt ({const} in tool/check_architecture.py, fail-closed)")
            continue
        for t, (f, l) in sorted(graph[m].items()):
            err(f, l, f"Blattmodul {m} importiert Modul {t} ({const}; Regeln: docs/architecture/code-map.md)")

def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    core, nc = build_graph(root, CORE_SRC, ("core", "app/packages/core/lib/"), barrel="package:core/core.dart")
    app, na = build_graph(root, APP_FEATURES, (APP_PACKAGE, "app/lib/"))
    check("core", core, sccs(core), CORE_CYCLE_MODULES, "CORE_CYCLE_MODULES")
    check_leaves("core", core, CORE_LEAF_MODULES, "CORE_LEAF_MODULES")
    check("app", app, sccs(app), APP_CYCLE_FEATURES, "APP_CYCLE_FEATURES")
    if errors:
        print("Architekturprüfung rot:")
        print("\n".join(list(dict.fromkeys(errors))[:60]))
        sys.exit(1)
    print(f"{nc + na} Dateien geprüft, keine neuen Zyklen")

if __name__ == "__main__":
    main()
