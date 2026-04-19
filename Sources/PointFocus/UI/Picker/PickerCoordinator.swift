import AppKit
import Foundation

@MainActor
final class PickerCoordinator {
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func pickGlobal() async -> Bool {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let primaryMaxY = (NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? screen).frame.maxY
        let tlFrame = CGRect(
            x: screen.visibleFrame.minX,
            y: primaryMaxY - screen.visibleFrame.maxY,
            width: screen.visibleFrame.width,
            height: screen.visibleFrame.height
        )
        let result = await runOverlay(frame: tlFrame, observeBundleID: nil)
        guard let p = result else { return false }
        let fp = FocusPoint(x: p.x / tlFrame.width, y: p.y / tlFrame.height)
        store.update { $0.globalPoint = fp }
        return true
    }

    func pick(bundleID: String) async -> Bool {
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                return false
            }
        }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate(options: [.activateAllWindows])
        }
        let deadline = Date().addingTimeInterval(5.0)
        var r: FocusedWindowProbe.Result? = nil
        while Date() < deadline {
            if let cur = FocusedWindowProbe.current(), cur.bundleID == bundleID {
                r = cur
                break
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        guard let probe = r else { return false }
        let click = await runOverlay(frame: probe.frame, observeBundleID: bundleID)
        guard let p = click else { return false }
        let fp = FocusPoint(x: p.x / probe.frame.width, y: p.y / probe.frame.height)
        store.update { $0.overrides[bundleID] = fp }
        return true
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
