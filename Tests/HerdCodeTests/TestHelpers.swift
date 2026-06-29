import Foundation
@testable import HerdCode

struct FakeJumpExecutor: JumpExecuting {
    let handler: @Sendable (String) async throws -> Void

    func focusPane(_ paneId: String) async throws {
        try await handler(paneId)
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
