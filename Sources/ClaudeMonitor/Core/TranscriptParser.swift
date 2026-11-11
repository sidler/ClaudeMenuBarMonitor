import Foundation

/// Was sich aus dem Ende einer Transkriptdatei ablesen lässt.
struct TranscriptDigest: Sendable {
    enum Kind: Sendable { case userPrompt, toolUse, toolResult, assistantText, thinking, other }

    var cwd: String?
    var gitBranch: String?
    var model: String?
    var customTitle: String?
    var lastPrompt: String?
    var permissionMode: String?

    var lastEntryAt: Date?
    var lastKind: Kind = .other
    var headline: String?
    var detail: String?

    var contextTokens: Int?
    var costUSD: Double?
    var linesAdded = 0
    var linesRemoved = 0
    var startedAt: Date?
    var turns = 0
    var toolCalls = 0
    var errorAt: Date?
    var recent: [ActivityItem] = []
}

/// Liest das Ende einer `.jsonl`-Datei und leitet daraus ab, was die Session gerade tut.
///
/// Gelesen wird nur der Schwanz der Datei — die Transkripte werden mehrere Megabyte groß,
/// und alles, was das Panel zeigt, steht in den letzten Einträgen.
enum TranscriptParser {
    static let tailBytes = 512 * 1024
    static let recentLimit = 8

    static func digest(of url: URL) -> TranscriptDigest? {
        guard let lines = tailLines(of: url) else { return nil }
        var d = TranscriptDigest()
        var lastToolSummary: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String
            else { continue }

            // Felder, die in vielen Eintragsarten stehen — immer den jüngsten Wert behalten.
            if let v = obj["cwd"] as? String { d.cwd = v }
            if let v = obj["gitBranch"] as? String, !v.isEmpty { d.gitBranch = v }

            switch type {
            case "custom-title":
                d.customTitle = (obj["customTitle"] as? String)?.nonEmpty
            case "last-prompt":
                d.lastPrompt = (obj["lastPrompt"] as? String)?.truncated(to: 180)
            case "mode":
                d.permissionMode = obj["mode"] as? String
            case "relocated":
                if let v = obj["relocatedCwd"] as? String { d.cwd = v }
            case "cost-state":
                d.costUSD = Fmt.double(obj["totalCostUSD"])
                d.linesAdded = Fmt.int(obj["totalLinesAdded"]) ?? d.linesAdded
                d.linesRemoved = Fmt.int(obj["totalLinesRemoved"]) ?? d.linesRemoved
                d.startedAt = Fmt.epochMillis(obj["startTime"]) ?? d.startedAt
            case "system":
                let at = Fmt.date(obj["timestamp"])
                if (obj["level"] as? String) == "error" || (obj["hookErrors"] as? [Any])?.isEmpty == false {
                    d.errorAt = at
                }
                if let stop = obj["stopReason"] as? String, !stop.isEmpty, stop != "end_turn" {
                    d.errorAt = at
                }
            case "user":
                guard (obj["isSidechain"] as? Bool) != true else { continue }
                let at = Fmt.date(obj["timestamp"])
                let msg = obj["message"] as? [String: Any]
                let blocks = contentBlocks(msg?["content"])
                let isToolResult = blocks.contains { ($0["type"] as? String) == "tool_result" }
                d.lastEntryAt = at ?? d.lastEntryAt
                if isToolResult {
                    d.lastKind = .toolResult
                    d.headline = lastToolSummary.map { "\($0) · Ergebnis" } ?? "Werkzeug · Ergebnis"
                } else {
                    d.turns += 1
                    d.lastKind = .userPrompt
                    let text = plainText(msg?["content"])
                    d.headline = text.map { "Du: \($0.truncated(to: 140))" }
                    d.detail = text?.truncated(to: 240)
                    if let at, let text { append(&d, ActivityItem(id: "u-\(at.timeIntervalSince1970)", at: at, kind: .prompt, text: text.truncated(to: 90))) }
                }
            case "assistant":
                guard (obj["isSidechain"] as? Bool) != true else { continue }
                let at = Fmt.date(obj["timestamp"])
                d.lastEntryAt = at ?? d.lastEntryAt
                guard let msg = obj["message"] as? [String: Any] else { continue }
                if let m = msg["model"] as? String { d.model = m }
                if let usage = msg["usage"] as? [String: Any] { d.contextTokens = contextSize(usage) ?? d.contextTokens }

                let blocks = contentBlocks(msg["content"])
                if let tool = blocks.last(where: { ($0["type"] as? String) == "tool_use" }) {
                    d.toolCalls += 1
                    let summary = toolSummary(tool)
                    lastToolSummary = summary.short
                    d.lastKind = .toolUse
                    d.headline = summary.short
                    d.detail = summary.long
                    if let at { append(&d, ActivityItem(id: "t-\(at.timeIntervalSince1970)", at: at, kind: .tool, text: summary.short)) }
                } else if let text = blocks.compactMap({ ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }).last?.flattenedMarkdown.nonEmpty {
                    d.lastKind = .assistantText
                    d.headline = text.truncated(to: 140)
                    d.detail = text.truncated(to: 280)
                    if let at { append(&d, ActivityItem(id: "a-\(at.timeIntervalSince1970)", at: at, kind: .answer, text: text.truncated(to: 90))) }
                } else if blocks.contains(where: { ($0["type"] as? String) == "thinking" }) {
                    d.lastKind = .thinking
                    d.headline = "Denkt nach"
                }
            default:
                continue
            }
        }
        return d
    }

    private static func append(_ d: inout TranscriptDigest, _ item: ActivityItem) {
        d.recent.append(item)
        if d.recent.count > recentLimit { d.recent.removeFirst(d.recent.count - recentLimit) }
    }

    private static func contentBlocks(_ raw: Any?) -> [[String: Any]] {
        (raw as? [[String: Any]]) ?? []
    }

    private static func plainText(_ raw: Any?) -> String? {
        if let s = raw as? String { return s.nonEmpty }
        let texts = contentBlocks(raw).compactMap { $0["text"] as? String }
        return texts.joined(separator: " ").nonEmpty
    }

    /// Belegung des Kontextfensters: alles, was beim letzten Aufruf im Prompt stand.
    /// Die Ausgabe zählt nicht mit — sie steht erst im nächsten Aufruf im Kontext.
    private static func contextSize(_ usage: [String: Any]) -> Int? {
        let input = Fmt.int(usage["input_tokens"]) ?? 0
        let cacheRead = Fmt.int(usage["cache_read_input_tokens"]) ?? 0
        let cacheWrite = Fmt.int(usage["cache_creation_input_tokens"]) ?? 0
        let total = input + cacheRead + cacheWrite
        return total > 0 ? total : nil
    }

    /// „Bash · composer update“ für die Liste, der volle Befehl fürs Popover.
    static func toolSummary(_ block: [String: Any]) -> (short: String, long: String?) {
        let name = (block["name"] as? String) ?? "Werkzeug"
        let input = (block["input"] as? [String: Any]) ?? [:]
        let display = name.hasPrefix("mcp__")
            ? name.split(separator: "_").filter { !$0.isEmpty }.dropFirst().first.map(String.init) ?? name
            : name

        func path(_ key: String) -> String? {
            (input[key] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        }

        let detail: String? = switch name {
        case "Bash": input["command"] as? String
        case "Read", "Edit", "Write", "NotebookEdit": path("file_path")
        case "Grep": (input["pattern"] as? String).map { "/\($0)/" }
        case "Glob": input["pattern"] as? String
        case "Task", "Agent": input["description"] as? String
        case "WebFetch": (input["url"] as? String).flatMap { URL(string: $0)?.host() }
        case "WebSearch": input["query"] as? String
        default: input.values.compactMap { $0 as? String }.max(by: { $0.count < $1.count })
        }

        guard let detail = detail?.nonEmpty else { return (display, nil) }
        return ("\(display) · \(detail.truncated(to: 48))", detail.truncated(to: 300))
    }

    /// Letzte `tailBytes` der Datei, ohne die angeschnittene erste Zeile.
    private static func tailLines(of url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        var text = String(decoding: data, as: UTF8.self)
        if offset > 0, let nl = text.firstIndex(of: "\n") { text = String(text[text.index(after: nl)...]) }
        return text.split(separator: "\n").map(String.init)
    }
}
