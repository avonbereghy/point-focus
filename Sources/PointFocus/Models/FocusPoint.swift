import Foundation

struct FocusPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
    }

    static let center = FocusPoint(x: 0.5, y: 0.5)
}
