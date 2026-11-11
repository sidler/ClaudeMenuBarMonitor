import Foundation

/// An event dropped by the hook script.
///
/// Claude Code hands hooks a JSON object on stdin; the script stores it unchanged
/// in a spool folder. That way the hook needs neither `jq` nor Python.
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

    /// Tells “Claude needs permission” apart from “Claude is waiting for your input”.
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

    /// Newest event per session. Older files are cleared out along the way.
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
                // Unreadable or foreign format: gone after an hour.
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

        // Only the newest event per session counts — the rest is spent.
        // Without this the spool grows by one file per tool call.
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
