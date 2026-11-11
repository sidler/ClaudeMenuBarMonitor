import Foundation

/// One entry in a session's history.
struct ActivityItem: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable { case prompt, tool, answer, notice }

    let id: String
    let at: Date
    let kind: Kind
    let text: String
}

/// A session's state as the panel shows it.
struct Session: Identifiable, Sendable, Hashable {
    let id: String                 // sessionId
    let transcript: URL
    let projectSlug: String

    var title: String              // customTitle, or the project folder
    var cwd: String?
    var gitBranch: String?
    var model: String?
    var permissionMode: String?

    var state: SessionState
    var stateSince: Date
    var lastActivity: Date

    /// One-liner under the name: “Bash · composer update”.
    var headline: String
    /// Longer text for the popover: the command or question verbatim.
    var detail: String?

    var startedAt: Date?
    var turns: Int
    var toolCalls: Int
    var costUSD: Double?
    var linesAdded: Int
    var linesRemoved: Int
    var contextTokens: Int?
    var contextLimit: Int
    var lastPrompt: String?
    var recent: [ActivityItem]

    var projectName: String {
        if let cwd, let name = URL(fileURLWithPath: cwd).lastPathComponent.nonEmpty { return name }
        return projectSlug.split(separator: "-").last.map(String.init) ?? projectSlug
    }

    var contextFraction: Double? {
        guard let contextTokens, contextLimit > 0 else { return nil }
        return min(1, Double(contextTokens) / Double(contextLimit))
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }

    /// Flattens Markdown into one line of prose: links become their link text,
    /// emphasis and headings fall away.
    var flattenedMarkdown: String {
        var text = self
        if let links = try? Regex(#"\[([^\]]+)\]\([^)]+\)"#) {
            text = text.replacing(links) { match in
                (match.output[1].substring).map(String.init) ?? ""
            }
        }
        return text
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Truncates to `limit` characters without cutting a word in half.
    func truncated(to limit: Int) -> String {
        let flat = replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return cut[..<space] + "…"
        }
        return cut + "…"
    }
}
