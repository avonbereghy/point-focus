import AppKit
import CoreGraphics

@MainActor
final class FocusRouter {
    private let store: SettingsStore
    private let events: EventTapService
    private let perms: PermissionsService
    private var task: Task<Void, Never>?

    init(store: SettingsStore, events: EventTapService, perms: PermissionsService) {
        self.store = store
        self.events = events
        self.perms = perms
    }

    func start() {
        task?.cancel()
        let stream = events.events
        task = Task { @MainActor [weak self] in
            for await _ in stream {
                self?.handle()
            }
        }
    }

    private func handle() {
        guard store.settings.enabled else { return }
        guard perms.accessibility == .granted && perms.inputMonitoring == .granted else { return }
        guard let r = FocusedWindowProbe.current() else { return }
        let rp = store.focusPoint(for: r.bundleID)
        let target = CGPoint(
            x: r.frame.minX + r.frame.width * rp.x,
            y: r.frame.minY + r.frame.height * rp.y
        )
        CursorWarpService.warp(to: target)
    }
}
