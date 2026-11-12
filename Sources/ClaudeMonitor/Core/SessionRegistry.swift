import Foundation

/// Claude Code's own registry of running sessions: `~/.claude/sessions/<pid>.json`.
///
/// Every running session writes one file with its pid, its session id, the project folder
/// and — the reason this exists — a `status` it maintains itself. That beats anything
/// derived from transcripts: a session that is not in the registry is not running, and one
/// that is tells us what it is doing instead of us guessing from file timestamps.
struct RegistryEntry: Sendable {
    let pid: pid_t
    let sessionId: String
    let cwd: String?
    let name: String?
    /// One of `busy`, `shell`, `idle`, `waiting` — the vocabulary Claude Code writes.
    let status: String?
    /// Set while the session waits; the exact values are undocumented.
    let waitingFor: String?
    let statusUpdatedAt: Date?
    let startedAt: Date?
    /// `interactive`, `bg`, `daemon` or `daemon-worker`.
    let kind: String?
    let entrypoint: String?

    /// Sessions a person is actually sitting in front of. Daemons and workers are noise.
    var isInteractive: Bool {
        kind == nil || kind == "interactive"
    }
}

enum SessionRegistry {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/sessions", directoryHint: .isDirectory)
    }

    /// Live entries by session id. Files whose process is gone are ignored — Claude Code
    /// does not always get to clean up after a crash or a `kill -9`.
    static func entries() -> [String: RegistryEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var result: [String: RegistryEntry] = [:]
        for file in files where file.pathExtension == "json" {
            guard let entry = parse(file), isRunning(entry.pid), entry.isInteractive else { continue }
            // Should two files name the same session, the one that reported last wins.
            if let existing = result[entry.sessionId],
               (existing.statusUpdatedAt ?? .distantPast) >= (entry.statusUpdatedAt ?? .distantPast) {
                continue
            }
            result[entry.sessionId] = entry
        }
        return result
    }

    private static func parse(_ url: URL) -> RegistryEntry? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = obj["sessionId"] as? String,
              let pid = Fmt.int(obj["pid"]).map(pid_t.init)
        else { return nil }

        return RegistryEntry(
            pid: pid,
            sessionId: sessionId,
            cwd: obj["cwd"] as? String,
            name: (obj["name"] as? String)?.nonEmpty,
            status: obj["status"] as? String,
            waitingFor: (obj["waitingFor"] as? String)?.nonEmpty,
            statusUpdatedAt: Fmt.epochMillis(obj["statusUpdatedAt"]),
            startedAt: Fmt.epochMillis(obj["startedAt"]),
            kind: obj["kind"] as? String,
            entrypoint: obj["entrypoint"] as? String
        )
    }

    /// Signal 0 asks the kernel whether the process exists without disturbing it.
    /// `EPERM` means it exists but belongs to someone else — alive either way.
    private static func isRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
