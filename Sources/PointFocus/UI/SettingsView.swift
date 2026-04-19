import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let perms: PermissionsService
    let picker: PickerCoordinator
    let launch: LaunchAtLoginService

    private static let pointFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = 0
        f.maximum = 1
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.enabled },
            set: { newValue in store.update { $0.enabled = newValue } }
        )
    }

    private var globalXBinding: Binding<Double> {
        Binding(
            get: { store.settings.globalPoint.x },
            set: { newValue in
                store.update {
                    $0.globalPoint = FocusPoint(x: newValue, y: $0.globalPoint.y)
                }
            }
        )
    }

    private var globalYBinding: Binding<Double> {
        Binding(
            get: { store.settings.globalPoint.y },
            set: { newValue in
                store.update {
                    $0.globalPoint = FocusPoint(x: $0.globalPoint.x, y: newValue)
                }
            }
        )
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launch.isEnabled },
            set: { newValue in
                try? launch.set(newValue)
                store.update { $0.launchAtLogin = launch.isEnabled }
            }
        )
    }

    var body: some View {
        Form {
            Section("Status") {
                Toggle("Enabled", isOn: enabledBinding)
                HStack(spacing: 12) {
                    permissionChip(label: "Accessibility", state: perms.accessibility)
                    permissionChip(label: "Input Monitoring", state: perms.inputMonitoring)
                    Spacer()
                    Button("Fix permissions…") {
                        OnboardingWindowController.shared.show(perms: perms)
                    }
                }
            }

            Section("Global default focus point") {
                HStack {
                    Text("x")
                    TextField("", value: globalXBinding, formatter: Self.pointFormatter)
                        .frame(width: 80)
                    Stepper("", value: globalXBinding, in: 0...1, step: 0.01)
                        .labelsHidden()
                }
                HStack {
                    Text("y")
                    TextField("", value: globalYBinding, formatter: Self.pointFormatter)
                        .frame(width: 80)
                    Stepper("", value: globalYBinding, in: 0...1, step: 0.01)
                        .labelsHidden()
                }
                Button("Pick on screen…") {
                    Task { _ = await picker.pickGlobal() }
                }
            }

            Section("Per-app overrides") {
                let entries = store.settings.overrides.sorted(by: { $0.key < $1.key })
                ForEach(entries, id: \.key) { entry in
                    AppOverrideRow(
                        bundleID: entry.key,
                        point: entry.value,
                        onRepick: {
                            let id = entry.key
                            Task { _ = await picker.pick(bundleID: id) }
                        },
                        onRemove: {
                            let id = entry.key
                            store.update { $0.overrides.removeValue(forKey: id) }
                        }
                    )
                }
                Button("Add app…") { addApp() }
            }

            Section("Launch at login") {
                Toggle("Launch PointFocus at login", isOn: launchBinding)
            }

            Section {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit PointFocus")
                }
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 600)
    }

    @ViewBuilder
    private func permissionChip(label: String, state: PermissionState) -> some View {
        let granted = state == .granted
        HStack(spacing: 6) {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text("\(label): \(granted ? "Granted" : "Not granted")")
                .font(.caption)
                .foregroundStyle(granted ? .secondary : .primary)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        Task { _ = await picker.pick(bundleID: bundleID) }
    }
}
