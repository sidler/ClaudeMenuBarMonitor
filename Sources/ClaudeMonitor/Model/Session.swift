import Foundation

/// Ein Eintrag im Verlauf einer Session.
struct ActivityItem: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable { case prompt, tool, answer, notice }

    let id: String
    let at: Date
    let kind: Kind
    let text: String
}

/// Der Zustand einer Session, so wie ihn das Panel zeigt.
struct Session: Identifiable, Sendable, Hashable {
    let id: String                 // sessionId
    let transcript: URL
    let projectSlug: String

    var title: String              // customTitle oder Projektordner
    var cwd: String?
    var gitBranch: String?
    var model: String?
    var permissionMode: String?

    var state: SessionState
    var stateSince: Date
    var lastActivity: Date

    /// Einzeiler unter dem Namen: „Bash · composer update“.
    var headline: String
    /// Längerer Text fürs Popover: Kommando oder Rückfrage im Wortlaut.
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

    /// Macht aus Markdown eine Zeile Fließtext: Links werden zu ihrem Linktext,
    /// Auszeichnungen und Überschriften fallen weg.
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

    /// Kürzt auf `limit` Zeichen, bricht dabei nicht mitten im Wort ab.
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
