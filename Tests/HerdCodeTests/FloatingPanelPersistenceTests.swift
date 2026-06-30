import XCTest
@testable import HerdCode

final class FloatingPanelPersistenceTests: XCTestCase {

    private static let testSuiteName = "HerdCode.PersistenceTests"
    private static let originKey = "HerdCode.windowOrigin"

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: Self.testSuiteName)!
        defaults.removePersistentDomain(forName: Self.testSuiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.testSuiteName)
        defaults = nil
        super.tearDown()
    }

    func testSaveAndRestoreOriginRoundTrip() {
        let point = NSPoint(x: 123.5, y: 456.0)
        defaults.set(NSStringFromPoint(point), forKey: Self.originKey)

        guard let stored = defaults.string(forKey: Self.originKey) else {
            XCTFail("저장된 값이 없음")
            return
        }
        let restored = NSPointFromString(stored)
        XCTAssertEqual(restored.x, point.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, point.y, accuracy: 0.001)
    }

    func testRestoredOriginReturnsNilWhenNotSet() {
        let stored = defaults.string(forKey: Self.originKey)
        XCTAssertNil(stored, "저장값 없을 때 nil이어야 함")
    }

    func testOverwriteOriginKeepsLatestValue() {
        let first = NSPoint(x: 10, y: 20)
        let second = NSPoint(x: 300, y: 400)

        defaults.set(NSStringFromPoint(first), forKey: Self.originKey)
        defaults.set(NSStringFromPoint(second), forKey: Self.originKey)

        guard let stored = defaults.string(forKey: Self.originKey) else {
            XCTFail("저장된 값이 없음")
            return
        }
        let restored = NSPointFromString(stored)
        XCTAssertEqual(restored.x, second.x, accuracy: 0.001)
        XCTAssertEqual(restored.y, second.y, accuracy: 0.001)
    }

    func testOriginKeyFormat() {
        let point = NSPoint(x: 42, y: 99)
        let encoded = NSStringFromPoint(point)
        let decoded = NSPointFromString(encoded)
        XCTAssertEqual(decoded, point)
    }
}
