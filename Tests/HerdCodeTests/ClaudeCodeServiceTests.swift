import XCTest
@testable import HerdCode

final class ClaudeCodeServiceTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeSessions(_ sessions: [[String: Any]]) -> URL {
        let dir = tmpDir.appendingPathComponent("sessions")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for s in sessions {
            let pid = s["pid"] as! Int
            let data = try! JSONSerialization.data(withJSONObject: s)
            let url = dir.appendingPathComponent("\(pid).json")
            try! data.write(to: url)
        }
        return dir
    }

    private func writeProjectJsonl(pathKey: String, sessionId: String, title: String) -> URL {
        let dir = tmpDir.appendingPathComponent("projects/\(pathKey)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let entry = "{\"type\":\"ai-title\",\"aiTitle\":\"\(title)\",\"sessionId\":\"\(sessionId)\"}\n"
        let url = dir.appendingPathComponent("\(sessionId).jsonl")
        try! entry.data(using: .utf8)!.write(to: url)
        return tmpDir.appendingPathComponent("projects")
    }

    private func makeRawSession(pid: Int, sessionId: String, cwd: String, status: String = "idle") -> [String: Any] {
        [
            "pid": pid,
            "sessionId": sessionId,
            "cwd": cwd,
            "status": status,
            "startedAt": 1_700_000_000_000,
            "updatedAt": 1_700_000_001_000,
            "version": "2.0.0",
            "peerProtocol": 1,
            "kind": "interactive",
            "entrypoint": "cli",
            "procStart": "Mon Jan 01 00:00:00 2024",
            "statusUpdatedAt": 1_700_000_001_000
        ]
    }

    // MARK: - Tests

    func test_fetchSessions_returnsEmptyForMissingDir() async throws {
        let service = ClaudeCodeService(
            sessionsDir: tmpDir.appendingPathComponent("nonexistent").path,
            projectsDir: tmpDir.path
        )
        let sessions = try await service.fetchSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func test_fetchSessions_parsesSessionFields() async throws {
        let cwd = "/tmp/myproject"
        let sessionId = "abc12345-0000-0000-0000-000000000000"
        let myPid = Int(ProcessInfo.processInfo.processIdentifier)
        let sessDir = writeSessions([makeRawSession(pid: myPid, sessionId: sessionId, cwd: cwd)])

        let service = ClaudeCodeService(
            sessionsDir: sessDir.path,
            projectsDir: tmpDir.path
        )
        let sessions = try await service.fetchSessions()
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].sessionId, sessionId)
        XCTAssertEqual(sessions[0].cwd, cwd)
        XCTAssertEqual(sessions[0].status, "idle")
    }

    func test_fetchSessions_extractsAiTitle() async throws {
        let sessionId = "test1234-0000-0000-0000-000000000000"
        let cwd = "/tmp/proj"
        let pathKey = cwd.replacingOccurrences(of: "/", with: "-")
        let projectsDir = writeProjectJsonl(pathKey: pathKey, sessionId: sessionId, title: "테스트 대화 제목")

        let myPid = Int(ProcessInfo.processInfo.processIdentifier)
        let sessDir = writeSessions([makeRawSession(pid: myPid, sessionId: sessionId, cwd: cwd)])

        let service = ClaudeCodeService(
            sessionsDir: sessDir.path,
            projectsDir: projectsDir.path
        )
        let sessions = try await service.fetchSessions()
        XCTAssertEqual(sessions.first?.title, "테스트 대화 제목")
    }

    func test_displayTitle_fallsBackToShortId() {
        let session = ClaudeCodeSession(
            pid: 1, sessionId: "abcdefgh-1234-0000-0000-000000000000",
            cwd: "/tmp", status: "idle",
            startedAt: Date(), updatedAt: Date(),
            version: "2.0.0", title: ""
        )
        XCTAssertEqual(session.displayTitle, "abcdefgh")
    }

    func test_isBusy_forBusyStatus() {
        let busy = ClaudeCodeSession(
            pid: 1, sessionId: "a", cwd: "/", status: "busy",
            startedAt: Date(), updatedAt: Date(), version: "2.0", title: ""
        )
        XCTAssertTrue(busy.isBusy)
        let idle = ClaudeCodeSession(
            pid: 1, sessionId: "a", cwd: "/", status: "idle",
            startedAt: Date(), updatedAt: Date(), version: "2.0", title: ""
        )
        XCTAssertFalse(idle.isBusy)
    }

    func test_fetchSessions_skipsDeadProcesses() async throws {
        // PID 99999 almost certainly does not exist
        let sessDir = writeSessions([makeRawSession(pid: 99999, sessionId: "dead-sess-0000-0000-0000-000000000000", cwd: "/tmp")])
        let service = ClaudeCodeService(sessionsDir: sessDir.path, projectsDir: tmpDir.path)
        let sessions = try await service.fetchSessions()
        XCTAssertTrue(sessions.isEmpty)
    }
}
