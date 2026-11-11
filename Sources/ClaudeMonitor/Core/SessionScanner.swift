import Foundation

struct ScanConfig: Sendable {
    var projectsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects", directoryHint: .isDirectory)
    /// Sessions ohne Aktivität seit dieser Spanne verschwinden aus der Liste.
    var maxAge: TimeInterval = 24 * 3600
    /// So lange ohne neue Zeile gilt eine Session noch als arbeitend.
    var idleAfter: TimeInterval = 90
    var contextLimit = 200_000
}

/// Liest alle jungen Transkripte und leitet daraus den Zustand jeder Session ab.
///
/// Läuft bewusst außerhalb des Main-Actors: der Scan fasst Dateien an.
enum SessionScanner {
    static func scan(_ config: ScanConfig, now: Date = .now) -> [Session] {
        let fm = FileManager.default
        let hooks = HookSpool.latestBySession(maxAge: config.maxAge)
        let cutoff = now.addingTimeInterval(-config.maxAge)

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: config.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sessions: [Session] = []

        for projectDir in projectDirs {
            guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let files = try? fm.contentsOfDirectory(
                      at: projectDir,
                      includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                      options: [.skipsHiddenFiles]
                  )
            else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                let modified = values?.contentModificationDate ?? .distantPast
                let created = values?.creationDate
                guard modified > cutoff else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                guard let digest = TranscriptParser.digest(of: file) else { continue }
                sessions.append(makeSession(
                    id: id,
                    file: file,
                    slug: projectDir.lastPathComponent,
                    modified: modified,
                    digest: digest,
                    created: created,
                    hook: hooks[id],
                    config: config,
                    now: now
                ))
            }
        }

        return sessions.sorted(by: order)
    }

    /// Wartet → arbeitet → ruht; innerhalb der Gruppe die jüngste Änderung zuerst.
    static func order(_ a: Session, _ b: Session) -> Bool {
        if a.state.group != b.state.group { return a.state.group < b.state.group }
        if a.state != b.state { return a.state < b.state }
        return a.lastActivity > b.lastActivity
    }

    private static func makeSession(
        id: String,
        file: URL,
        slug: String,
        modified: Date,
        digest: TranscriptDigest,
        created: Date?,
        hook: HookEvent?,
        config: ScanConfig,
        now: Date
    ) -> Session {
        let activity = max(modified, digest.lastEntryAt ?? .distantPast)
        var state = transcriptState(digest, activity: activity, config: config, now: now)
        var since = digest.lastEntryAt ?? modified
        var headline = digest.headline ?? state.title
        var detail = digest.detail

        // Der Hook weiß mehr als die Datei — aber nur, solange nichts Jüngeres passiert ist.
        if let hook, hook.at >= activity.addingTimeInterval(-2) {
            since = hook.at
            switch hook.kind {
            case .notification:
                if hook.isPermissionRequest {
                    state = .awaitingApproval
                    headline = hook.toolSummary ?? digest.headline ?? "Freigabe angefragt"
                    detail = hook.toolDetail ?? hook.message
                } else {
                    state = .awaitingReply
                    headline = digest.headline ?? "Wartet auf deine Antwort"
                    detail = digest.detail ?? hook.message
                }
            case .preToolUse, .postToolUse, .userPromptSubmit, .sessionStart:
                state = .working
                headline = hook.toolSummary ?? headline
            case .stop, .subagentStop, .sessionEnd:
                state = .idle
            }
        }

        return Session(
            id: id,
            transcript: file,
            projectSlug: slug,
            title: digest.customTitle ?? URL(fileURLWithPath: digest.cwd ?? slug).lastPathComponent,
            cwd: digest.cwd ?? hook?.cwd,
            gitBranch: digest.gitBranch,
            model: digest.model,
            permissionMode: digest.permissionMode,
            state: state,
            stateSince: since,
            lastActivity: activity,
            headline: headline,
            detail: detail,
            startedAt: digest.startedAt ?? created,
            turns: digest.turns,
            toolCalls: digest.toolCalls,
            costUSD: digest.costUSD,
            linesAdded: digest.linesAdded,
            linesRemoved: digest.linesRemoved,
            contextTokens: digest.contextTokens,
            contextLimit: (digest.contextTokens ?? 0) > config.contextLimit ? 1_000_000 : config.contextLimit,
            lastPrompt: digest.lastPrompt,
            recent: digest.recent.reversed()
        )
    }

    private static func transcriptState(
        _ digest: TranscriptDigest,
        activity: Date,
        config: ScanConfig,
        now: Date
    ) -> SessionState {
        if let error = digest.errorAt, error >= (digest.lastEntryAt ?? error) { return .aborted }
        let fresh = now.timeIntervalSince(activity) < config.idleAfter
        return switch digest.lastKind {
        case .assistantText: .idle
        case .toolUse, .toolResult, .thinking, .userPrompt, .other: fresh ? .working : .idle
        }
    }
}
