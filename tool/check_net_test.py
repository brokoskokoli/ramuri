#!/usr/bin/env python3
"""Selbsttest für tool/check_net.py. Aufruf: check_net_test.py [Repo-Wurzel]

Baut einen kleinen Baum mit zulässigem Kartenadapter (grün), führt jeden bekannten Umgehungsfall einzeln darauf aus
(jeweils rot, mit erwarteter Meldung) und prüft zuletzt den echten Baum (grün). Wird eine Regel in check_net.py
entfernt oder aufgeweicht, wird der zugehörige Fall grün und dieser Test rot."""
import os, shutil, subprocess, sys, tempfile

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
CHECK = os.path.join(REPO, "tool", "check_net.py")
MAP = "app/packages/adapters/lib/src/map/"

LIST = """pub flutter sdk
pub flutter_test sdk
pub core kein-netz
pub drift kein-netz
pub http nur-karte
pub flutter_map nur-karte
pub test nur-entwicklung
pub flutter_driver nur-entwicklung
pub fuchsia_remote_debug_protocol nur-entwicklung
pub integration_test nur-entwicklung
pub jni nur-entwicklung
pub package_config nur-entwicklung
pub process nur-entwicklung
gradle junit:junit nur-entwicklung
plugin dev.flutter.flutter-plugin-loader nur-entwicklung
plugin com.android.application nur-entwicklung
"""
LOCK = """packages:
  drift:
    dependency: "direct main"
    description:
      name: drift
      sha256: "00"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
  flutter_map:
    dependency: transitive
    description:
      name: flutter_map
      sha256: "00"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  http:
    dependency: transitive
    description:
      name: http
      sha256: "00"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
"""
FILES = {
    "tool/net_allowed_packages.txt": LIST,
    "app/pubspec.lock": LOCK,
    "app/pubspec.yaml": "name: running_app\ndependencies:\n  flutter:\n    sdk: flutter\n  core:\n    path: packages/core\n"
                        "  adapters:\n    path: packages/adapters\ndev_dependencies:\n  test: ^1.0.0\n",
    "app/lib/main.dart": "import 'package:flutter/material.dart';\nimport 'package:adapters/adapters.dart';\n"
                         "// Image.network(HttpClient()) steht nur im Kommentar\n/* HttpClient() */\n"
                         "final s = 'HttpClient() und Image.network';\nfinal t = '${s.length}';\n",
    "app/android/build.gradle.kts": "allprojects { repositories { google()\n mavenCentral() } }\n",
    "app/android/settings.gradle.kts": 'pluginManagement { includeBuild("$flutterSdkPath/packages/flutter_tools/gradle") }\n'
                                       'plugins { id("dev.flutter.flutter-plugin-loader") version "1.0.0"\n'
                                       'id("com.android.application") version "9.1.0" apply false }\n',
    "app/android/app/build.gradle.kts": 'plugins { id("com.android.application") }\n'
                                        'dependencies { testImplementation("junit:junit:4.13.2") }\n',
    "app/android/app/src/main/kotlin/a/Main.kt": "package a\nclass Main { val x = 1 }\n",
    "app/packages/core/pubspec.yaml": "name: core\ndependencies:\n",
    "app/packages/core/lib/core.dart": "library core;\nimport 'dart:io';\nfinal f = File('x');\n",
    "app/packages/adapters/pubspec.yaml": "name: adapters\ndependencies:\n  flutter:\n    sdk: flutter\n  core:\n    path: ../core\n"
                                          "  drift: 1.0.0\n  http: 1.0.0\n  flutter_map: 1.0.0\n",
    "app/packages/adapters/lib/adapters.dart": "export 'src/map/tile.dart';\n",
    "app/packages/adapters/lib/map_testing.dart": "library;\nexport 'src/map/test_net.dart';\n",
    MAP + "tile.dart": "import 'dart:io';\nimport 'package:http/http.dart' as http;\nimport 'package:flutter_map/flutter_map.dart';\n"
                       "import 'test_net.dart';\nfinal c = HttpClient();\nfinal i = Image.network('x');\n",
    MAP + "test_net.dart": "class FakeNet {}\n",
}

def build(extra):
    d = tempfile.mkdtemp(prefix="check_net_")
    for rel, content in {**FILES, **extra}.items():
        if content is None:
            continue
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w", encoding="utf-8").write(content) if isinstance(content, str) else open(p, "wb").write(content)
    return d

def run(d):
    r = subprocess.run([sys.executable, CHECK, d], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr

def with_lock(*names):
    return LOCK.replace("sdks:", "".join(
        f'  {n}:\n    dependency: transitive\n    description:\n      name: {n}\n      sha256: "00"\n'
        f'      url: "https://pub.dev"\n    source: hosted\n    version: "1.0.0"\n' for n in names) + "sdks:")

def d(code):
    return "import 'package:flutter/material.dart';\n" + code + "\n"

# Name, Dateien, erwartete Meldung (Teilstring der Ausgabe)
RED = [
    ("import-if http", {"app/lib/a.dart": "import 'stub.dart' if (dart.library.io) 'package:http/http.dart';\n"}, "a.dart:1: Paket 'http' ist nur im Kartenadapter"),
    ("export-if http", {"app/lib/a.dart": "export 'stub.dart' if (dart.library.io) 'package:http/http.dart';\n"}, "a.dart:1: Paket 'http'"),
    ("import raw-String", {"app/lib/a.dart": "import r'package:http/http.dart';\n"}, "a.dart:1: Paket 'http'"),
    ("import ohne Leerzeichen", {"app/lib/a.dart": "import'package:http/http.dart';\n"}, "a.dart:1: Paket 'http'"),
    ("import mehrzeilig", {"app/lib/a.dart": "import\n  'package:http/http.dart'\n  as h;\n"}, "a.dart:1: Paket 'http'"),
    ("NetworkAssetBundle", {"app/lib/a.dart": d("final b = NetworkAssetBundle(Uri());")}, "a.dart:2: Netz-Klasse"),
    ("Image.network mit Zeilenumbruch", {"app/lib/a.dart": d("final w = Image\n  .network('x');")}, "a.dart:2: Netz-Aufruf"),
    ("InternetAddress", {"app/lib/a.dart": d("final r = InternetAddress('1.1.1.1').reverse();")}, "a.dart:2: Netz-Klasse"),
    ("dart:io mit Alias", {"app/lib/a.dart": "import 'dart:io' as io;\nfinal c = io.HttpClient();\n"}, "a.dart:2: Netz-Klasse"),
    ("Code in Interpolation", {"app/lib/a.dart": "final s = 'x ${HttpClient()} y';\n"}, "a.dart:1: Netz-Klasse"),
    ("build/ in app/lib", {"app/lib/build/a.dart": "final c = HttpClient();\n"}, "app/lib/build/a.dart:1"),
    (".idea/ in app/lib", {"app/lib/.idea/a.dart": "final c = HttpClient();\n"}, "app/lib/.idea/a.dart:1"),
    (".gradle/ in app/android/app", {"app/android/app/.gradle/A.kt": "val c = java.net.URL(\"x\")\n"}, "app/android/app/.gradle/A.kt:1"),
    ("Zeichenkette verbirgt Code", {"app/lib/a.dart": "final u = 'https://x'; final c = HttpClient();\n"}, "a.dart:1: Netz-Klasse"),
    ("Kommentarzeichen in Zeichenketten", {"app/lib/a.dart": "final a = '/*';\nfinal c = HttpClient();\nfinal b = '*/';\n"}, "a.dart:2: Netz-Klasse"),
    ("Kommentarzeichen in Raw-String", {"app/lib/a.dart": "final a = r'//';final c = HttpClient();\n"}, "a.dart:1: Netz-Klasse"),
    ("Kommentar nicht beendet", {"app/lib/a.dart": "/* offen\nfinal c = 1;\n"}, "a.dart:1: Kommentar nicht beendet"),
    ("Dreifach-String nicht beendet", {"app/lib/a.dart": "final c = '''offen\n"}, "a.dart:1: Zeichenkette nicht beendet"),
    ("neues Paket webview_flutter", {"app/pubspec.lock": with_lock("webview_flutter")}, "Paket 'webview_flutter' fehlt"),
    ("neues Paket rhttp", {"app/pubspec.lock": with_lock("rhttp")}, "Paket 'rhttp' fehlt"),
    ("neues Paket flutter_cache_manager", {"app/pubspec.lock": with_lock("flutter_cache_manager")}, "Paket 'flutter_cache_manager' fehlt"),
    ("neues Paket native_dio_adapter", {"app/pubspec.lock": with_lock("native_dio_adapter")}, "Paket 'native_dio_adapter' fehlt"),
    ("neues Paket amplitude_flutter", {"app/pubspec.lock": with_lock("amplitude_flutter")}, "Paket 'amplitude_flutter' fehlt"),
    ("nur transitiv im Lock", {"app/pubspec.lock": with_lock("sneaky_dep")}, "Paket 'sneaky_dep' fehlt"),
    ("direktes Paket dio in adapters", {"app/packages/adapters/pubspec.yaml": FILES["app/packages/adapters/pubspec.yaml"] + "  dio: 5.0.0\n"}, "adapters/pubspec.yaml:10: Paket 'dio' fehlt"),
    ("firebase_analytics in adapters", {"app/packages/adapters/pubspec.yaml": FILES["app/packages/adapters/pubspec.yaml"] + "  firebase_analytics: 1.0.0\n"}, "Paket 'firebase_analytics' fehlt"),
    ("Kartenpaket unter app-dependencies", {"app/pubspec.yaml": FILES["app/pubspec.yaml"].replace("dev_dependencies", "  flutter_map: 1.0.0\ndev_dependencies")}, "app/pubspec.yaml:9: 'flutter_map' ist nur im Kartenadapter"),
    ("Entwicklungspaket unter dependencies", {"app/pubspec.yaml": FILES["app/pubspec.yaml"].replace("dev_dependencies", "  test: 1.0.0\ndev_dependencies")}, "nur für die Entwicklung eingeordnet"),
    ("git-Abhängigkeit", {"app/packages/adapters/pubspec.yaml": FILES["app/packages/adapters/pubspec.yaml"].replace("  drift: 1.0.0", "  drift:\n    git: https://x/y.git")}, "git/hosted-Quelle"),
    ("path-Abhängigkeit fremd", {"app/packages/adapters/pubspec.yaml": FILES["app/packages/adapters/pubspec.yaml"].replace("  drift: 1.0.0", "  drift:\n    path: /tmp/drift")}, "path-Quelle"),
    ("dependency_overrides", {"app/pubspec.yaml": FILES["app/pubspec.yaml"] + "dependency_overrides:\n  drift: 1.0.0\n"}, "dependency_overrides"),
    ("Lock mit git-Quelle", {"app/pubspec.lock": LOCK.replace("source: hosted", "source: git", 1)}, "Quelle 'git' nicht erlaubt"),
    ("Lock mit fremdem Server", {"app/pubspec.lock": LOCK.replace("https://pub.dev", "https://evil.example", 1)}, "fremder Paketserver"),
    ("Gradle firebase", {"app/android/app/build.gradle.kts": 'dependencies { implementation("com.google.firebase:firebase-analytics:21.0") }\n'}, "Gradle-Abhängigkeit 'com.google.firebase:firebase-analytics'"),
    ("Gradle sentry", {"app/android/app/build.gradle.kts": 'dependencies { implementation("io.sentry:sentry-android:7.0") }\n'}, "'io.sentry:sentry-android'"),
    ("Gradle glide (Groovy)", {"app/android/app/build.gradle": "dependencies {\n  implementation 'com.github.bumptech.glide:glide:4.0'\n}\n"}, "'com.github.bumptech.glide:glide'"),
    ("Gradle Plugin unbekannt", {"app/android/app/build.gradle.kts": 'plugins { id("com.google.gms.google-services") }\n'}, "Gradle-Plugin 'com.google.gms.google-services'"),
    ("Gradle Versionskatalog module", {"app/android/gradle/libs.versions.toml": '[libraries]\nokh = { module = "com.squareup.okhttp3:okhttp", version = "4.0" }\n'}, "libs.versions.toml:2: Gradle-Abhängigkeit 'com.squareup.okhttp3:okhttp'"),
    ("Gradle Versionskatalog group/name", {"app/android/gradle/libs.versions.toml": '[libraries]\nx = { group = "io.sentry", name = "sentry", version = "1" }\n'}, "'io.sentry:sentry'"),
    ("Gradle Versionskatalog Kurzform", {"app/android/gradle/libs.versions.toml": '[libraries]\nx = "io.sentry:sentry:1"\n'}, "'io.sentry:sentry'"),
    ("Gradle lokale Datei", {"app/android/app/build.gradle.kts": 'dependencies { implementation(files("libs/x.jar")) }\n'}, "lokale Datei"),
    ("Gradle eigenes Repository", {"app/android/build.gradle.kts": 'repositories { maven { url = uri("https://x") } }\n'}, "eigenes Repository"),
    ("Gradle includeBuild fremd", {"app/android/settings.gradle.kts": FILES["app/android/settings.gradle.kts"] + 'includeBuild("../x")\n'}, "includeBuild"),
    ("Gradle in app/packages/*/android", {"app/packages/adapters/android/build.gradle": "dependencies { implementation 'io.sentry:sentry:1' }\n"}, "packages/adapters/android/build.gradle:1"),
    (".cpp mit Socket-Include", {"app/android/app/src/main/cpp/a.cpp": "#include <sys/socket.h>\nint f(){return 0;}\n"}, "a.cpp:1: natives Netz-Include"),
    (".c mit connect", {"app/packages/adapters/android/src/a.c": "int f(int s){return connect(s,0,0);}\n"}, "a.c:1: natives Netz-Aufruf"),
    (".cpp getaddrinfo in Plugin", {"app/packages/adapters/android/src/a.cpp": "void f(){ getaddrinfo(0,0,0,0); }\n"}, "a.cpp:1: natives Netz-Aufruf"),
    ("Swift URLSession", {"app/packages/adapters/ios/A.swift": "let s = URLSession.shared\n"}, "A.swift:1: natives Netz-Aufruf"),
    ("Kotlin java.net in Plugin", {"app/packages/adapters/android/src/main/kotlin/A.kt": "import java.net.Socket\n"}, "A.kt:1: JVM-Netz"),
    ("Kotlin socketFactory", {"app/android/app/src/main/kotlin/a/B.kt": "fun f(n: android.net.Network) = n.socketFactory\n"}, "B.kt:1: JVM-Netz-Klasse"),
    ("Kotlin okhttp", {"app/android/app/src/main/kotlin/a/B.kt": "import okhttp3.OkHttpClient\n"}, "B.kt:1: JVM-Netz"),
    ("Kotlin URL(", {"app/android/app/src/main/kotlin/a/B.kt": "val u = URL(\"x\")\n"}, "B.kt:1: java.net.URL"),
    ("Binärdatei .so", {"app/packages/adapters/android/src/main/jniLibs/x.so": b"\x7fELF"}, "Binärdatei"),
    ("Binärdatei .jar", {"app/android/app/libs/x.jar": b"PK"}, "Binärdatei"),
    ("export Fremdbibliothek in src/map", {MAP + "tile.dart": FILES[MAP + "tile.dart"] + "export 'package:http/http.dart';\n"}, "tile.dart:7: export von Fremdbibliothek"),
    ("export dart:io in src/map", {MAP + "tile.dart": FILES[MAP + "tile.dart"] + "export 'dart:io' show HttpClient;\n"}, "export von Fremdbibliothek"),
    ("adapters.dart exportiert http", {"app/packages/adapters/lib/adapters.dart": "export 'package:http/http.dart';\n"}, "adapters.dart:1: Paket 'http' ist nur im Kartenadapter"),
    ("adapters.dart exportiert map_test_*", {"app/packages/adapters/lib/adapters.dart": "export 'src/map/map_test_net.dart';\n", MAP + "map_test_net.dart": "class X {}\n"}, "adapters.dart:1: Zugriff auf src/map"),
    ("map_testing aus app/lib", {"app/lib/a.dart": "import 'package:adapters/map_testing.dart';\n"}, "a.dart:1: package:adapters/map_testing.dart"),
    ("src/map aus app/lib", {"app/lib/a.dart": "import 'package:adapters/src/map/tile.dart';\n"}, "a.dart:1: package:adapters/src/map/tile.dart"),
    ("map_testing aus adapters/lib", {"app/packages/adapters/lib/src/x.dart": "import '../map_testing.dart';\n"}, "x.dart:1: map_testing.dart nur in Tests"),
    ("src/map aus anderem adapters-Code", {"app/packages/adapters/lib/src/x.dart": "import 'map/tile.dart';\n"}, "x.dart:1: Zugriff auf src/map"),
    ("src/map per package aus adapters", {"app/packages/adapters/lib/src/x.dart": "import 'package:adapters/src/map/tile.dart';\n"}, "x.dart:1: Zugriff auf src/map"),
    ("Kartenpaket in app/lib", {"app/lib/a.dart": "import 'package:flutter_map/flutter_map.dart';\n"}, "a.dart:1: Paket 'flutter_map' ist nur im Kartenadapter"),
    ("Paket nicht in der Liste", {"app/lib/a.dart": "import 'package:webview_flutter/webview_flutter.dart';\n"}, "Paket 'webview_flutter' fehlt"),
    ("Entwicklungspaket in lib", {"app/lib/a.dart": "import 'package:test/test.dart';\n"}, "nur für die Entwicklung"),
    ("dart:html in app/lib", {"app/lib/a.dart": "import 'dart:html';\n"}, "dart:html nicht erlaubt"),
    ("dart:ffi in core", {"app/packages/core/lib/a.dart": "import 'dart:ffi';\n"}, "dart:ffi nicht erlaubt"),
    ("http:-URI", {"app/lib/a.dart": "import 'http://x/y.dart';\n"}, "URI-Schema"),
    ("import mit aneinandergereihten Zeichenketten", {"app/lib/a.dart": "import 'package' ':http/http.dart';\n"}, "a.dart:1: import: aneinandergereihte"),
    ("import dart: aneinandergereiht", {"app/lib/a.dart": "import 'dart' ':io' as x;\n"}, "a.dart:1: import: aneinandergereihte"),
    ("export aneinandergereiht, mehrzeilig", {"app/lib/a.dart": "export 'pack'\n  'age:http/http.dart';\n"}, "a.dart:1: export: aneinandergereihte"),
    ("Gradle benannte Argumente (Kotlin)", {"app/android/app/build.gradle.kts": 'dependencies { implementation(group = "io.sentry", name = "sentry-android", version = "7.0") }\n'}, "Koordinate in benannten Argumenten"),
    ("Gradle benannte Argumente (Groovy)", {"app/android/app/build.gradle": "dependencies {\n  implementation group: 'io.sentry', name: 'sentry', version: '7'\n}\n"}, "Koordinate in benannten Argumenten"),
    ("Gradle mapOf mit group/name", {"app/android/app/build.gradle.kts": 'dependencies { implementation(mapOf("group" to "io.sentry", "name" to "sentry", "version" to "7")) }\n'}, "getrennten Zeichenketten"),
    ("Gradle create() mit mehreren Zeichenketten", {"app/android/app/build.gradle.kts": 'dependencies { implementation(create("io.sentry", "sentry", "7")) }\n'}, "create() mit getrennten"),
    ("Gradle Interpolation $a", {"app/android/app/build.gradle.kts": 'dependencies { implementation("$a:sentry-android:7.0") }\n'}, "Koordinate mit Interpolation"),
    ("Gradle Interpolation ${a}", {"app/android/app/build.gradle.kts": 'dependencies { implementation("${a}:sentry-android:7.0") }\n'}, "Koordinate mit Interpolation"),
    ("Gradle Interpolation im Namen", {"app/android/app/build.gradle.kts": 'dependencies { implementation("io.sentry:${n}:7.0") }\n'}, "Koordinate mit Interpolation"),
    ("Process.run", {"app/lib/a.dart": d("Future<void> f() => Process.run('curl', ['x']);")}, "a.dart:2: Prozessstart"),
    ("Process . start mit Zeilenumbruch", {"app/lib/a.dart": d("Future<void> f() => Process\n  .start('curl', []);")}, "a.dart:2: Prozessstart"),
    ("SecureServerSocket", {"app/lib/a.dart": d("final s = SecureServerSocket.bind('x', 1, null);")}, "a.dart:2: Prozessstart oder Server-Socket"),
    ("typedef auf Image", {"app/lib/a.dart": d("typedef I = Image;\nfinal w = I.network('x');")}, "a.dart:2: Alias einer Netz-Klasse"),
    ("typedef auf HttpClient", {"app/lib/a.dart": "typedef H = HttpClient;\n"}, "a.dart:1: Alias einer Netz-Klasse"),
    ("flutter_driver in lib", {"app/lib/a.dart": "import 'package:flutter_driver/flutter_driver.dart';\n"}, "Paket 'flutter_driver' ist nur für die Entwicklung"),
    ("fuchsia_remote_debug_protocol in lib", {"app/lib/a.dart": "import 'package:fuchsia_remote_debug_protocol/x.dart';\n"}, "Paket 'fuchsia_remote_debug_protocol' ist nur für"),
    ("integration_test in lib", {"app/lib/a.dart": "import 'package:integration_test/integration_test.dart';\n"}, "Paket 'integration_test' ist nur für"),
    ("jni in lib", {"app/lib/a.dart": "import 'package:jni/jni.dart';\n"}, "Paket 'jni' ist nur für die Entwicklung"),
    ("package_config in lib", {"app/lib/a.dart": "import 'package:package_config/package_config.dart';\n"}, "Paket 'package_config' ist nur für"),
    ("process in lib", {"app/lib/a.dart": "import 'package:process/process.dart';\n"}, "Paket 'process' ist nur für"),
    (".dex in app/android", {"app/android/app/libs/x.dex": "x"}, "x.dex: Binärdatei"),
    ("CMakeLists.txt", {"app/android/app/src/main/cpp/CMakeLists.txt": "project(x)\n"}, "CMakeLists.txt: CMake-Skript"),
    ("*.cmake", {"app/android/app/src/main/cpp/x.cmake": "x\n"}, "x.cmake: CMake-Skript"),
    ("Verzeichnis-Symlink in app/lib", {}, "symbolischer Link"),
    ("Datei-Symlink in app/lib", {}, "symbolischer Link"),
    ("Code in unbekanntem Ordner app/hook", {"app/hook/build.dart": "final c = HttpClient();\n"}, "app/hook/build.dart:1"),
    ("Freigabeliste fehlt", {"tool/net_allowed_packages.txt": None}, "Freigabeliste fehlt"),
    ("Freigabeliste ungültig", {"tool/net_allowed_packages.txt": LIST + "pub x vielleicht\n"}, "ungültige Zeile"),
    ("Suchpfad app/lib fehlt", {"app/lib/main.dart": None}, "app/lib"),
]

def symlinks(tree, name):
    if name.startswith("Verzeichnis"):
        os.makedirs(os.path.join(tree, "app/elsewhere"), exist_ok=True)
        os.symlink(os.path.join(tree, "app/elsewhere"), os.path.join(tree, "app/lib/link"))
    elif name.startswith("Datei"):
        os.symlink(os.path.join(tree, "app/lib/main.dart"), os.path.join(tree, "app/lib/link.dart"))

def main():
    failures = []
    t = build({})
    rc, out = run(t)
    print(("ok   " if rc == 0 else "FAIL ") + "zulässiger Kartenadapter grün")
    if rc != 0:
        failures.append("Basis nicht grün: " + out)
    shutil.rmtree(t)
    for name, files, expect in RED:
        t = build(files)
        symlinks(t, name)
        rc, out = run(t)
        good = rc == 1 and expect in out
        print(("ok   " if good else "FAIL ") + name)
        if not good:
            failures.append(f"{name}: rc={rc}, erwartet '{expect}'\n{out[-400:]}")
        shutil.rmtree(t)
    rc, out = run(REPO)
    print(("ok   " if rc == 0 else "FAIL ") + "heutiger Baum grün")
    if rc != 0:
        failures.append("heutiger Baum: " + out[-600:])
    if failures:
        print("\n".join(failures))
        sys.exit(1)
    print("%d Fälle, alle wie erwartet" % (len(RED) + 2))

main()
