#if DEBUG
import AppKit
import SwiftUI

/// Photographs the panel for the README: `--screenshots <directory>`.
///
/// Why real windows and `screencapture` rather than SwiftUI's `ImageRenderer`:
/// the panel has no background of its own. In the menu bar it sits on a glass
/// window, and glass is composited by the window server out of whatever lies
/// behind it. Rendered offscreen there is nothing behind it, and the shot comes
/// out empty. So the picture has to be taken of a window that is genuinely on
/// screen — over a backdrop of our own, rather than over whatever happens to be
/// on the desktop.
enum Screenshots {
    /// `NSApplication.delegate` does not retain; this does.
    nonisolated(unsafe) private static var runner: ScreenshotRunner?

    static func run(outputDirectory: String) {
        // `main()` is on the main thread already -- the compiler just cannot see it.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let runner = ScreenshotRunner(directory: outputDirectory)
            Screenshots.runner = runner
            app.delegate = runner
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}

@MainActor
final class ScreenshotRunner: NSObject, NSApplicationDelegate {
    private let directory: String
    private var windows: [NSWindow] = []

    init(directory: String) {
        self.directory = directory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await shootEverything()
            NSApp.terminate(nil)
        }
    }

    private func shootEverything() async {
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true
        )
        let store = SessionStore.shared
        store.loadDemo()

        for mode in [Appearance.light, .dark] {
            NSApp.appearance = NSAppearance(named: mode.name)

            store.selectedID = nil
            store.idleExpanded = false
            await shoot(
                name: "panel\(mode.suffix)",
                view: AnyView(PanelView(store: store)),
                appearance: mode,
                extraWidth: 0
            )

            // The popover is a window of its own, opened by SwiftUI next to the row.
            // Selecting the row before the panel is shown means it is already open
            // when the shutter falls.
            store.selectedID = store.sessions.first?.id
            await shoot(
                name: "detail\(mode.suffix)",
                view: AnyView(PanelView(store: store)),
                appearance: mode,
                extraWidth: 430
            )
            store.selectedID = nil

            await shootSettings(name: "settings\(mode.suffix)", appearance: mode)
        }
    }

    // MARK: - One picture

    /// `extraWidth` leaves room to the right of the panel for a popover.
    private func shoot(name: String, view: AnyView, appearance: Appearance, extraWidth: CGFloat) async {
        let host = NSHostingView(rootView: view)
        host.layout()
        let size = host.fittingSize

        let pad: CGFloat = 46
        let backdropSize = CGSize(
            width: size.width + extraWidth + pad * 2,
            height: size.height + pad * 2
        )
        let origin = centered(backdropSize)

        let backdrop = makeBackdrop(
            frame: NSRect(origin: origin, size: backdropSize), appearance: appearance
        )
        let panel = makePanel(
            host: host,
            frame: NSRect(
                x: origin.x + pad,
                y: origin.y + pad,
                width: size.width,
                height: size.height
            ),
            appearance: appearance
        )

        backdrop.orderFront(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()

        await settle()
        // The popover is the subject of this picture, and a window that is not key
        // draws its buttons grey.
        if extraWidth > 0,
           let popover = NSApp.windows.first(where: { $0.isVisible && $0 !== panel && $0 !== backdrop }) {
            popover.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(250))
        }
        await fit(backdrop: backdrop, padding: pad)
        capture(rect: backdrop.frame, to: name)

        panel.orderOut(nil)
        backdrop.orderOut(nil)
        windows.removeAll { $0 === panel || $0 === backdrop }
    }

    /// Settings is an ordinary titled window, so it is photographed as one —
    /// title bar included, because that is what the user will see.
    private func shootSettings(name: String, appearance: Appearance) async {
        let host = NSHostingView(rootView: SettingsView())
        host.layout()
        let size = host.fittingSize

        let pad: CGFloat = 46
        let titleBar: CGFloat = 28
        let backdropSize = CGSize(width: size.width + pad * 2, height: size.height + titleBar + pad * 2)
        let origin = centered(backdropSize)

        let backdrop = makeBackdrop(
            frame: NSRect(origin: origin, size: backdropSize), appearance: appearance
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Monitor Settings"
        window.contentView = host
        window.appearance = NSAppearance(named: appearance.name)
        window.level = .floating
        window.setFrameOrigin(NSPoint(x: origin.x + pad, y: origin.y + pad))
        windows.append(window)

        backdrop.orderFront(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        await settle()
        await fit(backdrop: backdrop, padding: pad)
        capture(rect: backdrop.frame, to: name)

        window.orderOut(nil)
        backdrop.orderOut(nil)
        windows.removeAll { $0 === window || $0 === backdrop }
    }

    // MARK: - Windows

    private func makePanel(host: NSView, frame: NSRect, appearance: Appearance) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.appearance = NSAppearance(named: appearance.name)

        // The glass the menu bar window provides. Without it the panel would be
        // drawn onto nothing, since none of its views carry a background.
        let material = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 13
        material.layer?.masksToBounds = true
        material.autoresizingMask = [.width, .height]

        host.frame = material.bounds
        host.autoresizingMask = [.width, .height]
        material.addSubview(host)

        window.contentView = material
        windows.append(window)
        return window
    }

    /// Something for the glass to pick up, and for the shadow to fall on. Also
    /// keeps the desktop — and whatever is on it — out of the picture.
    private func makeBackdrop(frame: NSRect, appearance: Appearance) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = appearance.backdrop
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

        windows.append(window)
        return window
    }

    /// Lays the backdrop exactly under whatever ended up on screen.
    ///
    /// A popover is a window of its own and SwiftUI decides where to put it: it
    /// reaches further than the panel it belongs to, and a backdrop sized from the
    /// panel alone left it hanging over the edge. So the frames are measured after
    /// the fact rather than guessed beforehand.
    private func fit(backdrop: NSWindow, padding: CGFloat) async {
        let others = NSApp.windows.filter { $0.isVisible && $0 !== backdrop }
        guard var union = others.first?.frame else { return }
        for window in others.dropFirst() { union = union.union(window.frame) }
        backdrop.setFrame(union.insetBy(dx: -padding, dy: -padding), display: true)
        try? await Task.sleep(for: .milliseconds(350))
    }

    private func centered(_ size: CGSize) -> NSPoint {
        let screen = (NSScreen.main ?? NSScreen.screens[0]).frame
        return NSPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
    }

    // MARK: - The shutter

    /// `NSApp.run()` is already turning the main runloop; awaiting here hands it
    /// back so the window actually gets drawn. The glass material and the popover
    /// each need a frame on screen before they are there to photograph.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(900))
    }

    private func capture(rect: NSRect, to name: String) {
        // screencapture measures from the top left of the primary display;
        // AppKit measures from the bottom left.
        let primary = NSScreen.screens[0].frame
        let top = primary.height - rect.maxY
        let region = "\(Int(rect.origin.x)),\(Int(top)),\(Int(rect.width)),\(Int(rect.height))"
        let path = "\(directory)/\(name).png"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-t", "png", "-R", region, path]
        do {
            try process.run()
            process.waitUntilExit()
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? Int) ?? 0
            print("\(name).png  \(region)  \(size) bytes")
        } catch {
            print("\(name): \(error.localizedDescription)")
        }
    }

    enum Appearance {
        case light, dark

        var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
        var suffix: String { self == .light ? "" : "-dark" }

        /// Something for the glass to pick up and the shadow to fall on. Flat
        /// rather than a gradient: it has to survive being resized.
        var backdrop: NSColor {
            self == .light ? NSColor(hex: "#E8ECF3") : NSColor(hex: "#1B1D23")
        }
    }
}
#endif
