import Foundation

/// `ClaudeMonitor --scan` gibt aus, was die Datenschicht gerade sieht.
/// Gedacht zum Prüfen der Zustandslogik, ohne die Menüleiste zu öffnen.
enum ScanDump {
    static func run() {
        let sessions = SessionScanner.scan(ScanConfig())
        guard !sessions.isEmpty else {
            print("Keine Session der letzten 24 Stunden.")
            return
        }

        print("\(sessions.count) Session(s)\n")
        for session in sessions {
            let age = Fmt.elapsed(since: session.lastActivity)
            print("[\(session.state.title.padded(to: 15))] \(session.title.padded(to: 22)) \(age.padded(to: 7)) \(session.headline)")
            var meta: [String] = []
            if let branch = session.gitBranch { meta.append(branch) }
            if let model = Fmt.modelName(session.model) { meta.append(model) }
            if let cost = session.costUSD { meta.append(Fmt.money(cost)) }
            if let tokens = session.contextTokens { meta.append("\(Fmt.tokens(tokens)) Kontext") }
            meta.append("\(session.turns) Turns, \(session.toolCalls) Werkzeuge")
            meta.append("+\(session.linesAdded)/−\(session.linesRemoved)")
            print("                   \(meta.joined(separator: " · "))")
        }
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? String(prefix(width)) : self + String(repeating: " ", count: width - count)
    }
}
