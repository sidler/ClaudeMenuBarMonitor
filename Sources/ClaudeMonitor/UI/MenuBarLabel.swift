import SwiftUI

/// The menu bar symbol: no dot when quiet, otherwise dot plus count.
struct MenuBarLabel: View {
    let state: SessionState?
    let count: Int

    /// Through @AppStorage, so the symbol changes the moment it is switched
    /// in Settings.
    @AppStorage("menuBarSymbol") private var symbol = MenuBarIcon.defaultSymbol

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuBarIcon.image(for: state, symbol: symbol))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: state?.needsAttention == true ? .bold : .semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let state else { return "Claude Monitor — no active session" }
        return "Claude Monitor — \(count) × \(state.title)"
    }
}
