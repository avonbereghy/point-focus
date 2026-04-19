import AppKit
import Observation

@MainActor
final class MenuBarController: NSObject {
    private let store: SettingsStore
    private let perms: PermissionsService
    private let launch: LaunchAtLoginService
    private let onShowSettings: () -> Void
    private let onShowOnboarding: () -> Void
    private let onQuit: () -> Void
    private let statusItem: NSStatusItem

    init(store: SettingsStore,
         perms: PermissionsService,
         launch: LaunchAtLoginService,
         onShowSettings:   @escaping () -> Void,
         onShowOnboarding: @escaping () -> Void,
         onQuit:           @escaping () -> Void) {
        self.store = store
        self.perms = perms
        self.launch = launch
        self.onShowSettings = onShowSettings
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(onClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshIcon()
        startObservation()
    }

    @objc private func onClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
        let optionHeld = event?.modifierFlags.contains(.option) == true
        if isRightClick || optionHeld {
            showMenu()
        } else {
            store.update { $0.enabled.toggle() }
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let enabledItem = NSMenuItem(title: "Enabled",
                                     action: #selector(toggleEnabled),
                                     keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = store.settings.enabled ? .on : .off
        menu.addItem(enabledItem)

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(showSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launchItem = NSMenuItem(title: "Launch at Login",
                                    action: #selector(toggleLaunchAtLogin),
                                    keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launch.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let permissionsMissing = perms.accessibility != .granted || perms.inputMonitoring != .granted
        if permissionsMissing {
            menu.addItem(NSMenuItem.separator())
            let fixItem = NSMenuItem(title: "Fix Permissions…",
                                     action: #selector(showOnboarding),
                                     keyEquivalent: "")
            fixItem.target = self
            menu.addItem(fixItem)
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit PointFocus",
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleEnabled() {
        store.update { $0.enabled.toggle() }
    }

    @objc private func showSettings() {
        onShowSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        try? launch.set(!launch.isEnabled)
        store.update { $0.launchAtLogin = launch.isEnabled }
    }

    @objc private func showOnboarding() {
        onShowOnboarding()
    }

    @objc private func quit() {
        onQuit()
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let name: String
        if perms.accessibility != .granted || perms.inputMonitoring != .granted {
            name = "exclamationmark.triangle"
        } else if !store.settings.enabled {
            name = "scope.slash"
        } else {
            name = "scope"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
    }

    private func startObservation() {
        withObservationTracking {
            _ = store.settings.enabled
            _ = perms.accessibility
            _ = perms.inputMonitoring
        } onChange: {
            Task { @MainActor in
                self.refreshIcon()
                self.startObservation()
            }
        }
    }
}
