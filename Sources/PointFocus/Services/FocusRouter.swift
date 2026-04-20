import AppKit
import CoreGraphics

@MainActor
final class FocusRouter {
    private let store: SettingsStore
    private let events: EventTapService
    private let perms: PermissionsService
    private var task: Task<Void, Never>?
    private var tapStarted = false

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
        observePermissions()
    }

    private func observePermissions() {
        withObservationTracking {
            _ = perms.accessibility
            _ = perms.inputMonitoring
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.tryStartTap()
                self?.observePermissions()
            }
        }
        tryStartTap()
    }

    private func tryStartTap() {
        guard !tapStarted else { return }
        guard perms.inputMonitoring == .granted else { return }
        do {
            try events.start()
            tapStarted = true
        } catch {
            PFLog.router.log("tap start failed — \(String(describing: error), privacy: .public)")
        }
    }

    private func handle() {
        guard store.settings.enabled else { return }
        guard perms.accessibility == .granted && perms.inputMonitoring == .granted else { return }

        // Snapshot the focused app BEFORE the switch commits, then poll briefly
        // for it to change. macOS's app activation lands ~50-150ms after we see
        // Cmd release, so querying immediately gets the previous app's frame.
        let initialBundle = FocusedWindowProbe.current()?.bundleID

        Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(0.3)
            var target: FocusedWindowProbe.Result?
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 20_000_000)
                if let cur = FocusedWindowProbe.current(),
                   cur.bundleID != initialBundle {
                    target = cur
                    break
                }
            }
            guard let r = target ?? FocusedWindowProbe.current() else { return }
            let rp = self.store.focusPoint(for: r.bundleID)
            let point = CGPoint(
                x: r.frame.minX + r.frame.width * rp.x,
                y: r.frame.minY + r.frame.height * rp.y
            )
            CursorWarpService.warp(to: point)
        }
    }
}
