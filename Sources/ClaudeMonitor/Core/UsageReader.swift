import Foundation

/// How much has been used in the current five-hour block and over the last seven days.
///
/// Three sources, and they are not equally trustworthy:
///
/// 1. **Token counts from the transcripts** — exact and always current, but they are *our*
///    sum, not Anthropic's accounting, which weighs models differently.
/// 2. **The plan percentages** the desktop app samples into
///    `~/Library/Application Support/Claude/plan-usage-history.json` — those are the real
///    numbers behind `/usage`, but only as fresh as the last sample.
/// 3. **`quotaLimits.resetsAt`** from a transcript — exact, but only written when a request
///    was actually rejected.
///
/// The view labels which one it is showing; nothing here pretends to be more than it is.
struct UsageSnapshot: Sendable {
    struct Window: Sendable {
        var tokens = 0
        var sessions = 0
        var since: Date?
        var resets: Date?
        /// True when `resets` was derived from activity rather than reported by the API.
        var resetIsEstimate = true
    }

    var fiveHour = Window()
    var week = Window()

    /// Percentages as the desktop app last sampled them, plus the age of that sample.
    var planFiveHourPercent: Int?
    var planWeekPercent: Int?
    var planSampledAt: Date?

    /// Total tokens per session over the week — counted from whole files, so this is
    /// more complete than the tail-based figure in `Session`.
    var sessionTokens: [String: Int] = [:]

    var computedAt: Date = .now
    /// How long the scan took — the scan reads whole transcripts, not just their tails.
    var scanDuration: TimeInterval = 0
}

enum UsageReader {
    /// Anthropic's usage block. A block starts with the first request and lasts five hours.
    static let blockLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 24 * 3600

    static var planHistoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Claude/plan-usage-history.json")
    }

    /// Walks every transcript touched in the last seven days.
    ///
    /// Unlike `TranscriptParser` this reads the files whole: a window of hours or days
    /// reaches further back than the tail. That costs time, so the store calls this on a
    /// slow timer, not on every scan.
    static func snapshot(_ config: ScanConfig = ScanConfig(), now: Date = .now) -> UsageSnapshot {
        let started = Date.now
        var snapshot = UsageSnapshot(computedAt: now)

        let weekStart = now.addingTimeInterval(-weekLength)
        var samples: [(at: Date, tokens: Int, session: String)] = []
        var sessionCost: [String: Double] = [:]
        var reportedReset: (type: String, at: Date)?

        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: config.projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return snapshot }

        for projectDir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                guard modified > weekStart else { continue }
                let id = file.deletingPathExtension().lastPathComponent
                read(file, id: id, weekStart: weekStart, samples: &samples, cost: &sessionCost, reset: &reportedReset)
            }
        }

        for sample in samples {
            snapshot.sessionTokens[sample.session, default: 0] += sample.tokens
        }

        snapshot.week = window(from: weekStart, samples: samples, cost: sessionCost, now: now)
        snapshot.week.resets = nil      // the weekly anchor is not knowable from local files
        snapshot.week.since = weekStart

        if let blockStart = currentBlockStart(samples.map(\.at), now: now) {
            snapshot.fiveHour = window(from: blockStart, samples: samples, cost: sessionCost, now: now)
            snapshot.fiveHour.since = blockStart
            snapshot.fiveHour.resets = blockStart.addingTimeInterval(blockLength)
        }

        // A reset the API actually reported beats our estimate.
        if let reportedReset, reportedReset.at > now {
            if reportedReset.type == "five_hour" {
                snapshot.fiveHour.resets = reportedReset.at
                snapshot.fiveHour.resetIsEstimate = false
            } else {
                snapshot.week.resets = reportedReset.at
                snapshot.week.resetIsEstimate = false
            }
        }

        applyPlanSample(&snapshot)
        snapshot.scanDuration = Date.now.timeIntervalSince(started)
        return snapshot
    }

    // MARK: - Reading

    private static let assistantNeedle = Data("\"type\":\"assistant\"".utf8)
    private static let costNeedle = Data("\"type\":\"cost-state\"".utf8)
    private static let quotaNeedle = Data("\"quotaLimits\"".utf8)

    /// Scans a transcript backwards and stops at the window edge.
    ///
    /// Byte search over the mapped file, not line-by-line string work: the transcripts add
    /// up to hundreds of megabytes, and Swift's Unicode-aware `contains` over that took
    /// over a minute. Only the lines a needle actually hits are handed to the JSON decoder.
    private static func read(
        _ url: URL,
        id: String,
        weekStart: Date,
        samples: inout [(at: Date, tokens: Int, session: String)],
        cost: inout [String: Double],
        reset: inout (type: String, at: Date)?
    ) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), !data.isEmpty else { return }

        // Assistant entries carry the token counts. Walking from the end lets us stop as
        // soon as we leave the window instead of reading months of history.
        var searchEnd = data.endIndex
        while let hit = data.range(of: assistantNeedle, options: .backwards, in: data.startIndex..<searchEnd) {
            let line = lineRange(containing: hit, in: data)
            searchEnd = line.lowerBound

            guard let obj = decode(data[line]) else { continue }
            guard let at = Fmt.date(obj["timestamp"]) else { continue }
            guard at >= weekStart else { break }

            guard let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            // Cache reads dwarf everything else and say little about the plan quota,
            // so they stay out of the headline figure.
            let tokens = (Fmt.int(usage["input_tokens"]) ?? 0)
                + (Fmt.int(usage["output_tokens"]) ?? 0)
                + (Fmt.int(usage["cache_creation_input_tokens"]) ?? 0)
            guard tokens > 0 else { continue }
            samples.append((at: at, tokens: tokens, session: id))

            if searchEnd == data.startIndex { break }
        }

        // The last cost-state holds the session total — one search from the end is enough.
        if let hit = data.range(of: costNeedle, options: .backwards, in: data.startIndex..<data.endIndex),
           let obj = decode(data[lineRange(containing: hit, in: data)]),
           let total = Fmt.double(obj["totalCostUSD"]) {
            cost[id] = total
        }

        // A reported reset only exists when a request was actually rejected.
        if let hit = data.range(of: quotaNeedle, options: .backwards, in: data.startIndex..<data.endIndex),
           let obj = decode(data[lineRange(containing: hit, in: data)]),
           let quota = obj["quotaLimits"] as? [String: Any],
           let seconds = Fmt.double(quota["resetsAt"]) {
            let at = Date(timeIntervalSince1970: seconds)
            let type = (quota["rateLimitType"] as? String) ?? "five_hour"
            if reset == nil || at > reset!.at { reset = (type, at) }
        }
    }

    private static func decode(_ slice: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: slice) as? [String: Any]
    }

    /// Widens a hit to the newline-delimited line around it.
    private static func lineRange(containing hit: Range<Data.Index>, in data: Data) -> Range<Data.Index> {
        let newline = UInt8(ascii: "\n")
        var start = hit.lowerBound
        while start > data.startIndex, data[data.index(before: start)] != newline {
            start = data.index(before: start)
        }
        var end = hit.upperBound
        while end < data.endIndex, data[end] != newline {
            end = data.index(after: end)
        }
        return start..<end
    }

    // MARK: - Windows

    private static func window(
        from start: Date,
        samples: [(at: Date, tokens: Int, session: String)],
        cost: [String: Double],
        now: Date
    ) -> UsageSnapshot.Window {
        var window = UsageSnapshot.Window(since: start)
        var sessions: Set<String> = []
        for sample in samples where sample.at >= start {
            window.tokens += sample.tokens
            sessions.insert(sample.session)
        }
        window.sessions = sessions.count
        // Cost is only known per session, and a session can straddle the window edge.
        // Summing it here would invent precision, so the window reports tokens only.
        return window
    }

    /// A block starts with the first request and runs five hours; the next request after
    /// that opens the next one.
    private static func currentBlockStart(_ timestamps: [Date], now: Date) -> Date? {
        var start: Date?
        for at in timestamps.sorted() {
            if let current = start, at < current.addingTimeInterval(blockLength) { continue }
            start = at
        }
        guard let start, now < start.addingTimeInterval(blockLength) else { return nil }
        return start
    }

    // MARK: - Plan percentages

    /// `{"version":2,"samples":[{"t":…,"org":"…","u":{"fh":11,"sd":14}}]}`
    /// `fh` = five hours, `sd` = seven days, both in percent of the plan's limit.
    private static func applyPlanSample(_ snapshot: inout UsageSnapshot) {
        guard let data = try? Data(contentsOf: planHistoryURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]],
              let latest = samples.max(by: { (Fmt.double($0["t"]) ?? 0) < (Fmt.double($1["t"]) ?? 0) })
        else { return }

        snapshot.planSampledAt = Fmt.epochMillis(latest["t"])
        guard let usage = latest["u"] as? [String: Any] else { return }
        snapshot.planFiveHourPercent = Fmt.int(usage["fh"])
        snapshot.planWeekPercent = Fmt.int(usage["sd"])
    }
}
