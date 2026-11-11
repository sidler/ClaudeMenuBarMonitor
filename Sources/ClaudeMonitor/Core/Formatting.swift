import Foundation

enum Fmt {
    private static let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    static func date(_ raw: Any?) -> Date? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        if let parsed = try? iso.parse(s) { return parsed }
        return try? isoPlain.parse(s)
    }

    /// Epoch milliseconds, which Claude stores as a string.
    static func epochMillis(_ raw: Any?) -> Date? {
        let ms: Double? = switch raw {
        case let d as Double: d
        case let i as Int: Double(i)
        case let s as String: Double(s)
        default: nil
        }
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    static func double(_ raw: Any?) -> Double? {
        switch raw {
        case let d as Double: d
        case let i as Int: Double(i)
        case let s as String: Double(s)
        default: nil
        }
    }

    static func int(_ raw: Any?) -> Int? {
        switch raw {
        case let i as Int: i
        case let d as Double: Int(d)
        case let s as String: Int(Double(s) ?? .nan)
        default: nil
        }
    }

    /// “0:42”, “18 min”, “1 h 12” — short enough for a single line in the panel.
    static func elapsed(since date: Date, now: Date = .now) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "0:\(String(format: "%02d", s))" }
        if s < 600 { return "\(s / 60):\(String(format: "%02d", s % 60))" }
        if s < 3600 { return "\(s / 60) min" }
        let h = s / 3600, m = (s % 3600) / 60
        if h < 24 { return m == 0 ? "\(h) h" : "\(h) h \(String(format: "%02d", m))" }
        return "\(h / 24) d"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    static func tokens(_ value: Int) -> String {
        value >= 1000 ? "\(value / 1000)k" : "\(value)"
    }

    /// “claude-opus-5-5” → “Opus 5.5”
    static func modelName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var parts = raw.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        guard let family = parts.first else { return raw }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}
