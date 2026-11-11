import Foundation

/// `ClaudeMonitor --scan` prints what the data layer currently sees.
/// Meant for checking the state logic without opening the menu bar.
enum ScanDump {
    static func run() {
        let sessions = SessionScanner.scan(ScanConfig())
        guard !sessions.isEmpty else {
            print("No sessions in the last 24 hours.")
            return
        }

        print("\(sessions.count) session(s)\n")
        for session in sessions {
            let age = Fmt.elapsed(since: session.lastActivity)
            print("[\(session.state.title.padded(to: 15))] \(session.title.padded(to: 22)) \(age.padded(to: 7)) \(session.headline)")
            var meta: [String] = []
            if let branch = session.gitBranch { meta.append(branch) }
            if let model = Fmt.modelName(session.model) { meta.append(model) }
            if let cost = session.costUSD { meta.append(Fmt.money(cost)) }
            if let tokens = session.contextTokens { meta.append("\(Fmt.tokens(tokens)) context") }
            meta.append("\(session.turns) prompts, \(session.toolCalls) tools")
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
