import XCTest
@testable import HerdCode

private struct FakeOpencodeService: OpencodeProviding {
    let sessions: [OpencodeSession]
    let todos: [OpencodeTodo]

    func fetchRecentSessions(limit: Int) async throws -> [OpencodeSession] {
        Array(sessions.prefix(limit))
    }

    func fetchTodos(for sessionIds: [String]) async throws -> [OpencodeTodo] {
        todos.filter { sessionIds.contains($0.sessionId) }
    }
}

@MainActor
final class StatusMonitorRemoteTests: XCTestCase {
    func testRemoteFailureDoesNotEraseLocalState() async throws {
        let localService = makeService(targetLabel: "local")
        let remoteTarget = HerdrTarget(label: "remote-a", isLocal: false, remote: "remote-a", session: "remote-a", herdrPath: nil)
        let remoteService = makeFailingService(message: "remote offline")
        let opencodeService = FakeOpencodeService(sessions: [], todos: [])

        let monitor = StatusMonitor(
            pollInterval: 999,
            herdrService: localService,
            targets: [remoteTarget],
            opencodeService: opencodeService,
            remoteServiceFactory: { _ in remoteService }
        )

        await monitor.refresh()

        XCTAssertEqual(monitor.state.herdrSessions.map(\.targetLabel), ["local"])
        XCTAssertEqual(monitor.state.herdrSessions.map(\.name), ["local-main"])
        XCTAssertEqual(monitor.state.herdrAgents.map(\.targetLabel), ["local"])
        XCTAssertEqual(monitor.state.herdrAgents.map(\.paneId), ["pane-local-1"])
        XCTAssertTrue(monitor.state.remoteOpencodeSessions.isEmpty)
        XCTAssertTrue(monitor.lastError?.contains("remote-a herdr sessions: remote offline") == true)
    }

    func testRefreshMergesLocalFirstThenRemoteAgents() async throws {
        let localService = makeService(targetLabel: "local")
        let remoteTarget = HerdrTarget(label: "remote-b", isLocal: false, remote: "remote-b", session: "remote-b", herdrPath: nil)
        let remoteService = makeService(targetLabel: remoteTarget.label)
        let opencodeService = FakeOpencodeService(sessions: [], todos: [])

        let monitor = StatusMonitor(
            pollInterval: 999,
            herdrService: localService,
            targets: [remoteTarget],
            opencodeService: opencodeService,
            remoteServiceFactory: { _ in remoteService }
        )

        await monitor.refresh()

        XCTAssertEqual(monitor.state.herdrAgents.map(\.targetLabel), ["local", "remote-b"])
        XCTAssertEqual(monitor.state.herdrAgents.map(\.agent), ["local-agent", "remote-b-agent"])
        XCTAssertEqual(monitor.state.herdrSessions.map(\.targetLabel), ["local", "remote-b"])
        XCTAssertEqual(monitor.state.herdrSessions.map(\.name), ["local-main", "remote-b-main"])
        XCTAssertEqual(monitor.state.herdrAgents[0].paneId, "pane-local-1")
        XCTAssertEqual(monitor.state.herdrAgents[1].paneId, "")
        XCTAssertEqual(monitor.state.remoteOpencodeSessions.map(\.targetLabel), ["remote-b"])
        XCTAssertNil(monitor.lastError)
    }

    private func makeService(
        targetLabel: String
    ) -> HerdrService {
        HerdrService(
            herdrPath: "/fake/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, args in
                if args == ["session", "list", "--json"] {
                    return """
                    [{"name": "\(targetLabel)-main", "status": "running", "directory": "/tmp", "socket": "/tmp/\(targetLabel).sock"}]
                    """
                }

                if args == ["agent", "list"] {
                    return """
                    {
                      \"id\": \"1\",
                      \"result\": {
                        \"agents\": [
                          {
                            \"agent\": \"\(targetLabel)-agent\",
                            \"agent_status\": \"working\",
                            \"cwd\": \"/tmp\",
                            \"focused\": true,
                            \"pane_id\": \"pane-\(targetLabel)-1\",
                            \"tab_id\": \"tab-1\",
                            \"workspace_id\": \"ws-1\",
                            \"agent_session\": null
                          }
                        ],
                        \"type\": \"success\"
                      }
                    }
                    """
                }

                if args == ["workspace", "list"] {
                    return """
                    {
                      \"id\": \"1\",
                      \"result\": {
                        \"workspaces\": [
                          {
                            \"workspace_id\": \"ws-1\",
                            \"label\": \"\(targetLabel)-workspace\",
                            \"agent_status\": \"working\",
                            \"focused\": true,
                            \"tab_count\": 1,
                            \"pane_count\": 1
                          }
                        ],
                        \"type\": \"success\"
                      }
                    }
                    """
                }

                throw FakeFailure(message: "unexpected args: \(args.joined(separator: " "))")
            }
        )
    }

    private func makeFailingService(message: String) -> HerdrService {
        HerdrService(
            herdrPath: "/fake/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, _ in
                throw FakeFailure(message: message)
            }
        )
    }

}
