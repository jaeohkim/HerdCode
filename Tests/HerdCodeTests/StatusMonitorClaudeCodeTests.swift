import XCTest
@testable import HerdCode

private final class CountingClaudeCodeService: ClaudeCodeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    let firstSessions: [ClaudeCodeSession]
    let subsequentError: Error?

    init(firstSessions: [ClaudeCodeSession], subsequentError: Error?) {
        self.firstSessions = firstSessions
        self.subsequentError = subsequentError
    }

    func fetchSessions() async throws -> [ClaudeCodeSession] {
        lock.lock()
        let count = callCount
        callCount += 1
        lock.unlock()
        if count == 0 {
            return firstSessions
        }
        if let error = subsequentError { throw error }
        return firstSessions
    }
}

@MainActor
final class StatusMonitorClaudeCodeTests: XCTestCase {
    func test_claudeCodeSessions_appearsInState() async throws {
        let session = ClaudeCodeSession(
            pid: 1234,
            sessionId: "abcdef1234567890",
            cwd: "/tmp",
            status: "busy",
            startedAt: Date(),
            updatedAt: Date(),
            version: "1.0.0",
            title: "테스트 세션"
        )
        let claudeCodeService = FakeClaudeCodeService(sessions: [session])

        let monitor = StatusMonitor(
            pollInterval: 999,
            claudeCodeService: claudeCodeService
        )

        await monitor.refresh()

        XCTAssertEqual(monitor.state.claudeCodeSessions.count, 1)
        XCTAssertEqual(monitor.state.claudeCodeSessions[0].title, "테스트 세션")
        XCTAssertEqual(monitor.state.claudeCodeSessions[0].status, "busy")
    }

    func test_claudeCodeError_doesNotClearPreviousState() async throws {
        let session = ClaudeCodeSession(
            pid: 5678,
            sessionId: "fedcba9876543210",
            cwd: "/tmp",
            status: "idle",
            startedAt: Date(),
            updatedAt: Date(),
            version: "1.0.0",
            title: "이전 세션"
        )
        let service = CountingClaudeCodeService(
            firstSessions: [session],
            subsequentError: FakeFailure(message: "claudeCode fetch failed")
        )

        let monitor = StatusMonitor(
            pollInterval: 999,
            claudeCodeService: service
        )

        await monitor.refresh()
        XCTAssertEqual(monitor.state.claudeCodeSessions.count, 1)

        await monitor.refresh()

        XCTAssertEqual(monitor.state.claudeCodeSessions.count, 1)
        XCTAssertTrue(monitor.lastError?.contains("claudeCode") == true)
    }

    func test_busyClaudeCodeCount_reflectsState() async throws {
        let busySession = ClaudeCodeSession(
            pid: 1111,
            sessionId: "aaaa000000000001",
            cwd: "/tmp/busy",
            status: "busy",
            startedAt: Date(),
            updatedAt: Date(),
            version: "1.0.0",
            title: "바쁜 세션"
        )
        let idleSession = ClaudeCodeSession(
            pid: 2222,
            sessionId: "bbbb000000000002",
            cwd: "/tmp/idle",
            status: "idle",
            startedAt: Date(),
            updatedAt: Date(),
            version: "1.0.0",
            title: "한가한 세션"
        )
        let claudeCodeService = FakeClaudeCodeService(sessions: [busySession, idleSession])

        let monitor = StatusMonitor(
            pollInterval: 999,
            claudeCodeService: claudeCodeService
        )

        await monitor.refresh()

        XCTAssertEqual(monitor.state.busyClaudeCodeCount, 1)
    }
}
