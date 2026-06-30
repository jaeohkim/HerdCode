import XCTest
@testable import HerdCode

@MainActor
final class HerdrServiceRemoteTransportTests: XCTestCase {

    // MARK: - SSH command composition uses CommandRunner injection, not --remote

    func testSSHCommandRunnerDoesNotUseRemoteFlag() async throws {
        var capturedArgs: [String] = []

        let service = HerdrService(
            herdrPath: "/opt/homebrew/bin/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, args in
                capturedArgs = args
                return "[]"
            }
        )

        _ = try await service.fetchSessions()

        XCTAssertFalse(capturedArgs.contains("--remote"), "CommandRunner must not inject --remote flag")
        XCTAssertEqual(capturedArgs, ["session", "list", "--json"])
    }

    // MARK: - --json flag for session list

    func testFetchSessionsUsesJsonFlag() async throws {
        var capturedArgs: [String] = []

        let service = HerdrService(
            herdrPath: "/fake/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, args in
                capturedArgs = args
                return """
                [{"name":"s1","status":"running","directory":"/tmp","socket":"/tmp/s1.sock"}]
                """
            }
        )

        let sessions = try await service.fetchSessions()

        XCTAssertEqual(capturedArgs.last, "--json")
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.name, "s1")
    }

    // MARK: - Remote path discovery order

    func testSSHCommandRunnerUsesConfigPathWhenProvided() {
        let runner = HerdrService.sshCommandRunner(
            remote: "host1",
            session: "sess1",
            herdrPath: "/custom/bin/herdr"
        )

        XCTAssertNotNil(runner, "sshCommandRunner should return a valid runner with custom path")
    }

    func testSSHCommandRunnerFallsBackToHerdrWhenNoPath() {
        let runner = HerdrService.sshCommandRunner(
            remote: "host1",
            session: "sess1",
            herdrPath: nil
        )

        XCTAssertNotNil(runner, "sshCommandRunner should return a valid runner without custom path")
    }

    // MARK: - StatusMonitor uses remoteServiceFactory (not --remote)

    func testStatusMonitorUsesFactoryForRemoteTargets() async throws {
        var factoryCalled = false
        let remoteTarget = HerdrTarget(label: "r1", isLocal: false, remote: "r1", session: "r1", herdrPath: nil)

        let localService = HerdrService(
            herdrPath: "/fake/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, args in
                if args == ["session", "list", "--json"] { return "[]" }
                if args == ["agent", "list"] {
                    return """
                    {"id":"1","result":{"agents":[],"type":"success"}}
                    """
                }
                if args == ["workspace", "list"] {
                    return """
                    {"id":"1","result":{"workspaces":[],"type":"success"}}
                    """
                }
                return "[]"
            }
        )

        let monitor = StatusMonitor(
            pollInterval: 999,
            herdrService: localService,
            targets: [remoteTarget],
            opencodeService: FakeOpencodeServiceForTransport(sessions: [], todos: []),
            remoteServiceFactory: { target in
                factoryCalled = true
                XCTAssertEqual(target.label, "r1")
                return HerdrService(
                    herdrPath: "/fake/herdr",
                    appActivator: FakeAppActivator {},
                    jumpExecutor: FakeJumpExecutor { _ in },
                    jumpLogger: TestJumpLogger(),
                    commandRunner: { _, args in
                        if args == ["session", "list", "--json"] { return "[]" }
                        if args == ["agent", "list"] {
                            return """
                            {"id":"1","result":{"agents":[],"type":"success"}}
                            """
                        }
                        return "[]"
                    }
                )
            }
        )

        await monitor.refresh()

        XCTAssertTrue(factoryCalled, "StatusMonitor must use remoteServiceFactory for remote targets")
    }

    // MARK: - Remote agents get sanitized paneId and focused

    func testRemoteAgentsSanitized() async throws {
        let remoteTarget = HerdrTarget(label: "remote-x", isLocal: false, remote: "remote-x", session: "remote-x", herdrPath: nil)

        let localService = HerdrService(
            herdrPath: "/fake/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, args in
                if args == ["session", "list", "--json"] { return "[]" }
                if args == ["agent", "list"] {
                    return """
                    {"id":"1","result":{"agents":[],"type":"success"}}
                    """
                }
                if args == ["workspace", "list"] {
                    return """
                    {"id":"1","result":{"workspaces":[],"type":"success"}}
                    """
                }
                return "[]"
            }
        )

        let remoteService = HerdrService(
            herdrPath: "/fake/herdr",
            appActivator: FakeAppActivator {},
            jumpExecutor: FakeJumpExecutor { _ in },
            jumpLogger: TestJumpLogger(),
            commandRunner: { _, args in
                if args == ["session", "list", "--json"] { return "[]" }
                if args == ["agent", "list"] {
                    return """
                    {
                      "id": "1",
                      "result": {
                        "agents": [{
                          "agent": "remote-agent",
                          "agent_status": "working",
                          "cwd": "/tmp",
                          "focused": true,
                          "pane_id": "pane-remote-1",
                          "tab_id": "tab-1",
                          "workspace_id": "ws-1",
                          "agent_session": null
                        }],
                        "type": "success"
                      }
                    }
                    """
                }
                return "[]"
            }
        )

        let monitor = StatusMonitor(
            pollInterval: 999,
            herdrService: localService,
            targets: [remoteTarget],
            opencodeService: FakeOpencodeServiceForTransport(sessions: [], todos: []),
            remoteServiceFactory: { _ in remoteService }
        )

        await monitor.refresh()

        let remoteAgents = monitor.state.herdrAgents.filter { $0.targetLabel == "remote-x" }
        XCTAssertEqual(remoteAgents.count, 1)
        XCTAssertEqual(remoteAgents[0].paneId, "", "Remote agent paneId must be empty")
        XCTAssertFalse(remoteAgents[0].focused, "Remote agent must not be focused")
    }
}

private struct FakeOpencodeServiceForTransport: OpencodeProviding {
    let sessions: [OpencodeSession]
    let todos: [OpencodeTodo]

    func fetchRecentSessions(limit: Int) async throws -> [OpencodeSession] {
        Array(sessions.prefix(limit))
    }

    func fetchTodos(for sessionIds: [String]) async throws -> [OpencodeTodo] {
        todos.filter { sessionIds.contains($0.sessionId) }
    }
}
