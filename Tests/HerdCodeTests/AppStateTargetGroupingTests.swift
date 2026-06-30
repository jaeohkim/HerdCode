import Foundation
import XCTest
@testable import HerdCode

final class AppStateTargetGroupingTests: XCTestCase {

    func testHerdrModelsNamespaceIDsByTargetLabel() {
        let localAgent = makeAgent(targetLabel: "local", paneId: "pane-1")
        let remoteAgent = makeAgent(targetLabel: "server", paneId: "pane-1")
        let localSession = makeHerdrSession(targetLabel: "local", name: "alpha")
        let remoteSession = makeHerdrSession(targetLabel: "server", name: "alpha")

        XCTAssertEqual(localAgent.id, "local:pane-1")
        XCTAssertEqual(remoteAgent.id, "server:pane-1")
        XCTAssertNotEqual(localAgent.id, remoteAgent.id)

        XCTAssertEqual(localSession.id, "local:alpha")
        XCTAssertEqual(remoteSession.id, "server:alpha")
        XCTAssertNotEqual(localSession.id, remoteSession.id)
    }

    func testRemoteOpencodeSessionsStaySeparateFromLocalSessions() {
        var state = AppState()
        state.opencodeSessions = [makeOpencodeSession(id: "ses-1")]
        state.remoteOpencodeSessions = [
            RemoteOpencodeSession(targetLabel: "server", sessionId: "ses-1", isRunning: true)
        ]

        XCTAssertEqual(state.opencodeSessions.count, 1)
        XCTAssertEqual(state.remoteOpencodeSessions.count, 1)
        XCTAssertEqual(state.opencodeSessions[0].id, "ses-1")
        XCTAssertEqual(state.remoteOpencodeSessions[0].id, "server:ses-1")
    }

    func testRemoteTargetConfigReturnsEmptyArrayWhenFileIsAbsent() {
        let missingPath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("remotes.json")
            .path

        let result = RemoteTargetConfig(configPath: missingPath).loadTargets()

        XCTAssertEqual(result, [])
    }

    private func makeAgent(targetLabel: String, paneId: String) -> HerdrAgent {
        HerdrAgent(
            agent: "agent-1",
            agentStatus: "working",
            cwd: "/tmp",
            focused: false,
            paneId: paneId,
            tabId: "tab-1",
            workspaceId: "workspace-1",
            agentSession: nil,
            targetLabel: targetLabel
        )
    }

    private func makeHerdrSession(targetLabel: String, name: String) -> HerdrSession {
        HerdrSession(
            name: name,
            status: "running",
            directory: "/tmp",
            socket: "/tmp/socket",
            targetLabel: targetLabel
        )
    }

    private func makeOpencodeSession(id: String) -> OpencodeSession {
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
