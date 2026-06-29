import Foundation
import SQLite3

/// opencode SQLite DB를 직접 읽어 세션/TODO/비용 정보를 조회합니다.
actor OpencodeService {

    private let dbPath: String
    private var db: OpaquePointer?

    init(dbPath: String = "\(NSHomeDirectory())/.local/share/opencode/opencode.db") {
        self.dbPath = dbPath
    }

    // MARK: - Public API

    func fetchRecentSessions(limit: Int = 20) async throws -> [OpencodeSession] {
        try openIfNeeded()
        return try querySessions(limit: limit)
    }

    func fetchTodos(for sessionIds: [String]) async throws -> [OpencodeTodo] {
        guard !sessionIds.isEmpty else { return [] }
        try openIfNeeded()
        return try queryTodos(sessionIds: sessionIds)
    }

    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Private: DB Open

    private func openIfNeeded() throws {
        guard db == nil else { return }

        // WAL 모드 DB를 읽기 전용으로 열기
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)
        guard result == SQLITE_OK else {
            throw OpencodeError.cannotOpenDB(dbPath, result)
        }
    }

    // MARK: - Private: Queries

    private func querySessions(limit: Int) throws -> [OpencodeSession] {
        let sql = """
            SELECT
                id, project_id, title, time_created, time_updated,
                time_archived, agent, model, cost,
                tokens_input, tokens_output
            FROM session
            WHERE time_archived IS NULL
            ORDER BY time_updated DESC
            LIMIT ?;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw OpencodeError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        var sessions: [OpencodeSession] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let session = OpencodeSession(
                id:           string(stmt, col: 0),
                title:        string(stmt, col: 2),
                projectId:    string(stmt, col: 1),
                timeCreated:  date(stmt, col: 3),
                timeUpdated:  date(stmt, col: 4),
                timeArchived: optionalDate(stmt, col: 5),
                agent:        optionalString(stmt, col: 6),
                model:        optionalString(stmt, col: 7),
                cost:         sqlite3_column_double(stmt, 8),
                tokensInput:  Int(sqlite3_column_int64(stmt, 9)),
                tokensOutput: Int(sqlite3_column_int64(stmt, 10))
            )
            sessions.append(session)
        }
        return sessions
    }

    private func queryTodos(sessionIds: [String]) throws -> [OpencodeTodo] {
        let placeholders = sessionIds.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT session_id, content, status, priority, position
            FROM todo
            WHERE session_id IN (\(placeholders))
              AND status IN ('pending', 'in_progress')
            ORDER BY session_id, position;
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw OpencodeError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        for (i, sid) in sessionIds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (sid as NSString).utf8String, -1, nil)
        }

        var todos: [OpencodeTodo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let todo = OpencodeTodo(
                sessionId: string(stmt, col: 0),
                content:   string(stmt, col: 1),
                status:    string(stmt, col: 2),
                priority:  string(stmt, col: 3),
                position:  Int(sqlite3_column_int(stmt, 4))
            )
            todos.append(todo)
        }
        return todos
    }

    // MARK: - SQLite Column Helpers

    private func string(_ stmt: OpaquePointer?, col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    private func optionalString(_ stmt: OpaquePointer?, col: Int32) -> String? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: ptr)
    }

    /// opencode DB는 Unix timestamp(ms) 정수로 저장
    private func date(_ stmt: OpaquePointer?, col: Int32) -> Date {
        let ms = sqlite3_column_int64(stmt, col)
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }

    private func optionalDate(_ stmt: OpaquePointer?, col: Int32) -> Date? {
        guard sqlite3_column_type(stmt, col) != SQLITE_NULL else { return nil }
        let ms = sqlite3_column_int64(stmt, col)
        return Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }
}

// MARK: - Errors

enum OpencodeError: LocalizedError {
    case cannotOpenDB(String, Int32)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenDB(let path, let code):
            return "opencode DB를 열 수 없습니다 (\(path)): SQLite error \(code)"
        case .queryFailed(let msg):
            return "쿼리 실패: \(msg)"
        }
    }
}
