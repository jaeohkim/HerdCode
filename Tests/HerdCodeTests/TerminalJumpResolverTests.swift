import XCTest
@testable import HerdCode

final class TerminalJumpResolverTests: XCTestCase {
    func testHerdrAgentWithPaneIdIsEnabled() {
        let agent = makeAgent(paneId: "pane-1")

        let state = TerminalJumpResolver.rowState(for: agent)

        XCTAssertEqual(state.uiKey, "pane-1")
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.focusTarget, "pane-1")
        XCTAssertEqual(state.helpText, "")
    }

    func testHerdrAgentWithoutPaneIdIsDisabledWithFallbackUIKey() {
        let agent = makeAgent(paneId: "", agent: "agent-a", tabId: "tab-7", workspaceId: "ws-3")

        let state = TerminalJumpResolver.rowState(for: agent)

        XCTAssertEqual(state.uiKey, "agent-a|tab-7|ws-3")
        XCTAssertFalse(state.isEnabled)
        XCTAssertNil(state.focusTarget)
        XCTAssertEqual(state.helpText, "현재 연결된 terminal 없음")
    }

    func testOpenCodeSessionWithMatchingAgentIsEnabled() {
        let session = makeSession(id: "session-1")
        let agent = makeAgent(
            paneId: "pane-1",
            agentSession: HerdrAgentSession(source: "herdr:opencode", agent: "agent-a", kind: "id", value: session.id)
        )

        let state = TerminalJumpResolver.rowState(for: session, agents: [agent])

        XCTAssertEqual(state.uiKey, session.id)
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.focusTarget, "pane-1")
        XCTAssertEqual(state.helpText, "")
    }

    func testOpenCodeSessionWithWrongSourceIsDisabled() {
        let session = makeSession(id: "session-1")
        let agent = makeAgent(
            paneId: "pane-1",
            agentSession: HerdrAgentSession(source: "herdr:other", agent: "agent-a", kind: "id", value: session.id)
        )

        let state = TerminalJumpResolver.rowState(for: session, agents: [agent])

        assertDisabledSessionState(state, sessionId: session.id)
    }

    func testOpenCodeSessionWithWrongKindIsDisabled() {
        let session = makeSession(id: "session-1")
        let agent = makeAgent(
            paneId: "pane-1",
            agentSession: HerdrAgentSession(source: "herdr:opencode", agent: "agent-a", kind: "path", value: session.id)
        )

        let state = TerminalJumpResolver.rowState(for: session, agents: [agent])

        assertDisabledSessionState(state, sessionId: session.id)
    }

    func testOpenCodeSessionWithNoMatchingAgentIsDisabled() {
        let session = makeSession(id: "session-1")
        let agent = makeAgent(
            paneId: "pane-1",
            agentSession: HerdrAgentSession(source: "herdr:opencode", agent: "agent-a", kind: "id", value: "session-2")
        )

        let state = TerminalJumpResolver.rowState(for: session, agents: [agent])

        assertDisabledSessionState(state, sessionId: session.id)
    }

    func testOpenCodeSessionMatchingPriorityPrefersFocusedThenWorkingThenLexicographicPaneId() {
        let session = makeSession(id: "session-1")
        let mappedSession = HerdrAgentSession(source: "herdr:opencode", agent: "agent-a", kind: "id", value: session.id)

        let focusedWins = TerminalJumpResolver.rowState(
            for: session,
            agents: [
                makeAgent(paneId: "pane-z", agentStatus: "working", focused: false, agentSession: mappedSession),
                makeAgent(paneId: "pane-b", agentStatus: "idle", focused: true, agentSession: mappedSession),
            ]
        )
        XCTAssertEqual(focusedWins.focusTarget, "pane-b")

        let workingWins = TerminalJumpResolver.rowState(
            for: session,
            agents: [
                makeAgent(paneId: "pane-z", agentStatus: "idle", focused: false, agentSession: mappedSession),
                makeAgent(paneId: "pane-b", agentStatus: "working", focused: false, agentSession: mappedSession),
            ]
        )
        XCTAssertEqual(workingWins.focusTarget, "pane-b")

        let lexicographicWins = TerminalJumpResolver.rowState(
            for: session,
            agents: [
                makeAgent(paneId: "pane-z", agentStatus: "idle", focused: false, agentSession: mappedSession),
                makeAgent(paneId: "pane-a", agentStatus: "idle", focused: false, agentSession: mappedSession),
            ]
        )
        XCTAssertEqual(lexicographicWins.focusTarget, "pane-a")
    }

    func testOpenCodeSessionWithMatchedAgentWithoutPaneIdIsDisabled() {
        let session = makeSession(id: "session-1")
        let agent = makeAgent(
            paneId: "",
            agentSession: HerdrAgentSession(source: "herdr:opencode", agent: "agent-a", kind: "id", value: session.id)
        )

        let state = TerminalJumpResolver.rowState(for: session, agents: [agent])

        assertDisabledSessionState(state, sessionId: session.id)
    }

    private func assertDisabledSessionState(_ state: AgentRowState, sessionId: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state.uiKey, sessionId, file: file, line: line)
        XCTAssertFalse(state.isEnabled, file: file, line: line)
        XCTAssertNil(state.focusTarget, file: file, line: line)
        XCTAssertEqual(state.helpText, "현재 연결된 terminal 없음", file: file, line: line)
    }

    private func makeAgent(
        paneId: String,
        agent: String = "agent-a",
        agentStatus: String = "idle",
        focused: Bool = false,
        tabId: String = "tab-1",
        workspaceId: String = "workspace-1",
        agentSession: HerdrAgentSession? = nil
    ) -> HerdrAgent {
        HerdrAgent(
            agent: agent,
            agentStatus: agentStatus,
            cwd: "/tmp",
            focused: focused,
            paneId: paneId,
            tabId: tabId,
            workspaceId: workspaceId,
            agentSession: agentSession
        )
    }

    private func makeSession(id: String) -> OpencodeSession {
        OpencodeSession(
            id: id,
            title: "Session \(id)",
            projectId: "project-1",
            timeCreated: Date(timeIntervalSince1970: 0),
            timeUpdated: Date(timeIntervalSince1970: 0),
            timeArchived: nil,
            agent: nil,
            model: nil,
            cost: 0,
            tokensInput: 0,
            tokensOutput: 0
        )
    }
}
