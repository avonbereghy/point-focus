import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var watchTask: Task<Void, Never>?

    func show(perms: PermissionsService) {
        // Rebuild the hosting controller each show so the passed `perms` always
        // renders, and let the window adopt the SwiftUI content's fitting size.
        // The content is ~508pt wide once padding is counted, so the old fixed
        // 460×360 content rect clipped both the right edge and the lower text.
        let host = NSHostingController(rootView: OnboardingView(perms: perms))
        let w: NSWindow
        if let existing = window {
            w = existing
            w.contentViewController = host
        } else {
            w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.title = "PointFocus — Setup"
            w.isReleasedWhenClosed = false
            window = w
        }
        w.setContentSize(host.view.fittingSize)
        centerOnMouseScreen(w)
        w.makeKeyAndOrderFront(nil)
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
            var lastAccessibility = perms.accessibility
            var lastInputMonitoring = perms.inputMonitoring
            while self.window?.isVisible == true {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // Announce each permission as it transitions to granted so a
                // VoiceOver user gets audible progress, not just a silent relabel.
                if perms.accessibility == .granted && lastAccessibility != .granted {
                    self.announce("Accessibility granted.")
                }
                if perms.inputMonitoring == .granted && lastInputMonitoring != .granted {
                    self.announce("Input Monitoring granted.")
                }
                lastAccessibility = perms.accessibility
                lastInputMonitoring = perms.inputMonitoring
                if perms.accessibility == .granted && perms.inputMonitoring == .granted {
                    // Announce completion and let the on-screen success state be
                    // seen for a beat before the window dismisses itself.
                    self.announce("Setup complete. PointFocus is now active in your menu bar.")
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    self.window?.orderOut(nil)
                    break
                }
            }
        }
    }

    private func announce(_ message: String) {
        guard let window else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
