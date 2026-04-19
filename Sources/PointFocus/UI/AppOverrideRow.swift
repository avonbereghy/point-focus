import AppKit
import SwiftUI

struct AppOverrideRow: View {
    let bundleID: String
    let point: FocusPoint
    var onRepick: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: iconForBundleID(bundleID))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayNameForBundleID(bundleID))
                    .font(.headline)
                Text(bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "x: %.2f  y: %.2f", point.x, point.y))
                .font(.system(.body, design: .monospaced))
            Button("Re-pick", action: onRepick)
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
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
