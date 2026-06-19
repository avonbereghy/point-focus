import AppKit

@MainActor
final class PickerCoordinator {
    /// Outcome of a focus-point pick. `failed` carries a user-facing reason so
    /// callers can surface it; `cancelled` is silent (the user pressed Esc, the
    /// observed app terminated mid-pick, or a pick was already in progress).
    enum PickerOutcome {
        case completed
        case cancelled
        case failed(String)
    }

    private let store: SettingsStore
    /// Guards against stacking a second overlay while one is already live — a
    /// per-app pick can spend up to 5s probing before its overlay appears, and
    /// a second trigger in that window would otherwise orphan a full-screen,
    /// event-capturing overlay underneath the new one.
    private var isPicking = false

    init(store: SettingsStore) {
        self.store = store
    }

    func pickGlobal() async -> PickerOutcome {
        guard !isPicking else { return .cancelled }
        isPicking = true
        defer { isPicking = false }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let primaryMaxY = (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? screen).frame.maxY
        let tlFrame = CGRect(
            x: screen.visibleFrame.minX,
            y: primaryMaxY - screen.visibleFrame.maxY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
        guard let p = await runOverlay(frame: tlFrame, observeBundleID: nil) else { return .cancelled }
        let fp = FocusPoint(x: p.x / tlFrame.width, y: p.y / tlFrame.height)
        store.update { $0.globalPoint = fp }
        return .completed
    }

    func pick(bundleID: String) async -> PickerOutcome {
        guard !isPicking else { return .cancelled }
        isPicking = true
        defer { isPicking = false }

        var running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        if running == nil {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return .failed("Couldn't find \(displayName(for: bundleID)). It may not be installed.")
            }
            do {
                running = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                return .failed("Couldn't launch \(displayName(for: bundleID)).")
            }
        }
        running?.activate(options: [.activateAllWindows])
        let deadline = Date().addingTimeInterval(5.0)
        var r: FocusedWindowProbe.Result? = nil
        while Date() < deadline {
            if let cur = FocusedWindowProbe.current(), cur.bundleID == bundleID {
                r = cur
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let probe = r else {
            return .failed("Couldn't capture \(displayName(for: bundleID))'s window. Make sure it's open and visible, then try again.")
        }
        guard let p = await runOverlay(frame: probe.frame, observeBundleID: bundleID) else { return .cancelled }
        let fp = FocusPoint(x: p.x / probe.frame.width, y: p.y / probe.frame.height)
        store.update { $0.overrides[bundleID] = fp }
        return .completed
    }

    /// Best-effort human-readable app name for failure messages.
    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return bundleID }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }

    @MainActor
    private final class Box {
        var observer: NSObjectProtocol?
        var resumed: Bool = false
        let overlay: PickerOverlayWindow
        let cont: CheckedContinuation<CGPoint?, Never>

        init(overlay: PickerOverlayWindow, cont: CheckedContinuation<CGPoint?, Never>) {
            self.overlay = overlay
            self.cont = cont
        }

        func resume(_ point: CGPoint?) {
            if resumed { return }
            resumed = true
            if let obs = observer {
                NotificationCenter.default.removeObserver(obs)
                observer = nil
            }
            overlay.orderOut(nil)
            // Break the overlay ⇄ Box retain cycle: the overlay strongly holds
            // the onPick/onCancel closures, which strongly hold this Box, which
            // strongly holds the overlay. Without clearing them, the window and
            // its tracking-area view leak on every pick.
            overlay.onPick = nil
            overlay.onCancel = nil
            cont.resume(returning: point)
        }
    }

    private func runOverlay(frame axTLFrame: CGRect, observeBundleID: String?) async -> CGPoint? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGPoint?, Never>) in
            let overlay = PickerOverlayWindow(axTopLeftFrame: axTLFrame)
            let box = Box(overlay: overlay, cont: cont)
            overlay.onPick = { [box] p in box.resume(p) }
            overlay.onCancel = { [box] in box.resume(nil) }
            if let bid = observeBundleID {
                box.observer = NotificationCenter.default.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    let matches = app?.bundleIdentifier == bid
                    if matches {
                        Task { @MainActor [box] in box.resume(nil) }
                    }
                }
            }
            overlay.makeKeyAndOrderFront(nil)
        }
    }
}
