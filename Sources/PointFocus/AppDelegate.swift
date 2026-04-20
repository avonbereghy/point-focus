import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SettingsStore()
    let perms = PermissionsService()
    let events = EventTapService()
    let launch = LaunchAtLoginService()
    lazy var picker = PickerCoordinator(store: store)
    lazy var router = FocusRouter(store: store, events: events, perms: perms)
    var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        perms.refreshNow()
        perms.startPolling()

        if perms.accessibility != .granted || perms.inputMonitoring != .granted {
            OnboardingWindowController.shared.show(perms: perms)
        }

        // Event tap is started by FocusRouter only once Input Monitoring is
        // confirmed granted — creating it before permission lands leaves the
        // tap permanently dead for this process.
        router.start()

        menuBar = MenuBarController(
            store: store,
            perms: perms,
            launch: launch,
            picker: picker,
            onShowOnboarding: { [unowned self] in
                OnboardingWindowController.shared.show(perms: self.perms)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        events.stop()
        perms.stopPolling()
    }
}
