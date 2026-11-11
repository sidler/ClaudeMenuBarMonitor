import Foundation

/// Ein vom Hook-Skript abgelegtes Ereignis.
///
/// Claude Code reicht Hooks ein JSON-Objekt über stdin; das Skript legt es unverändert
/// in einem Spool-Ordner ab. Dadurch braucht der Hook weder `jq` noch Python.
struct HookEvent: Sendable {
    enum Kind: String, Sendable {
        case notification = "Notification"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case userPromptSubmit = "UserPromptSubmit"
        case stop = "Stop"
        case subagentStop = "SubagentStop"
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
    }

    let sessionId: String
    let kind: Kind
    let at: Date
    let toolName: String?
    let toolSummary: String?
    let toolDetail: String?
    let message: String?
    let cwd: String?

    /// Unterscheidet „Claude braucht eine Freigabe“ von „Claude wartet auf deine Antwort“.
    var isPermissionRequest: Bool {
        guard kind == .notification else { return false }
        let text = (message ?? "").lowercased()
        return text.contains("permission") || text.contains("approve")
            || text.contains("freigabe") || text.contains("erlaubnis")
    }
}

enum HookSpool {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/monitor/events", directoryHint: .isDirectory)

    /// Jüngstes Ereignis je Session. Ältere Dateien werden dabei gleich weggeräumt.
    static func latestBySession(maxAge: TimeInterval) -> [String: HookEvent] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        let cutoff = Date.now.addingTimeInterval(-maxAge)
        var latest: [String: HookEvent] = [:]
        var keep: [String: URL] = [:]
        var superseded: [URL] = []

        for url in entries where url.pathExtension == "json" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            guard modified > cutoff else {
                try? fm.removeItem(at: url)
                continue
            }
            guard let event = parse(url, modified: modified) else {
                // Unlesbar oder fremdes Format: nach einer Stunde weg.
                if modified < Date.now.addingTimeInterval(-3600) { try? fm.removeItem(at: url) }
                continue
            }
            if let existing = latest[event.sessionId], existing.at >= event.at {
                superseded.append(url)
                continue
            }
            if let older = keep[event.sessionId] { superseded.append(older) }
            latest[event.sessionId] = event
            keep[event.sessionId] = url
        }

        // Pro Session zählt nur das jüngste Ereignis — der Rest ist verbraucht.
        // Ohne das wächst der Spool um eine Datei je Werkzeugaufruf.
        for url in superseded { try? fm.removeItem(at: url) }

        return latest
    }

    private static func parse(_ url: URL, modified: Date) -> HookEvent? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = obj["session_id"] as? String,
              let raw = obj["hook_event_name"] as? String,
              let kind = HookEvent.Kind(rawValue: raw)
        else { return nil }

        let toolName = obj["tool_name"] as? String
        var short: String?
        var long: String?
        if let toolName {
            let summary = TranscriptParser.toolSummary(["name": toolName, "input": obj["tool_input"] ?? [:]])
            short = summary.short
            long = summary.long
        }

        return HookEvent(
            sessionId: sessionId,
            kind: kind,
            at: Fmt.date(obj["timestamp"]) ?? modified,
            toolName: toolName,
            toolSummary: short,
            toolDetail: long,
            message: obj["message"] as? String,
            cwd: obj["cwd"] as? String
        )
    }
}
