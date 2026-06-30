import XCTest
@testable import HerdCode

final class AppStateTodoGroupingTests: XCTestCase {

    func testMatchingSessionReturnsOnlyItsOwnTodos() {
        let session = makeSession(id: "ses-1")
        let state = makeState(todos: [
            makeTodo(sessionId: "ses-1", position: 0),
            makeTodo(sessionId: "ses-1", position: 1),
            makeTodo(sessionId: "ses-2", position: 0),
        ])

        let result = state.todosFor(session)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.sessionId == "ses-1" })
    }

    func testOriginalOrderIsPreserved() {
        let session = makeSession(id: "ses-1")
        let state = makeState(todos: [
            makeTodo(sessionId: "ses-1", position: 0, status: "pending"),
            makeTodo(sessionId: "ses-1", position: 1, status: "in_progress"),
            makeTodo(sessionId: "ses-1", position: 2, status: "completed"),
        ])

        let result = state.todosFor(session)

        XCTAssertEqual(result.map { $0.position }, [0, 1, 2])
    }

    func testSessionWithNoTodosReturnsEmpty() {
        let session = makeSession(id: "ses-empty")
        let state = makeState(todos: [
            makeTodo(sessionId: "ses-1", position: 0),
        ])

        let result = state.todosFor(session)

        XCTAssertTrue(result.isEmpty)
    }

    func testCrossSessionIsolationExcludesOrphanTodos() {
        let session = makeSession(id: "ses-A")
        let state = makeState(todos: [
            makeTodo(sessionId: "ses-A", position: 0),
            makeTodo(sessionId: "ses-B", position: 0),
            makeTodo(sessionId: "ses-C", position: 0),
        ])

        let result = state.todosFor(session)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sessionId, "ses-A")
    }

    private func makeSession(id: String) -> OpencodeSession {
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

    private func makeTodo(sessionId: String, position: Int, status: String = "pending") -> OpencodeTodo {
        OpencodeTodo(
            sessionId: sessionId,
            content: "Todo \(position)",
            status: status,
            priority: "medium",
            position: position
        )
    }

    private func makeState(todos: [OpencodeTodo]) -> AppState {
        var state = AppState()
        state.opencodeTodos = todos
        return state
    }
}
