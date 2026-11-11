import AppKit

/// Öffnet den Projektordner im Terminal der Wahl.
///
/// Zwei Wege, weil Terminals sich unterschiedlich verhalten: Terminal.app und iTerm nehmen
/// einen Ordner über Launch Services entgegen, andere — Tabby etwa — melden gar keine
/// Dokumenttypen an und ignorieren ihn. Für die gibt es einen frei wählbaren Befehl.
enum TerminalLauncher {
    struct Entry: Identifiable, Hashable, Sendable {
        let id: String      // Bundle-ID, stabil auch wenn die App umzieht
        let name: String
        let url: URL
        /// Ob die App laut ihrem Bundle Ordner entgegennimmt.
        let acceptsFolders: Bool
    }

    static let customID = "custom"
    static let defaultCommand = "open -a Terminal {dir}"

    /// Terminals, die keinen Ordner über Launch Services annehmen, aber ein URL-Schema
    /// mit einem passenden Kommando mitbringen. Tabby etwa kennt `open [directory]` —
    /// nachzulesen in seiner Parser-Konfiguration, das Schema registriert es selbst.
    private static let urlSchemes: [String: String] = [
        "org.tabby": "tabby://open?directory={dirurl}"
    ]

    private static let candidates = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "org.tabby",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "co.zeit.hyper"
    ]

    /// Die tatsächlich installierten Terminals, in der Reihenfolge der Kandidatenliste.
    static func installed() -> [Entry] {
        candidates.compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            let bundle = Bundle(url: url)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let types = bundle?.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] ?? []
            let acceptsFolders = types.contains { type in
                let content = type["LSItemContentTypes"] as? [String] ?? []
                return content.contains("public.directory") || content.contains("public.folder")
            }
            return Entry(
                id: id,
                name: name,
                url: url,
                acceptsFolders: acceptsFolders || urlSchemes[id] != nil
            )
        }
    }

    enum LaunchError: LocalizedError {
        case appMissing(String)
        case commandFailed(String)
        case urlInvalid(String)

        var errorDescription: String? {
            switch self {
            case let .appMissing(id): "Terminal not found: \(id)"
            case let .commandFailed(reason): "Command failed: \(reason)"
            case let .urlInvalid(url): "Invalid URL: \(url)"
            }
        }
    }

    static func open(directory: URL) throws {
        let defaults = UserDefaults.standard
        let bundleID = defaults.string(forKey: "terminalBundleID") ?? "com.apple.Terminal"

        guard bundleID == customID else {
            // Eigenes URL-Kommando schlägt Launch Services: nur so landet der Ordner an.
            if let template = urlSchemes[bundleID] {
                let raw = template.replacingOccurrences(of: "{dirurl}", with: urlEncoded(directory.path))
                guard let url = URL(string: raw) else { throw LaunchError.urlInvalid(raw) }
                NSWorkspace.shared.open(url)
                return
            }
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw LaunchError.appMissing(bundleID)
            }
            NSWorkspace.shared.open([directory], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return
        }

        let template = defaults.string(forKey: "terminalCommand") ?? defaultCommand
        let filled = template
            .replacingOccurrences(of: "{dirurl}", with: urlEncoded(directory.path))
            .replacingOccurrences(of: "{dir}", with: shellQuoted(directory.path))
        try run(command: filled)
    }

    private static func run(command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            throw LaunchError.commandFailed(error.localizedDescription)
        }
    }

    /// Pfade dürfen Leerzeichen und Apostrophe enthalten.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Für den Query-Teil einer Adresse: `&`, `=` und `#` müssen kodiert sein.
    private static func urlEncoded(_ path: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}
