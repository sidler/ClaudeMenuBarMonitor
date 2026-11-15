import Foundation

/// Registers a status line bridge in `~/.claude/settings.json` — and removes it again.
///
/// Claude Code hands its status line command a JSON payload on stdin, and that payload is
/// the only place on this machine where the plan's two windows appear while they are still
/// running: `rate_limits.five_hour` and `rate_limits.seven_day`, each with a percentage and
/// the reset time the API reported. Hooks never carry them, and the sample the desktop app
/// writes can sit untouched for days.
///
/// A status line is a single setting, so one that is already configured is not replaced but
/// chained: the bridge keeps the payload, hands it to the previous command and prints
/// whatever that prints. The line looks exactly as it did.
enum StatusLineInstaller {
    enum Status: Equatable {
        /// Our bridge is the configured status line.
        case installed(chained: String?)
        /// Someone else's status line is configured — installing would chain it.
        case foreign(String)
        case notInstalled
        case unreadable(String)

        var isComplete: Bool {
            if case .installed = self { return true }
            return false
        }

        var text: String {
            switch self {
            case let .installed(chained?):
                "Installed — passes the line through to \(chained)"
            case .installed:
                "Installed"
            case let .foreign(command):
                "Not installed — \(command) is configured and would be kept"
            case .notInstalled:
                "Not installed — percentages stay as old as the desktop app's last sample"
            case let .unreadable(reason):
                "Settings unreadable: \(reason)"
            }
        }
    }

    enum InstallError: LocalizedError {
        case settingsUnreadable(String)
        case settingsNotWritable(String)

        var errorDescription: String? {
            switch self {
            case let .settingsUnreadable(reason): "Could not read settings.json: \(reason)"
            case let .settingsNotWritable(reason): "Could not write settings.json: \(reason)"
            }
        }
    }

    // MARK: - Locations

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var settingsURL: URL { home.appending(path: ".claude/settings.json") }
    static var backupURL: URL { home.appending(path: ".claude/settings.json.bak") }
    static var scriptURL: URL { home.appending(path: ".claude/monitor/statusline.sh") }
    /// The status line that was configured before, as a script the bridge can run …
    static var chainScriptURL: URL { home.appending(path: ".claude/monitor/statusline-chain.sh") }
    /// … and verbatim, so removing the bridge can put it back exactly as it was.
    static var chainURL: URL { home.appending(path: ".claude/monitor/statusline-chain.json") }
    /// Where the bridge leaves the payload for `UsageReader`.
    static var payloadURL: URL { home.appending(path: ".claude/monitor/statusline.json") }

    /// Deliberately without jq or Python: this runs on every redraw of the status line.
    private static let script = """
    #!/bin/sh
    # Claude Monitor — status line bridge.
    #
    # Claude Code hands the status line a JSON payload on stdin. It is the only place on
    # this machine that carries the plan's five-hour and seven-day windows while they run,
    # so the app reads them from the copy this script leaves behind.
    #
    # The payload is passed on unchanged to the status line that was configured before,
    # and its output is printed as it is: the line looks exactly as it did.
    set -eu

    dir="${HOME}/.claude/monitor"
    out="${dir}/statusline.json"
    chain="${dir}/statusline-chain.sh"
    mkdir -p "$dir"

    tmp="${dir}/.statusline-$$.json"
    cat > "$tmp"
    # Renamed into place rather than written in place: the app may read at any moment.
    mv -f "$tmp" "$out"

    if [ -x "$chain" ]; then
        exec "$chain" < "$out"
    fi
    exit 0

    """

    // MARK: - Status

    static func status() -> Status {
        let settings: [String: Any]
        do {
            settings = try readSettings()
        } catch {
            return .unreadable(error.localizedDescription)
        }

        let configured = (settings["statusLine"] as? [String: Any])?["command"] as? String
        switch configured {
        case scriptURL.path:
            guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else { return .notInstalled }
            return .installed(chained: chainedCommand())
        case let other?:
            return .foreign(other)
        case nil:
            return .notInstalled
        }
    }

    /// The command the bridge hands the line on to, as it was configured.
    static func chainedCommand() -> String? {
        guard let data = try? Data(contentsOf: chainURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["command"] as? String
    }

    // MARK: - Install and remove

    static func install() throws {
        var settings = try readSettings()
        let previous = settings["statusLine"] as? [String: Any]

        // Re-installing must not chain the bridge to itself.
        if let previous, previous["command"] as? String != scriptURL.path {
            try writeChain(previous)
        }

        try write(script, to: scriptURL)

        // `padding` and `refreshInterval` are the user's, not ours — they stay.
        var line: [String: Any] = ["type": "command", "command": scriptURL.path]
        for key in ["padding", "refreshInterval"] {
            if let value = previous?[key] { line[key] = value }
        }
        settings["statusLine"] = line
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = try readSettings()

        // Only hand the setting back if it is still ours — a status line configured in the
        // meantime belongs to whoever configured it.
        if (settings["statusLine"] as? [String: Any])?["command"] as? String == scriptURL.path {
            if let data = try? Data(contentsOf: chainURL),
               let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings["statusLine"] = previous
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings)
        }

        let fm = FileManager.default
        for url in [scriptURL, chainScriptURL, chainURL, payloadURL] {
            try? fm.removeItem(at: url)
        }
    }

    // MARK: - Files

    /// Keeps the previous status line twice: as JSON to restore, as a script to run.
    private static func writeChain(_ previous: [String: Any]) throws {
        guard let command = previous["command"] as? String, !command.isEmpty else { return }
        let data = try JSONSerialization.data(
            withJSONObject: previous,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try createDirectory()
        try (data + Data("\n".utf8)).write(to: chainURL, options: .atomic)

        // The command is a shell snippet, so it goes in verbatim as the body of a script
        // rather than through any quoting of ours. stdin is inherited from the bridge.
        try write("""
        #!/bin/sh
        # Claude Monitor — the status line that was configured before the bridge.
        # Put back into settings.json when the bridge is removed.
        \(command)

        """, to: chainScriptURL)
    }

    private static func write(_ contents: String, to url: URL) throws {
        try createDirectory()
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func createDirectory() throws {
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard !data.isEmpty else { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.settingsUnreadable("not a JSON object")
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
            // Back up before the first change — the file belongs to the user, not to us.
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
