import Foundation

/// Trägt die Hook-Brücke in `~/.claude/settings.json` ein — und wieder aus.
///
/// Das Skript selbst legt die App unter `~/.claude/monitor/hook.sh` ab, nicht im
/// App-Bundle: der eingetragene Pfad muss gültig bleiben, auch wenn die App
/// verschoben, ersetzt oder aus dem Papierkorb wiederhergestellt wird.
enum HookInstaller {
    /// Ereignisse, aus denen sich die Zustände ableiten.
    static let events = [
        "Notification",     // wartet auf Freigabe / auf Antwort
        "PreToolUse",       // arbeitet
        "PostToolUse",      // arbeitet
        "UserPromptSubmit", // arbeitet
        "Stop",             // ruht
        "SessionStart",
        "SessionEnd"
    ]

    enum Status: Equatable {
        case installed
        case partial(missing: [String])
        case notInstalled
        case unreadable(String)

        var isComplete: Bool { self == .installed }

        var text: String {
            switch self {
            case .installed:
                "Eingetragen für alle \(events.count) Ereignisse"
            case let .partial(missing):
                "Teilweise eingetragen — es fehlen: \(missing.joined(separator: ", "))"
            case .notInstalled:
                "Nicht eingetragen — Wartezustände werden bis dahin nur geschätzt"
            case let .unreadable(reason):
                "Einstellungen nicht lesbar: \(reason)"
            }
        }
    }

    enum InstallError: LocalizedError {
        case settingsUnreadable(String)
        case settingsNotWritable(String)

        var errorDescription: String? {
            switch self {
            case let .settingsUnreadable(reason): "settings.json konnte nicht gelesen werden: \(reason)"
            case let .settingsNotWritable(reason): "settings.json konnte nicht geschrieben werden: \(reason)"
            }
        }
    }

    // MARK: - Orte

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var settingsURL: URL { home.appending(path: ".claude/settings.json") }
    static var scriptURL: URL { home.appending(path: ".claude/monitor/hook.sh") }
    static var backupURL: URL { home.appending(path: ".claude/settings.json.bak") }

    /// Bewusst ohne jq oder Python: der Hook läuft bei jedem Werkzeugaufruf.
    private static let script = """
    #!/bin/sh
    # Claude Monitor — Hook-Brücke.
    # Legt das von Claude Code über stdin gereichte JSON im Spool-Ordner ab.
    # Die App liest die Dateien und räumt sie weg.
    set -eu

    dir="${HOME}/.claude/monitor/events"
    mkdir -p "$dir"
    cat > "${dir}/$(date +%s)-$$-${RANDOM:-0}.json"
    exit 0

    """

    // MARK: - Status

    static func status() -> Status {
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else { return .notInstalled }
        let settings: [String: Any]
        do {
            settings = try readSettings()
        } catch {
            return .unreadable(error.localizedDescription)
        }

        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        let missing = events.filter { !isRegistered($0, in: hooks) }
        return switch missing.count {
        case 0: .installed
        case events.count: .notInstalled
        default: .partial(missing: missing)
        }
    }

    private static func isRegistered(_ event: String, in hooks: [String: Any]) -> Bool {
        let matchers = hooks[event] as? [[String: Any]] ?? []
        return matchers.contains { matcher in
            (matcher["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == scriptURL.path }
        }
    }

    // MARK: - Eintragen und entfernen

    static func install() throws {
        try writeScript()
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in events {
            var matchers = hooks[event] as? [[String: Any]] ?? []
            // Ein leerer Matcher greift für alle Werkzeuge; vorhandene Einträge bleiben stehen.
            let index = matchers.firstIndex { ($0["matcher"] as? String ?? "").isEmpty } ?? {
                matchers.append(["matcher": "", "hooks": [[String: Any]]()])
                return matchers.count - 1
            }()

            var commands = matchers[index]["hooks"] as? [[String: Any]] ?? []
            guard !commands.contains(where: { $0["command"] as? String == scriptURL.path }) else { continue }
            commands.append(["type": "command", "command": scriptURL.path, "timeout": 5])
            matchers[index]["hooks"] = commands
            hooks[event] = matchers
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for event in events {
            guard var matchers = hooks[event] as? [[String: Any]] else { continue }
            for index in matchers.indices {
                let commands = (matchers[index]["hooks"] as? [[String: Any]] ?? [])
                    .filter { $0["command"] as? String != scriptURL.path }
                matchers[index]["hooks"] = commands
            }
            // Leere Hüllen aufräumen, aber fremde Einträge unangetastet lassen.
            matchers.removeAll { ($0["hooks"] as? [[String: Any]] ?? []).isEmpty }
            if matchers.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = matchers }
        }

        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        try writeSettings(settings)
        try? FileManager.default.removeItem(at: scriptURL)
    }

    // MARK: - Dateien

    private static func writeScript() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard !data.isEmpty else { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.settingsUnreadable("kein JSON-Objekt")
            }
            return object
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.settingsUnreadable(error.localizedDescription)
        }
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        do {
            // Sicherung vor der ersten Änderung — die Datei gehört dem Menschen, nicht uns.
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.copyItem(at: settingsURL, to: backupURL)
            }
            let data = try JSONSerialization.data(
                withJSONObject: settings,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try (data + Data("\n".utf8)).write(to: settingsURL, options: .atomic)
        } catch {
            throw InstallError.settingsNotWritable(error.localizedDescription)
        }
    }
}
