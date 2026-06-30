import Foundation

struct FocusPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = FocusPoint.clamp(x)
        self.y = FocusPoint.clamp(y)
    }

    // Codable synthesis writes the stored properties directly, bypassing the
    // clamp in init(x:y:). Decode through the clamp so a corrupted or
    // hand-edited UserDefaults blob (out-of-range, NaN, or inf) can't place the
    // cursor outside the target window or feed a non-finite value into
    // CGWarpMouseCursorPosition.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try container.decode(Double.self, forKey: .x),
                  y: try container.decode(Double.self, forKey: .y))
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return max(0, min(1, value))
    }

    static let center = FocusPoint(x: 0.5, y: 0.5)
}
