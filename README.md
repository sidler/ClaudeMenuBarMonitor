# Claude Monitor

Menüleisten-App für macOS, die alle Claude-Code-Sessions auf diesem Rechner auflistet:
ob eine Session gerade **arbeitet**, **auf dich wartet** oder **ruht**. Ein Popover zeigt
kurze Details zur ausgewählten Session.

## Voraussetzungen

- macOS 27 oder neuer (die App nutzt Liquid Glass: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`)
- Swift 6.4 (Command Line Tools reichen — Xcode ist nicht nötig)

## Bauen und starten

```sh
Scripts/bundle.sh release
open build/ClaudeMonitor.app
```

Die App hat kein Dock-Symbol (`LSUIElement`). Beenden über das Panel oder ⌘Q bei offenem Panel.

Zum Prüfen der Datenschicht ohne Oberfläche:

```sh
.build/release/ClaudeMonitor --scan
```

## Hooks einrichten (empfohlen)

In den Einstellungen der App (Zahnrad im Panel) gibt es dafür einen Knopf: **Hooks eintragen**.
Er zeigt auch, ob die Einträge vollständig sind, und nimmt sie wieder zurück.

Ohne Hooks leitet die App den Zustand allein aus den Transkriptdateien ab. Dann ist
„arbeitet“ zuverlässig, „wartet auf Freigabe“ aber nur geschätzt: eine hängende
Berechtigungsabfrage sieht im Transkript aus wie ein langer Werkzeugaufruf.

Was der Knopf tut:

1. legt `~/.claude/monitor/hook.sh` an (ein Vierzeiler, der das von Claude Code über stdin
   gereichte JSON in `~/.claude/monitor/events/` ablegt — kein `jq`, kein Python, kein Netz),
2. trägt dieses Skript in `~/.claude/settings.json` für `Notification`, `PreToolUse`,
   `PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart` und `SessionEnd` ein.

Vorhandene Hooks bleiben stehen, vor jeder Änderung entsteht `settings.json.bak`, und ein
zweiter Lauf ändert nichts. Der eingetragene Pfad liegt bewusst im Benutzerordner und nicht
im App-Bundle — er bleibt gültig, wenn die App verschoben oder ersetzt wird.

Dasselbe ohne Oberfläche:

```sh
.build/release/ClaudeMonitor --hooks            # Status
.build/release/ClaudeMonitor --install-hooks
.build/release/ClaudeMonitor --uninstall-hooks
```

Die App liest die Spool-Dateien bei jedem Scan und räumt sie weg: pro Session bleibt genau
das jüngste Ereignis liegen.

## Die fünf Zustände

| Zustand | Bedeutung | Woran erkannt |
| --- | --- | --- |
| **Freigabe nötig** | Berechtigungsabfrage offen | `Notification`-Hook mit Berechtigungstext |
| **Rückfrage offen** | Turn beendet, Claude fragt | `Notification`-Hook ohne Berechtigungstext |
| **Arbeitet** | Turn läuft | letzter Eintrag ist Werkzeugaufruf/-ergebnis, Datei jünger als 90 s |
| **Ruht** | Antwort liegt vor | letzter Eintrag ist Assistant-Text, oder `Stop`-Hook |
| **Abgebrochen** | Turn gestoppt oder Fehler | Fehlereintrag im Transkript |

Sortierung: wartet → arbeitet → ruht, innerhalb der Gruppe jüngste Änderung zuerst.
Mitteilungen gibt es nur beim Übergang nach „wartet auf dich“, einmal je Session und Turn.
Sessions ohne Aktivität seit 24 Stunden verschwinden aus der Liste.

## Terminal

In den Einstellungen lässt sich das Terminal für „Im Terminal öffnen“ wählen. Erkannt werden
Terminal.app, iTerm2, Tabby, Warp, Ghostty, kitty, Alacritty, WezTerm und Hyper, sofern
installiert — dazu „Eigener Befehl“ mit `{dir}` als Platzhalter für den Projektordner.

Der Unterschied ist nicht kosmetisch: Terminal.app und iTerm melden Launch Services, dass
sie Ordner öffnen können. Tabby und einige andere tun das nicht — sie starten dann zwar,
wechseln aber nicht ins Verzeichnis. Die Einstellungen warnen bei solchen Apps und
verweisen auf den eigenen Befehl; der Knopf **Testen** öffnet sofort einen Projektordner,
damit die Zeile nicht erst im Alltag auffällt.

## Aufbau

```
Sources/ClaudeMonitor/
  App/      Einstiegspunkt, --scan-Modus
  Model/    Session, SessionState
  Core/     TranscriptParser, HookEvents, HookInstaller, SessionScanner, FSEventWatcher,
            SessionStore, TerminalLauncher, Notifier
  UI/       MenuBarLabel, PanelView, SessionRow, SessionDetailView, SettingsView, Theme
```

- **TranscriptParser** liest nur die letzten 512 KB einer `.jsonl` — die Transkripte werden
  mehrere Megabyte groß, und alles Angezeigte steht am Ende.
- **FSEventWatcher** beobachtet `~/.claude/projects` und den Hook-Spool mit
  `kFSEventStreamCreateFlagFileEvents`, also inklusive Änderungen an Dateiinhalten.
  Debounce 150 ms, dazu alle 10 Sekunden ein Sicherheitsscan.
- **SessionScanner** läuft außerhalb des Main-Actors und liefert `Sendable`-Werte zurück.
- Gelesen wird nur. Die App schreibt nichts in `~/.claude/projects` und schickt nichts weg.

## Grenzen

- **Prompts und Werkzeuge** im Popover zählen nur, was im gelesenen Dateiende steht —
  nicht die ganze Session. Kosten, Laufzeit und geänderte Zeilen stammen dagegen aus den
  `cost-state`-Einträgen und gelten für die ganze Session.
- **Kontextfenster**: die Belegung ist die Prompt-Größe des letzten API-Aufrufs. Das Limit
  wird auf 200k geschätzt und auf 1 Mio. hochgesetzt, sobald die Messung darüber liegt.
- **Menüleistensymbol**: ein SwiftUI-Label in `MenuBarExtra` wird von macOS als Template
  gerendert, die Farbe fällt dabei weg. `MenuBarIcon` zeichnet das Symbol deshalb von Hand
  als `NSImage` mit `isTemplate = false`. Die Zustände unterscheiden sich zusätzlich in der
  Form des Punkts (gefüllt / Ring) und durch die Zahl daneben. Das Symbol selbst ist in den
  Einstellungen wählbar; zur Wahl stehen nur Symbole, die bei 16 Pixeln lesbar bleiben.
  Alle Kombinationen ansehen mit `ClaudeMonitor --icon-preview /tmp/icons.png`.
- Ohne Xcode gibt es keine SwiftUI-Previews: `@State` ist inzwischen ein Makro, dessen
  Plugin nur Xcode mitbringt. Die App kommt deshalb ohne `@State` aus — die Auswahl liegt
  im `SessionStore`.

## Lizenz

MIT — siehe [LICENSE](LICENSE).
