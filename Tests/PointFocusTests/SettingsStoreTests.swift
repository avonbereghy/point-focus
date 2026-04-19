import XCTest
@testable import PointFocus

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "PointFocusTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testFreshStoreHasDefaults() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, .default)
    }

    func testFocusPointForUnknownBundleFallsBackToGlobal() {
        let store = SettingsStore(defaults: defaults)
        store.update { $0.globalPoint = FocusPoint(x: 0.3, y: 0.7) }
        XCTAssertEqual(store.focusPoint(for: "com.nowhere.app"), FocusPoint(x: 0.3, y: 0.7))
    }

    func testFocusPointForKnownBundleUsesOverride() {
        let store = SettingsStore(defaults: defaults)
        store.update {
            $0.globalPoint = FocusPoint(x: 0.5, y: 0.5)
            $0.overrides["com.apple.Terminal"] = FocusPoint(x: 0.1, y: 0.9)
        }
        XCTAssertEqual(store.focusPoint(for: "com.apple.Terminal"), FocusPoint(x: 0.1, y: 0.9))
        XCTAssertEqual(store.focusPoint(for: "com.other.app"), FocusPoint(x: 0.5, y: 0.5))
    }

    func testPersistenceSurvivesNewInstance() async throws {
        let a = SettingsStore(defaults: defaults)
        a.update {
            $0.enabled = false
            $0.overrides["com.apple.Safari"] = FocusPoint(x: 0.2, y: 0.8)
        }
        // debounce is 200ms — wait long enough for persistence
        try await Task.sleep(nanoseconds: 400_000_000)

        let b = SettingsStore(defaults: defaults)
        XCTAssertFalse(b.settings.enabled)
        XCTAssertEqual(b.settings.overrides["com.apple.Safari"], FocusPoint(x: 0.2, y: 0.8))
    }

    func testMalformedPayloadFallsBackToDefaults() {
        defaults.set("this is not json".data(using: .utf8)!, forKey: "com.avb.pointfocus.v1")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, .default)
    }
}
