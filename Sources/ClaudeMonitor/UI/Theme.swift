import AppKit
import SwiftUI

enum Theme {
    static let panelWidth: CGFloat = 380
    static let panelMaxHeight: CGFloat = 560

    /// Blau und Orange statt Grün und Rot — unterscheidbar auch bei Rotgrünschwäche.
    static let working = dynamic(light: "#0A6BD4", dark: "#6FA8F5")
    static let waiting = dynamic(light: "#B35309", dark: "#E8A24A")
    static let aborted = dynamic(light: "#B03A2E", dark: "#E0776A")
    static let resting = dynamic(light: "#9A9AA0", dark: "#76767E")

    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: String) {
        let raw = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(raw, radix: 16) ?? 0
        self.init(
            srgbRed: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Der Statuspunkt: gefüllt, Ring oder Kontur — die Farbe trägt die Information nie allein.
struct StateDot: View {
    let state: SessionState
    var size: CGFloat = 8

    var body: some View {
        Group {
            switch state.dotStyle {
            case .filled:
                Circle().fill(state.tint)
            case .ring:
                Circle().strokeBorder(state.tint, lineWidth: size / 4)
            case .hollow:
                Circle().strokeBorder(state.tint, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(state.title)
    }
}
