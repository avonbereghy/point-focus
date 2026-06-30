import Foundation

struct Settings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var launchAtLogin: Bool = false
    var globalPoint: FocusPoint = .center
    var overrides: [String: FocusPoint] = [:]

    init() {}

    // Swift's synthesized init(from:) throws keyNotFound on any missing key,
    // which SettingsStore swallows via `try?` and resets ALL settings to
    // .default. Decode each key independently so a future schema change (a
    // field added in a newer build, or removed in an older one) preserves the
    // user's existing settings instead of silently wiping them.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try container.decodeIfPresent(Bool.self, forKey: .enabled) { enabled = v }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) { launchAtLogin = v }
        if let v = try container.decodeIfPresent(FocusPoint.self, forKey: .globalPoint) { globalPoint = v }
        if let v = try container.decodeIfPresent([String: FocusPoint].self, forKey: .overrides) { overrides = v }
    }

    static let `default` = Settings()
}
