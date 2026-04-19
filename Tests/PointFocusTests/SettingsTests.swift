import XCTest
@testable import PointFocus

final class SettingsTests: XCTestCase {
    func testDefaultValues() {
        let s = Settings.default
        XCTAssertTrue(s.enabled)
        XCTAssertFalse(s.launchAtLogin)
        XCTAssertEqual(s.globalPoint, .center)
        XCTAssertTrue(s.overrides.isEmpty)
    }

    func testCodableRoundTripEmpty() throws {
        let s = Settings.default
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s, decoded)
    }

    func testCodableRoundTripWithOverrides() throws {
        var s = Settings.default
        s.enabled = false
        s.launchAtLogin = true
        s.globalPoint = FocusPoint(x: 0.2, y: 0.4)
        s.overrides = [
            "com.apple.Terminal": FocusPoint(x: 0.1, y: 0.9),
            "com.apple.Safari": FocusPoint(x: 0.5, y: 0.5)
        ]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s, decoded)
        XCTAssertEqual(decoded.overrides["com.apple.Terminal"], FocusPoint(x: 0.1, y: 0.9))
    }
}
