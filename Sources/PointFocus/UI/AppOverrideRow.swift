import AppKit
import SwiftUI

struct AppOverrideRow: View {
    let bundleID: String
    let point: FocusPoint
    var canRepick: Bool = true
    var onRepick: () -> Void
    var onRemove: () -> Void

    var body: some View {
        let name = displayNameForBundleID(bundleID)
        HStack(spacing: 10) {
            Image(nsImage: iconForBundleID(bundleID))
                .resizable()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "x: %.2f  y: %.2f", point.x, point.y))
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel(String(format: "Focus point x %.2f, y %.2f", point.x, point.y))
            Button("Re-pick", action: onRepick)
                .accessibilityLabel("Re-pick focus point for \(name)")
                .disabled(!canRepick)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Remove override for \(name)")
        }
    }
}

private func iconForBundleID(_ id: String) -> NSImage {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil) ?? NSImage()
}

private func displayNameForBundleID(_ id: String) -> String {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
       let bundle = Bundle(url: url) {
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
    }
    return id
}
