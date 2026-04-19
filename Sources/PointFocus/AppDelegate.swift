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

        do {
            try events.start()
        } catch {
            NSLog("PointFocus: failed to start event tap — \(error)")
        }
        router.start()

        menuBar = MenuBarController(
            store: store,
            perms: perms,
            launch: launch,
            onShowSettings: { [unowned self] in
                SettingsWindowController.shared.show(
                    store: self.store,
                    perms: self.perms,
                    picker: self.picker,
                    launch: self.launch
                )
            },
            onShowOnboarding: { [unowned self] in
                OnboardingWindowController.shared.show(perms: self.perms)
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        events.stop()
        perms.stopPolling()
    }
}
