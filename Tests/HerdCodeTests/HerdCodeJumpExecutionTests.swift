import Foundation
import XCTest
@testable import HerdCode

final class HerdCodeJumpExecutionTests: XCTestCase {
    func testSuccessfulFakeExecutorDoesNotLogJumpError() async throws {
        let logger = TestJumpLogger()
        let service = HerdrService(
            appActivator: FakeAppActivator {},
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
            appActivator: FakeAppActivator {},
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
            appActivator: FakeAppActivator {},
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

    func testActivatorRunsBeforeFocusOnSuccess() async throws {
        let events = LockedEvents()
        let service = HerdrService(
            appActivator: FakeAppActivator {
                events.append("activate")
            },
            jumpExecutor: FakeJumpExecutor { _ in
                events.append("focus")
            },
            jumpLogger: TestJumpLogger()
        )

        try await service.focusPane("pane-ordered")

        XCTAssertEqual(events.snapshot(), ["activate", "focus"])
    }

    func testActivationFailureLogsJumpErrorAndThrows() async {
        let logger = TestJumpLogger()
        let focusCalled = LockedFlag()
        let service = HerdrService(
            appActivator: FakeAppActivator {
                throw HerdrError.activationFailed(bundleId: GhosttyNSWorkspaceActivator.bundleId, reason: "Application not found")
            },
            jumpExecutor: FakeJumpExecutor { _ in
                focusCalled.setTrue()
            },
            jumpLogger: logger
        )

        do {
            try await service.focusPane("pane-activation-failure")
            XCTFail("Expected activation failure")
        } catch let error as HerdrError {
            switch error {
            case .activationFailed(let bundleId, let reason):
                XCTAssertEqual(bundleId, GhosttyNSWorkspaceActivator.bundleId)
                XCTAssertEqual(reason, "Application not found")
            default:
                XCTFail("Expected activationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected HerdrError.activationFailed, got \(error)")
        }

        XCTAssertTrue(logger.lines.contains { $0.contains("[HerdCodeJumpError]") })
        XCTAssertFalse(focusCalled.value)
    }
}
