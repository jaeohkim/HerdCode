import XCTest
@testable import HerdCode

final class FloatingPanelPlacementTests: XCTestCase {

    private let screen = ScreenGeometry(
        visibleFrame: NSRect(x: 0, y: 23, width: 1440, height: 877)
    )
    private let panelHeight: CGFloat = 480

    func testNoSavedOriginReturnTopRight() {
        let frame = PanelPlacement.resolveFrame(
            savedOrigin: nil,
            height: panelHeight,
            screen: screen
        )
        let expected = PanelPlacement.topRightFrame(height: panelHeight, screen: screen)
        XCTAssertEqual(frame, expected)
    }

    func testValidSavedOriginUsesRestoredFrame() {
        let margin = PanelPlacement.windowMargin
        let width = PanelPlacement.panelWidth
        let origin = NSPoint(
            x: screen.visibleFrame.minX + margin,
            y: screen.visibleFrame.minY + margin
        )
        let frame = PanelPlacement.resolveFrame(
            savedOrigin: origin,
            height: panelHeight,
            screen: screen
        )
        XCTAssertEqual(frame.origin, origin)
        XCTAssertEqual(frame.size.width, width)
        XCTAssertEqual(frame.size.height, panelHeight)
    }

    func testInvalidSavedOriginPartiallyOutsideFallsBackToTopRight() {
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - PanelPlacement.panelWidth + 100,
            y: screen.visibleFrame.maxY - panelHeight + 100
        )
        let frame = PanelPlacement.resolveFrame(
            savedOrigin: origin,
            height: panelHeight,
            screen: screen
        )
        let expected = PanelPlacement.topRightFrame(height: panelHeight, screen: screen)
        XCTAssertEqual(frame, expected)
    }

    func testTopRightAnchorStableWhenHeightChanges() {
        let heightA: CGFloat = 300
        let heightB: CGFloat = 700

        let frameA = PanelPlacement.resolveFrame(savedOrigin: nil, height: heightA, screen: screen)
        let frameB = PanelPlacement.resolveFrame(savedOrigin: nil, height: heightB, screen: screen)

        XCTAssertEqual(frameA.maxX, frameB.maxX, accuracy: 1,
                       "top-right anchor X 는 height 변경에 영향받지 않아야 함")
        XCTAssertEqual(frameA.maxY, frameB.maxY, accuracy: 1,
                       "top-right anchor Y(maxY) 는 height 변경에 영향받지 않아야 함")
    }
}
