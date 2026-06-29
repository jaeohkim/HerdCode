import XCTest
@testable import HerdCode

@MainActor
final class HerdCodePanelVisibilityTests: XCTestCase {
    func testJumpDoesNotHideVisiblePanel() async throws {
        let logger = TestJumpLogger()
        let service = HerdrService(
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: logger
        )
        let monitor = StatusMonitor(herdrService: service, pollInterval: 999)

        let agent = HerdrAgent(
            agent: "opencode",
            agentStatus: "working",
            cwd: "/tmp",
            focused: true,
            paneId: "pane-test",
            tabId: "tab-1",
            workspaceId: "ws-1",
            agentSession: nil
        )

        await monitor.jumpToAgent(agent)

        XCTAssertNil(monitor.lastError)
        XCTAssertFalse(logger.lines.contains { $0.contains("[HerdCodeJumpError]") })
    }
}
