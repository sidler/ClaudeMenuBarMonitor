import AppKit

/// Opens the project folder in the terminal of choice.
///
/// Two routes, because terminals differ: Terminal.app and iTerm accept a folder
/// through Launch Services, while others — Tabby for one — declare no document
/// types at all and ignore it. Those get a freely chosen command.
enum TerminalLauncher {
    struct Entry: Identifiable, Hashable, Sendable {
        let id: String      // bundle id, stable even when the app moves
        let name: String
        let url: URL
        /// Whether the app accepts folders according to its bundle.
        let acceptsFolders: Bool
    }

    static let customID = "custom"
    static let defaultCommand = "open -a Terminal {dir}"

    /// Terminals that take no folder through Launch Services but ship a URL scheme
    /// with a fitting command. Tabby knows `open [directory]` —
    /// it sits in its own parser config, and it registers the scheme itself.
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

    /// The terminals actually installed, in the order of the candidate list.
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
            // A dedicated URL command beats Launch Services: only that way does the folder arrive.
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

    /// Paths may contain spaces and apostrophes.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// For the query part of a URL: `&`, `=` and `#` have to be encoded.
    private static func urlEncoded(_ path: String) -> String {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
}
