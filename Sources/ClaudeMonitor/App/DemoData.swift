#if DEBUG
import Foundation

/// Fabricated sessions for `--demo` and `--screenshots`.
///
/// The README needs pictures of a full panel, and a full panel means somebody's
/// real work: project names, branches, the commands they ran. These are made up
/// instead — close enough to the real shape that the screenshots are honest, and
/// far enough from anybody's machine that they give nothing away.
///
/// Debug builds only. The shipped app has no way to reach this.
enum DemoData {
    static func sessions(now: Date = .now) -> [Session] {
        [
            approval(now),
            question(now),
            building(now),
            installing(now),
            resting(now, name: "marketing-site", ago: 2_700),
            resting(now, name: "infra-terraform", ago: 8_400)
        ]
    }

    // MARK: - The two that want something

    private static func approval(_ now: Date) -> Session {
        var session = base(
            id: "7c1f0a52-4e88-4a1b-9d33-0b8e2f61c4aa",
            name: "checkout-service",
            cwd: "/Users/you/work/checkout-service",
            branch: "feature/apple-pay",
            now: now
        )
        session.state = .awaitingApproval
        session.stateSince = now.addingTimeInterval(-320)
        session.lastActivity = session.stateSince
        session.headline = "Bash · rm -rf node_modules && npm ci"
        session.detail = "rm -rf node_modules && npm ci --prefer-offline"
        session.turns = 14
        session.toolCalls = 63
        session.costUSD = 2.41
        session.linesAdded = 184
        session.linesRemoved = 37
        session.contextTokens = 96_400
        session.startedAt = now.addingTimeInterval(-5_280)
        session.recent = [
            item("Bash · rm -rf node_modules && npm ci", now.addingTimeInterval(-320), .tool),
            item("Read · package-lock.json", now.addingTimeInterval(-368), .tool),
            item("The lockfile and package.json disagree on vite.", now.addingTimeInterval(-410), .answer),
            item("the build fails after the merge, find out why", now.addingTimeInterval(-470), .prompt)
        ]
        return session
    }

    private static func question(_ now: Date) -> Session {
        var session = base(
            id: "2a9d5be1-7f04-4c2e-8ad6-19c7b03e55f2",
            name: "docs-portal",
            cwd: "/Users/you/work/docs-portal",
            branch: "main",
            now: now
        )
        session.state = .awaitingReply
        session.stateSince = now.addingTimeInterval(-940)
        session.lastActivity = session.stateSince
        session.headline = "Should the old /api/v1 routes keep redirecting?"
        session.detail = "The rewrite drops /api/v1 entirely. Keeping the redirects costs one middleware and keeps old bookmarks alive — should they stay?"
        session.turns = 7
        session.toolCalls = 21
        session.costUSD = 0.88
        session.linesAdded = 46
        session.linesRemoved = 212
        session.contextTokens = 41_900
        session.startedAt = now.addingTimeInterval(-2_950)
        session.recent = [
            item("Should the old /api/v1 routes keep redirecting?", now.addingTimeInterval(-940), .answer),
            item("Edit · src/routes/index.ts", now.addingTimeInterval(-1_010), .tool),
            item("Grep · api/v1", now.addingTimeInterval(-1_080), .tool),
            item("move the docs over to the new router", now.addingTimeInterval(-1_200), .prompt)
        ]
        return session
    }

    // MARK: - The two that are busy

    private static func building(_ now: Date) -> Session {
        var session = base(
            id: "f5e3c70b-61d2-4f8a-b4e7-2d9a84c1f3b6",
            name: "payment-api",
            cwd: "/Users/you/work/payment-api",
            branch: "fix/invoice-rounding",
            now: now
        )
        session.state = .working
        session.stateSince = now.addingTimeInterval(-48)
        session.lastActivity = now.addingTimeInterval(-3)
        session.headline = "Edit · src/Billing/InvoiceBuilder.php"
        session.turns = 21
        session.toolCalls = 108
        session.costUSD = 4.17
        session.linesAdded = 512
        session.linesRemoved = 98
        session.contextTokens = 158_300
        session.startedAt = now.addingTimeInterval(-9_100)
        session.model = "claude-opus-5"
        session.recent = [
            item("Edit · src/Billing/InvoiceBuilder.php", now.addingTimeInterval(-3), .tool),
            item("Bash · vendor/bin/phpunit --filter Rounding", now.addingTimeInterval(-61), .tool),
            item("Two of the three cases round the wrong way.", now.addingTimeInterval(-95), .answer),
            item("the totals are off by a cent on partial refunds", now.addingTimeInterval(-160), .prompt)
        ]
        return session
    }

    private static func installing(_ now: Date) -> Session {
        var session = base(
            id: "b8740d19-3ac5-4e6f-90b1-7c52e8a0d4e3",
            name: "design-tokens",
            cwd: "/Users/you/work/design-tokens",
            branch: "main",
            now: now
        )
        session.state = .working
        session.stateSince = now.addingTimeInterval(-26)
        session.lastActivity = now.addingTimeInterval(-11)
        session.headline = "Bash · npm run build"
        session.turns = 4
        session.toolCalls = 12
        session.costUSD = 0.31
        session.linesAdded = 73
        session.linesRemoved = 5
        session.contextTokens = 22_700
        session.startedAt = now.addingTimeInterval(-640)
        session.model = "claude-haiku-5-5"
        return session
    }

    // MARK: - The quiet ones

    private static func resting(_ now: Date, name: String, ago: TimeInterval) -> Session {
        var session = base(
            id: "idle-\(name)",
            name: name,
            cwd: "/Users/you/work/\(name)",
            branch: "main",
            now: now
        )
        session.state = .idle
        session.stateSince = now.addingTimeInterval(-ago)
        session.lastActivity = session.stateSince
        session.headline = "Answered · nothing pending"
        session.turns = Int(ago) % 9 + 3
        session.toolCalls = Int(ago) % 40 + 8
        session.costUSD = Double(Int(ago) % 300) / 100
        session.contextTokens = Int(ago) % 60_000 + 12_000
        session.startedAt = now.addingTimeInterval(-ago - 3_600)
        return session
    }

    // MARK: - Shared shape

    private static func base(id: String, name: String, cwd: String, branch: String, now: Date) -> Session {
        Session(
            id: id,
            transcript: URL(fileURLWithPath: "/Users/you/.claude/projects/-Users-you-work-\(name)/\(id).jsonl"),
            projectSlug: "-Users-you-work-\(name)",
            title: name,
            cwd: cwd,
            gitBranch: branch,
            model: "claude-sonnet-5-5",
            permissionMode: "default",
            state: .idle,
            stateSince: now,
            lastActivity: now,
            headline: "",
            detail: nil,
            startedAt: now,
            turns: 0,
            toolCalls: 0,
            costUSD: nil,
            linesAdded: 0,
            linesRemoved: 0,
            contextTokens: nil,
            contextLimit: 200_000,
            lastPrompt: nil,
            recent: []
        )
    }

    private static func item(_ text: String, _ at: Date, _ kind: ActivityItem.Kind) -> ActivityItem {
        ActivityItem(id: "\(kind)-\(at.timeIntervalSince1970)", at: at, kind: kind, text: text)
    }

    // MARK: - Usage

    /// Plan percentages in the range the panel is meant to show: comfortable in the
    /// block, well into the week.
    static func usage(now: Date = .now) -> UsageSnapshot {
        var snapshot = UsageSnapshot(computedAt: now)
        snapshot.fiveHour = UsageSnapshot.Window(
            tokens: 1_284_000,
            sessions: 4,
            since: now.addingTimeInterval(-9_600),
            resets: now.addingTimeInterval(8_400),
            resetIsEstimate: true
        )
        snapshot.week = UsageSnapshot.Window(
            tokens: 9_830_000,
            sessions: 23,
            since: now.addingTimeInterval(-7 * 24 * 3_600),
            resets: nil,
            resetIsEstimate: true
        )
        snapshot.planFiveHourPercent = 37
        snapshot.planWeekPercent = 71
        snapshot.planSampledAt = now.addingTimeInterval(-540)
        snapshot.scanDuration = 0.68
        return snapshot
    }
}
#endif
