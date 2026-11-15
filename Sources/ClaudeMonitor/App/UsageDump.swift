import Foundation

/// `ClaudeMonitor --usage` prints the usage snapshot, including how long the scan took.
enum UsageDump {
    static func run() {
        let usage = UsageReader.snapshot()

        print("Scan took \(String(format: "%.2f", usage.scanDuration)) s\n")

        line("Five-hour block", usage.fiveHour, percent: usage.planFiveHourPercent)
        line("Last seven days", usage.week, percent: usage.planWeekPercent)

        if let sampledAt = usage.planSampledAt {
            let age = Fmt.elapsed(since: sampledAt)
            if usage.planFiveHourPercent == nil, usage.planWeekPercent == nil {
                print("\nPlan sample is \(age) old and describes windows that have since passed — percentages left out")
            } else {
                print("\nPlan percentages sampled \(age) ago by the desktop app")
            }
        } else {
            print("\nNo plan sample found at \(UsageReader.planHistoryURL.path)")
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
