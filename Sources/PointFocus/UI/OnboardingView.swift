import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics

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
                action: requestAccessibility
            )
            permissionRow(
                title: "Input Monitoring",
                description: "Detect the Cmd+Tab key combination.",
                state: perms.inputMonitoring,
                action: requestInputMonitoring
            )
            Text("This window will close automatically once both are granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 460)
    }

    @ViewBuilder
    private func permissionRow(title: String, description: String, state: PermissionState, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            chip(state: state)
            Button(state == .granted ? "Granted" : "Grant…", action: action)
                .disabled(state == .granted)
        }
    }

    // Trigger the native TCC prompt AND open System Settings. The prompt
    // causes macOS to add PointFocus to the relevant Privacy list if it
    // wasn't there already (e.g., after a tccutil reset).
    private func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the literal value of
        // kAXTrustedCheckOptionPrompt; using the literal avoids Swift 6
        // strict-concurrency complaints about the imported global.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private func openURL(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
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
