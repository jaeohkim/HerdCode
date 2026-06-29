import XCTest
@testable import HerdCode

@MainActor
final class HerdCodeStatusMonitorJumpTests: XCTestCase {
    func testJumpToAgentCallsActivationAndFocus() async throws {
        let events = LockedEvents()
        let service = HerdrService(
            appActivator: FakeAppActivator { events.append("activate") },
            jumpExecutor: FakeJumpExecutor { _ in events.append("focus") },
            jumpLogger: TestJumpLogger()
        )
        let monitor = StatusMonitor(herdrService: service, pollInterval: 999)

        let agent = HerdrAgent(
            agent: "opencode",
            agentStatus: "working",
            cwd: "/tmp",
            focused: true,
            paneId: "pane-agent-test",
            tabId: "tab-1",
            workspaceId: "ws-1",
            agentSession: nil
        )

        await monitor.jumpToAgent(agent)

        XCTAssertEqual(events.snapshot(), ["activate", "focus"])
        XCTAssertNil(monitor.lastError)
    }

    func testJumpToSessionCallsActivationAndFocusWhenMapped() async throws {
        let events = LockedEvents()
        let service = HerdrService(
            appActivator: FakeAppActivator { events.append("activate") },
            jumpExecutor: FakeJumpExecutor { paneId in events.append("focus:\(paneId)") },
            jumpLogger: TestJumpLogger()
        )
        let monitor = StatusMonitor(herdrService: service, pollInterval: 999)

        let session = OpencodeSession(
            id: "ses-test",
            title: "Test Session",
            projectId: "proj-1",
            timeCreated: .distantPast,
            timeUpdated: .distantPast,
            timeArchived: nil,
            agent: nil,
            model: nil,
            cost: 0,
            tokensInput: 0,
            tokensOutput: 0
        )
        let agent = HerdrAgent(
            agent: "opencode",
            agentStatus: "working",
            cwd: "/tmp",
            focused: true,
            paneId: "pane-session-test",
            tabId: "tab-1",
            workspaceId: "ws-1",
            agentSession: HerdrAgentSession(
                source: "herdr:opencode",
                agent: "opencode",
                kind: "id",
                value: session.id
            )
        )

        monitor.state = AppState(herdrAgents: [agent])

        await monitor.jumpToSession(session)

        XCTAssertTrue(events.snapshot().contains("activate"))
        XCTAssertTrue(events.snapshot().contains("focus:pane-session-test"))
        XCTAssertNil(monitor.lastError)
    }

    func testJumpToAgentDoesNotHidePanel() async throws {
        let service = HerdrService(
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger()
        )
        let monitor = StatusMonitor(herdrService: service, pollInterval: 999)

        let agent = HerdrAgent(
            agent: "opencode",
            agentStatus: "working",
            cwd: "/tmp",
            focused: true,
            paneId: "pane-panel-test",
            tabId: "tab-1",
            workspaceId: "ws-1",
            agentSession: nil
        )

        await monitor.jumpToAgent(agent)

        XCTAssertNil(monitor.lastError)
    }
}
