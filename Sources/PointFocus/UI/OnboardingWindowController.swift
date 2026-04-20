import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var watchTask: Task<Void, Never>?

    func show(perms: PermissionsService) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "PointFocus — Setup"
            w.contentView = NSHostingView(rootView: OnboardingView(perms: perms))
            w.isReleasedWhenClosed = false
            window = w
        }
        if let w = window {
            centerOnMouseScreen(w)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startWatching(perms: perms)
    }

    private func centerOnMouseScreen(_ w: NSWindow) {
        // Prefer the screen the mouse is on; fall back to the primary display
        // (the one at origin (0, 0) on the global screen coordinate space).
        let mouse = NSEvent.mouseLocation
        let target = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = target else { return }
        let vf = screen.visibleFrame
        let frame = w.frame
        let origin = NSPoint(
            x: vf.minX + (vf.width  - frame.width)  / 2,
            y: vf.minY + (vf.height - frame.height) / 2
        )
        w.setFrameTopLeftPoint(NSPoint(x: origin.x, y: origin.y + frame.height))
    }

    private func startWatching(perms: PermissionsService) {
        watchTask?.cancel()
        watchTask = Task { @MainActor in
            while self.window?.isVisible == true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if perms.accessibility == .granted && perms.inputMonitoring == .granted {
                    self.window?.orderOut(nil)
                    break
                }
            }
        }
    }
}
