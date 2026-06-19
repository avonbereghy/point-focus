import AppKit
import CoreGraphics

@MainActor
final class FocusRouter {
    // How long to wait for the newly-focused app to commit after Cmd release,
    // and how often to re-probe while waiting. Activation typically lands
    // ~50-150ms after we see Cmd release.
    private static let probeDeadline: TimeInterval = 0.3
    private static let probePollInterval: UInt64 = 20_000_000  // 20ms

    // Event-tap creation can transiently fail even when Input Monitoring is
    // already granted; retry a bounded number of times so the app isn't left
    // permanently dead until the next relaunch.
    private static let maxTapStartAttempts = 5
    private static let tapRetryDelay: TimeInterval = 1.0

    private let store: SettingsStore
    private let events: EventTapService
    private let perms: PermissionsService
    private var task: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var tapStarted = false
    private var tapStartAttempts = 0

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
            tapStartAttempts = 0
        } catch {
            PFLog.router.error("tap start failed (attempt \(self.tapStartAttempts + 1)) — \(String(describing: error), privacy: .public)")
            scheduleTapRetry()
        }
    }

    private func scheduleTapRetry() {
        guard tapStartAttempts < Self.maxTapStartAttempts else {
            PFLog.router.error("giving up on event tap after \(Self.maxTapStartAttempts) attempts")
            return
        }
        tapStartAttempts += 1
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.tapRetryDelay * 1_000_000_000))
            guard let self, !self.tapStarted else { return }
            self.tryStartTap()
        }
    }

    private func handle() {
        guard store.settings.enabled else {
            PFLog.warp.debug("ignoring Cmd+Tab — PointFocus is disabled")
            return
        }
        guard perms.accessibility == .granted && perms.inputMonitoring == .granted else {
            PFLog.warp.debug("ignoring Cmd+Tab — permissions not granted")
            return
        }

        // Snapshot the focused app BEFORE the switch commits, then poll briefly
        // for it to change. macOS's app activation lands ~50-150ms after we see
        // Cmd release, so querying immediately gets the previous app's frame. AX
        // can momentarily fail to resolve a focused window mid-switch, so fall
        // back to NSWorkspace's frontmost app for a reliable baseline.
        let baseline = FocusedWindowProbe.current()?.bundleID
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // Cancel any in-flight probe from a prior Cmd+Tab so rapid switching
        // can't leave a stale probe racing to warp into the wrong window.
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(Self.probeDeadline)
            var target: FocusedWindowProbe.Result?
            while Date() < deadline {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: Self.probePollInterval)
                guard let cur = FocusedWindowProbe.current() else { continue }
                if let baseline {
                    // We know the outgoing app — wait until a different app wins.
                    if cur.bundleID != baseline {
                        target = cur
                        break
                    }
                } else {
                    // No baseline at all: we can't tell old from new, so keep
                    // the most recent successful read and let it settle.
                    target = cur
                }
            }
            guard !Task.isCancelled else { return }
            guard let r = target ?? FocusedWindowProbe.current() else {
                PFLog.warp.debug("no focused window resolved — skipping warp")
                return
            }
            let rp = self.store.focusPoint(for: r.bundleID)
            let point = CGPoint(
                x: r.frame.minX + r.frame.width * rp.x,
                y: r.frame.minY + r.frame.height * rp.y
            )
            PFLog.warp.debug("warping to \(r.bundleID, privacy: .public) at (\(point.x), \(point.y))")
            CursorWarpService.warp(to: point)
        }
    }
}
