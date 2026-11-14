# Hinweise für Claude

Verbindlich ist [AGENTS.md](AGENTS.md). Lies sie vor jeder Änderung.

- Code und Spezifikation im selben Branch ändern; danach `python3 tool/spec_tool.py build` und `check`.
- Commit-Trailer: nur `Co-Authored-By: Claude <Modell> <noreply@anthropic.com>`, keine `Claude-Session`-Zeile.
