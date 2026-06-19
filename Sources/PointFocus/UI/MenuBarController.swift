import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let store: SettingsStore
    private let perms: PermissionsService
    private let launch: LaunchAtLoginService
    private let picker: PickerCoordinator
    private let onShowOnboarding: () -> Void
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<SettingsView>
    private static let popoverSize = NSSize(width: 440, height: 500)

    init(store: SettingsStore,
         perms: PermissionsService,
         launch: LaunchAtLoginService,
         picker: PickerCoordinator,
         onShowOnboarding: @escaping () -> Void) {
        self.store = store
        self.perms = perms
        self.launch = launch
        self.picker = picker
        self.onShowOnboarding = onShowOnboarding
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        // Hosting controller + SettingsView are built ONCE and reused. The
        // dismiss/onboarding callbacks need self, so we defer wiring them
        // below super.init() via the closure-swap pattern.
        let initialView = SettingsView(
            store: store,
            perms: perms,
            picker: picker,
            launch: launch
        )
        self.hostingController = NSHostingController(rootView: initialView)
        self.hostingController.preferredContentSize = Self.popoverSize
        super.init()

        // Now that `self` is available, rebuild the root view with callbacks.
        self.hostingController.rootView = SettingsView(
            store: store,
            perms: perms,
            picker: picker,
            launch: launch,
            onDismiss: { [weak self] in self?.popover.performClose(nil) },
            onShowOnboarding: { [weak self] in
                self?.popover.performClose(nil)
                self?.onShowOnboarding()
            }
        )

        self.popover.behavior = .transient
        self.popover.animates = false
        self.popover.contentViewController = self.hostingController
        self.popover.contentSize = Self.popoverSize

        // Pre-warm the SwiftUI view hierarchy so the first click is instant.
        _ = self.hostingController.view

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(onClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        refreshIcon()
        startObservation()
    }

    @objc private func onClick(_ sender: Any?) {
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let permissionsMissing = perms.accessibility != .granted || perms.inputMonitoring != .granted
        let name: String
        let fallback: String
        if permissionsMissing {
            name = "exclamationmark.triangle"
            fallback = "PF!"
        } else {
            name = "scope"
            fallback = "PF"
        }

        // A human description of the current state for VoiceOver, rather than the
        // raw SF Symbol name ("scope" / "exclamationmark.triangle").
        let stateDescription: String
        if permissionsMissing {
            stateDescription = "Permissions required"
        } else if !store.settings.enabled {
            stateDescription = "Disabled"
        } else {
            stateDescription = "Active"
        }

        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "PointFocus — \(stateDescription)") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = fallback
        }
        button.appearsDisabled = !store.settings.enabled
        button.setAccessibilityLabel("PointFocus")
        button.setAccessibilityValue(stateDescription)
    }

    private func startObservation() {
        withObservationTracking {
            _ = store.settings.enabled
            _ = perms.accessibility
            _ = perms.inputMonitoring
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshIcon()
                self?.startObservation()
            }
        }
    }
}
