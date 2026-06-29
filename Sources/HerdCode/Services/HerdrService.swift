import Foundation

protocol JumpExecuting: Sendable {
    func focusPane(_ paneId: String) async throws
}

struct HerdrProcessJumpExecutor: JumpExecuting {
    let herdrPath: String

    func focusPane(_ paneId: String) async throws {
        guard FileManager.default.fileExists(atPath: herdrPath) else {
            throw HerdrError.herdrNotFound(herdrPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: herdrPath)
        process.arguments = ["agent", "focus", paneId]

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = stderr.isEmpty ? (stdout.isEmpty ? "exit status \(process.terminationStatus)" : stdout) : stderr
            throw HerdrError.jumpFailed(paneId: paneId, message: message, status: process.terminationStatus)
        }
    }
}

/// herdr CLI를 통해 세션/에이전트/워크스페이스 상태를 조회합니다.
actor HerdrService {

    private let herdrPath: String
    private let jumpExecutor: any JumpExecuting
    private let jumpLogger: any JumpLogging

    init(
        herdrPath: String = "/opt/homebrew/bin/herdr",
        jumpExecutor: (any JumpExecuting)? = nil,
        jumpLogger: any JumpLogging = JumpLogger()
    ) {
        self.herdrPath = herdrPath
        self.jumpExecutor = jumpExecutor ?? HerdrProcessJumpExecutor(herdrPath: herdrPath)
        self.jumpLogger = jumpLogger
    }

    // MARK: - Public API

    func fetchSessions() async throws -> [HerdrSession] {
        // herdr session list 는 텍스트 테이블 출력 → 직접 파싱
        let output = try await run(args: ["session", "list"])
        return parseSessionList(output)
    }

    func fetchAgents() async throws -> [HerdrAgent] {
        let output = try await run(args: ["agent", "list"])
        guard let data = output.data(using: .utf8) else { return [] }
        let response = try JSONDecoder().decode(HerdrAgentListResponse.self, from: data)
        return response.result.agents
    }

    func fetchWorkspaces() async throws -> [HerdrWorkspace] {
        let output = try await run(args: ["workspace", "list"])
        guard let data = output.data(using: .utf8) else { return [] }
        let response = try JSONDecoder().decode(HerdrWorkspaceListResponse.self, from: data)
        return response.result.workspaces
    }

    func focusPane(_ paneId: String) async throws {
        do {
            try await jumpExecutor.focusPane(paneId)
        } catch let error as HerdrError {
            let jumpError = error.jumpError(for: paneId)
            jumpLogger.log(jumpError.jumpLogMessage)
            throw jumpError
        } catch {
            let jumpError = HerdrError.jumpFailed(paneId: paneId, message: error.localizedDescription, status: nil)
            jumpLogger.log(jumpError.jumpLogMessage)
            throw jumpError
        }
    }

    // MARK: - Private Helpers

    private func run(args: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: herdrPath)
        process.arguments = args

        // herdr가 현재 실행 중인 세션 소켓을 자동 감지하도록 환경 상속
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()  // stderr 무시

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else {
            throw HerdrError.invalidOutput
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseSessionList(_ text: String) -> [HerdrSession] {
        let lines = text.components(separatedBy: .newlines)
        var sessions: [HerdrSession] = []

        for line in lines {
            // 헤더 행 스킵
            if line.hasPrefix("name") || line.isEmpty { continue }

            // 공백 2개 이상으로 컬럼 구분
            let cols = line.components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard cols.count >= 4 else { continue }

            let session = HerdrSession(
                name: cols[0],
                status: cols[1],
                directory: cols[2],
                socket: cols[3]
            )
            sessions.append(session)
        }
        return sessions
    }
}

// MARK: - Errors

enum HerdrError: LocalizedError {
    case invalidOutput
    case herdrNotFound(String)
    case jumpFailed(paneId: String, message: String, status: Int32?)

    var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "herdr 명령 출력을 파싱할 수 없습니다."
        case .herdrNotFound(let path):
            return "herdr를 찾을 수 없습니다: \(path)"
        case .jumpFailed(let paneId, let message, let status):
            if let status {
                return "pane \(paneId) 포커스 이동 실패 (exit=\(status)): \(message)"
            }
            return "pane \(paneId) 포커스 이동 실패: \(message)"
        }
    }

    func jumpError(for paneId: String) -> HerdrError {
        switch self {
        case .jumpFailed:
            return self
        default:
            return .jumpFailed(paneId: paneId, message: localizedDescription, status: nil)
        }
    }

    var jumpLogMessage: String {
        switch self {
        case .jumpFailed(let paneId, let message, _):
            return "[HerdCodeJumpError] focus paneId=\(paneId) failed: \(message)"
        default:
            return "[HerdCodeJumpError] \(localizedDescription)"
        }
    }
}
