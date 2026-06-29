import Foundation
import XCTest
@testable import HerdCode

final class HerdCodeJumpExecutionTests: XCTestCase {
    func testSuccessfulFakeExecutorDoesNotLogJumpError() async throws {
        let logger = TestJumpLogger()
        let service = HerdrService(
            jumpExecutor: FakeJumpExecutor { paneId in
                XCTAssertEqual(paneId, "pane-123")
            },
            jumpLogger: logger
        )

        try await service.focusPane("pane-123")

        XCTAssertFalse(logger.lines.contains { $0.contains("[HerdCodeJumpError]") })
    }

    func testFailingFakeExecutorLogsJumpErrorPrefix() async {
        let logger = TestJumpLogger()
        let service = HerdrService(
            jumpExecutor: FakeJumpExecutor { _ in
                throw HerdrError.jumpFailed(paneId: "pane-123", message: "boom", status: 2)
            },
            jumpLogger: logger
        )

        do {
            try await service.focusPane("pane-123")
            XCTFail("Expected jump failure")
        } catch {
            XCTAssertTrue(logger.lines.contains { $0.contains("[HerdCodeJumpError]") })
        }
    }

    func testFailingFakeExecutorThrowsTypedError() async {
        let service = HerdrService(
            jumpExecutor: FakeJumpExecutor { _ in
                throw FakeFailure(message: "not focused")
            },
            jumpLogger: TestJumpLogger()
        )

        do {
            try await service.focusPane("pane-404")
            XCTFail("Expected jump failure")
        } catch let error as HerdrError {
            switch error {
            case .jumpFailed(let paneId, let message, let status):
                XCTAssertEqual(paneId, "pane-404")
                XCTAssertEqual(message, "not focused")
                XCTAssertNil(status)
            default:
                XCTFail("Expected jumpFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected HerdrError.jumpFailed, got \(error)")
        }
    }
}
