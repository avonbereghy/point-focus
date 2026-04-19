import Foundation
import Observation

@Observable @MainActor
final class SettingsStore {
    private static let storageKey = "com.avb.pointfocus.v1"
    private static let debounceSeconds = 0.2

    private(set) var settings: Settings
    private let defaults: UserDefaults
    @ObservationIgnored private var pendingWrite: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    func update(_ mutate: (inout Settings) -> Void) {
        mutate(&settings)
        schedulePersist()
    }

    func focusPoint(for bundleID: String) -> FocusPoint {
        settings.overrides[bundleID] ?? settings.globalPoint
    }

    private func schedulePersist() {
        pendingWrite?.cancel()
        let snapshot = settings
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let data = try? JSONEncoder().encode(snapshot) {
                self.defaults.set(data, forKey: Self.storageKey)
            }
        }
        pendingWrite = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceSeconds, execute: work)
    }
}
