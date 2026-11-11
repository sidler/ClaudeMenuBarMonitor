import AppKit
import SwiftUI

/// Zeichnet das Menüleisten-Symbol als farbiges Bild.
///
/// Ein SwiftUI-Label in `MenuBarExtra` wird von macOS als Template gerendert: die Maske
/// bleibt, die Farbe fällt weg. Deshalb entsteht das Bild hier von Hand, mit
/// `isTemplate = false` — nur so ist der Zustandspunkt blau oder orange.
enum MenuBarIcon {
    struct Choice: Identifiable, Hashable, Sendable {
        let id: String      // Name des SF-Symbols
        let name: String
    }

    static let defaultSymbol = "apple.terminal"

    /// Nur Symbole, die bei 16 px noch lesbar sind. Feingliedriges wie `brain` oder `cpu`
    /// verschmiert in der Menüleiste zu einem Fleck und steht deshalb nicht zur Wahl.
    static let choices: [Choice] = [
        Choice(id: "apple.terminal", name: "Terminal"),
        Choice(id: "terminal", name: "Terminal, schlicht"),
        Choice(id: "waveform", name: "Aktivität"),
        Choice(id: "waveform.path", name: "Puls"),
        Choice(id: "rectangle.stack", name: "Stapel"),
        Choice(id: "list.bullet.rectangle", name: "Liste"),
        Choice(id: "asterisk", name: "Stern"),
        Choice(id: "sparkle", name: "Funke"),
        Choice(id: "staroflife", name: "Burst"),
        Choice(id: "chevron.left.forwardslash.chevron.right", name: "Code"),
        Choice(id: "square.grid.2x2", name: "Raster"),
        Choice(id: "point.3.connected.trianglepath.dotted", name: "Agenten")
    ]

    static var currentSymbol: String {
        UserDefaults.standard.string(forKey: "menuBarSymbol") ?? defaultSymbol
    }

    static func image(for state: SessionState?, symbol: String = currentSymbol) -> NSImage {
        let glyph = tintedGlyph(symbol)
        let dotSize: CGFloat = 8

        // Die Höhe bleibt exakt die des Symbols: ein höheres Bild würde die Menüleiste
        // mittig ausrichten und das Symbol dadurch nach oben schieben. Der Punkt überlappt
        // deshalb die untere rechte Ecke und ragt nur seitlich heraus.
        let size = NSSize(width: glyph.size.width + dotSize / 2, height: glyph.size.height)

        let image = NSImage(size: size, flipped: false) { _ in
            glyph.draw(
                in: NSRect(origin: .zero, size: glyph.size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

            guard let state else { return true }
            let box = NSRect(x: size.width - dotSize, y: 0, width: dotSize, height: dotSize)

            // Loch unter dem Punkt, damit er sich vom Symbol abhebt — auch einfarbig.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(ovalIn: box.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.restoreGraphicsState()

            let color = NSColor(state.menuBarColor)
            switch state.dotStyle {
            case .filled:
                color.setFill()
                NSBezierPath(ovalIn: box).fill()
            case .ring, .hollow:
                color.setStroke()
                let ring = NSBezierPath(ovalIn: box.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 2
                ring.stroke()
            }
            return true
        }

        image.isTemplate = false
        image.accessibilityDescription = state?.title ?? "Keine aktive Session"
        return image
    }

    /// Das SF-Symbol ist eine Template-Maske; es bekommt hier die Textfarbe der Menüleiste.
    private static func tintedGlyph(_ name: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let requested = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: defaultSymbol, accessibilityDescription: nil)
        guard let symbol = requested?.withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: 14, height: 14))
        }

        return NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.labelColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

extension SessionState {
    /// Kräftiger als im Panel: in der Menüleiste ist der Punkt nur sechs Pixel groß.
    var menuBarColor: Color {
        switch self {
        case .awaitingApproval, .awaitingReply: Theme.waiting
        case .working: Theme.working
        case .aborted: Theme.aborted
        case .idle: Theme.resting
        }
    }
}
