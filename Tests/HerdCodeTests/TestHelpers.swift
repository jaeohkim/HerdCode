import Foundation
@testable import HerdCode

struct FakeJumpExecutor: JumpExecuting {
    let handler: @Sendable (String) async throws -> Void

    func focusPane(_ paneId: String) async throws {
        try await handler(paneId)
    }
}

struct FakeAppActivator: AppActivating {
    let handler: @Sendable () async throws -> Void

    func activate() async throws {
        try await handler()
    }
}

struct FakeFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

final class TestJumpLogger: JumpLogging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var lines: [String] = []

    func log(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(message)
    }
}

final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value)
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func setTrue() {
        lock.lock()
        defer { lock.unlock() }
        storage = true
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct FakeClaudeCodeService: ClaudeCodeProviding, @unchecked Sendable {
    var sessions: [ClaudeCodeSession]
    var error: Error?

    func fetchSessions() async throws -> [ClaudeCodeSession] {
        if let error { throw error }
        return sessions
    }
}
