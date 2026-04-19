import XCTest
@testable import PointFocus

final class FocusPointTests: XCTestCase {
    func testClampsBelowZero() {
        let p = FocusPoint(x: -0.5, y: -1.0)
        XCTAssertEqual(p.x, 0.0)
        XCTAssertEqual(p.y, 0.0)
    }

    func testClampsAboveOne() {
        let p = FocusPoint(x: 1.2, y: 2.5)
        XCTAssertEqual(p.x, 1.0)
        XCTAssertEqual(p.y, 1.0)
    }

    func testPreservesInRangeValues() {
        let p = FocusPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(p.x, 0.25)
        XCTAssertEqual(p.y, 0.75)
    }

    func testCenterIsHalfHalf() {
        XCTAssertEqual(FocusPoint.center.x, 0.5)
        XCTAssertEqual(FocusPoint.center.y, 0.5)
    }

    func testCodableRoundTrip() throws {
        let original = FocusPoint(x: 0.3, y: 0.8)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FocusPoint.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
