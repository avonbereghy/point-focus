import Foundation

struct Settings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var launchAtLogin: Bool = false
    var globalPoint: FocusPoint = .center
    var overrides: [String: FocusPoint] = [:]

    static let `default` = Settings()
}
