import Foundation

protocol ClaudeCodeProviding: Sendable {
    func fetchSessions() async throws -> [ClaudeCodeSession]
}

actor ClaudeCodeService: ClaudeCodeProviding {

    private let sessionsDir: String
    private let projectsDir: String

    init(
        sessionsDir: String = "\(NSHomeDirectory())/.claude/sessions",
        projectsDir: String = "\(NSHomeDirectory())/.claude/projects"
    ) {
        self.sessionsDir = sessionsDir
        self.projectsDir = projectsDir
    }

    func fetchSessions() async throws -> [ClaudeCodeSession] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir) else { return [] }

        let files = try fm.contentsOfDirectory(atPath: sessionsDir)
        var sessions: [ClaudeCodeSession] = []

        for file in files where file.hasSuffix(".json") {
            let path = "\(sessionsDir)/\(file)"
            guard let session = parseSessionFile(at: path) else { continue }
            guard isProcessAlive(pid: session.pid) else { continue }
            sessions.append(session)
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Private

    private func parseSessionFile(at path: String) -> ClaudeCodeSession? {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = try? JSONDecoder().decode(RawSession.self, from: data)
        else { return nil }

        let title = extractTitle(sessionId: raw.sessionId, cwd: raw.cwd)
        return ClaudeCodeSession(
            pid:       raw.pid,
            sessionId: raw.sessionId,
            cwd:       raw.cwd,
            status:    raw.status,
            startedAt: Date(timeIntervalSince1970: Double(raw.startedAt) / 1000),
            updatedAt: Date(timeIntervalSince1970: Double(raw.updatedAt) / 1000),
            version:   raw.version,
            title:     title
        )
    }

    private func extractTitle(sessionId: String, cwd: String) -> String {
        let pathKey = cwd.replacingOccurrences(of: "/", with: "-")
        let jsonlPath = "\(projectsDir)/\(pathKey)/\(sessionId).jsonl"

        guard let handle = FileHandle(forReadingAtPath: jsonlPath) else { return "" }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize: UInt64 = min(8192, fileSize)
        handle.seek(toFileOffset: fileSize - readSize)
        guard let chunk = try? handle.readToEnd(),
              let text = String(data: chunk, encoding: .utf8)
        else { return "" }

        let lines = text.components(separatedBy: "\n").reversed()
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(AiTitleEntry.self, from: data),
                  entry.type == "ai-title"
            else { continue }
            return entry.aiTitle
        }
        return ""
    }

    private func isProcessAlive(pid: Int) -> Bool {
        kill(pid_t(pid), 0) == 0
    }

    // MARK: - Decodable helpers

    private struct RawSession: Decodable {
        let pid: Int
        let sessionId: String
        let cwd: String
        let status: String
        let startedAt: Int64
        let updatedAt: Int64
        let version: String
    }

    private struct AiTitleEntry: Decodable {
        let type: String
        let aiTitle: String
    }
}
