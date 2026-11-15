import Foundation

/// `ClaudeMonitor --usage` prints the usage snapshot, including how long the scan took.
enum UsageDump {
    static func run() {
        let usage = UsageReader.snapshot()

        print("Scan took \(String(format: "%.2f", usage.scanDuration)) s\n")

        line("Five-hour block", usage.fiveHour, percent: usage.planFiveHourPercent)
        // With a reported reset the window is the plan's own week, which starts where
        // the plan says -- without one it is just the seven days behind us.
        line(usage.week.resetIsEstimate ? "Last seven days" : "Plan week",
             usage.week, percent: usage.planWeekPercent)

        switch usage.planSource {
        case .statusLine:
            let age = usage.planSampledAt.map { Fmt.elapsed(since: $0) } ?? "unknown"
            print("\nPlan percentages from Claude Code's status line, caught \(age) ago")
        case .desktopSample:
            let age = usage.planSampledAt.map { Fmt.elapsed(since: $0) } ?? "unknown"
            if usage.planFiveHourPercent == nil, usage.planWeekPercent == nil {
                print("\nPlan sample is \(age) old and describes windows that have since passed — percentages left out")
            } else {
                print("\nPlan percentages sampled \(age) ago by the desktop app")
            }
            print("Install the status line bridge in Settings for live figures")
        case nil:
            print("\nNo plan figures: nothing at \(UsageReader.statusLineURL.path)")
            print("and no usable sample at \(UsageReader.planHistoryURL.path)")
        }
    }

    private static func line(_ title: String, _ window: UsageSnapshot.Window, percent: Int?) {
        var parts = ["\(Fmt.tokens(window.tokens)) tokens", "\(window.sessions) sessions"]
        if let percent { parts.append("\(percent) % of plan") }
        print("\(title.padding(toLength: 18, withPad: " ", startingAt: 0)) \(parts.joined(separator: " · "))")

        if let since = window.since {
            print("                   since \(Fmt.clockOrDate(since))", terminator: "")
            if let resets = window.resets {
                print(", resets \(Fmt.clockOrDate(resets))\(window.resetIsEstimate ? " (estimated)" : " (reported)")")
            } else {
                print(", reset time unknown")
            }
        }
    }
}
