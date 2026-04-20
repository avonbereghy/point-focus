import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var store: SettingsStore
    let perms: PermissionsService
    let picker: PickerCoordinator
    let launch: LaunchAtLoginService
    var onDismiss: () -> Void = {}
    var onShowOnboarding: () -> Void = {}

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
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusSection
            globalPointSection
            overridesSection
            Divider()
            bottomRow
        }
        .padding(14)
        .frame(width: 440, height: 500, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("PointFocus")
                .font(.headline)
            Spacer()
            Text("v1.0.0").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable cursor warp on Cmd+Tab", isOn: enabledBinding)
            HStack(spacing: 10) {
                permissionChip(label: "Accessibility", state: perms.accessibility)
                permissionChip(label: "Input Monitoring", state: perms.inputMonitoring)
                Spacer()
                if perms.accessibility != .granted || perms.inputMonitoring != .granted {
                    Button("Fix permissions…", action: onShowOnboarding)
                        .controlSize(.small)
                }
            }
        }
    }

    private var globalPointSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Global default focus point").font(.subheadline).bold()
            Text("Where the cursor lands when there's no per-app override. 0.0 = top/left, 1.0 = bottom/right.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text("x").frame(width: 12, alignment: .trailing)
                TextField("", value: globalXBinding, formatter: Self.pointFormatter)
                    .frame(width: 72)
                Stepper("", value: globalXBinding, in: 0...1, step: 0.01).labelsHidden()
                Text("y").frame(width: 12, alignment: .trailing).padding(.leading, 8)
                TextField("", value: globalYBinding, formatter: Self.pointFormatter)
                    .frame(width: 72)
                Stepper("", value: globalYBinding, in: 0...1, step: 0.01).labelsHidden()
                Spacer()
                Button("Pick on screen…") {
                    onDismiss()
                    Task { _ = await picker.pickGlobal() }
                }
                .controlSize(.small)
            }
        }
    }

    private var overridesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Per-app overrides").font(.subheadline).bold()
                Spacer()
                Button("Add app…") { addApp() }
                    .controlSize(.small)
            }
            let entries = store.settings.overrides.sorted(by: { $0.key < $1.key })
            if entries.isEmpty {
                Text("No overrides yet. Add an app to set a point that only applies when you Cmd+Tab to it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(entries, id: \.key) { entry in
                            AppOverrideRow(
                                bundleID: entry.key,
                                point: entry.value,
                                onRepick: {
                                    let id = entry.key
                                    onDismiss()
                                    Task { _ = await picker.pick(bundleID: id) }
                                },
                                onRemove: {
                                    let id = entry.key
                                    store.update { $0.overrides.removeValue(forKey: id) }
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var bottomRow: some View {
        HStack {
            Toggle("Launch at login", isOn: launchBinding)
                .controlSize(.small)
            Spacer()
            Button("Quit PointFocus", role: .destructive) {
                NSApp.terminate(nil)
            }
            .controlSize(.small)
        }
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
                .foregroundStyle(.secondary)
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
        onDismiss()
        Task { _ = await picker.pick(bundleID: bundleID) }
    }
}
