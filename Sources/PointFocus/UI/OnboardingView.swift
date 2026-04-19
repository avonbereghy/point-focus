import SwiftUI
import AppKit

struct OnboardingView: View {
    let perms: PermissionsService

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to PointFocus")
                .font(.largeTitle)
                .bold()
            Text("PointFocus needs two permissions to detect Cmd+Tab and read window positions.")
                .foregroundStyle(.secondary)
            permissionRow(
                title: "Accessibility",
                description: "Read the focused window's frame.",
                state: perms.accessibility,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
            permissionRow(
                title: "Input Monitoring",
                description: "Detect the Cmd+Tab key combination.",
                state: perms.inputMonitoring,
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
            Text("This window will close automatically once both are granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }

    @ViewBuilder
    private func permissionRow(title: String, description: String, state: PermissionState, settingsURL: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            chip(state: state)
            Button("Open System Settings") {
                if let url = URL(string: settingsURL) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(state: PermissionState) -> some View {
        if state == .granted {
            Text("Granted")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.2), in: Capsule())
                .foregroundStyle(.green)
        } else {
            Text("Not granted")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.2), in: Capsule())
                .foregroundStyle(.red)
        }
    }
}
