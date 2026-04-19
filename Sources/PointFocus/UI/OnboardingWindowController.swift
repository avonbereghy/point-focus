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
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startWatching(perms: perms)
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
