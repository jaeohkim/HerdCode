import AppKit
import XCTest
@testable import HerdCode

final class HerdCodeGhosttyLiveSmokeTests: XCTestCase {

    func testGhosttyActivationPrecedesFocus_live() async throws {
        guard ProcessInfo.processInfo.environment["HERDCODE_LIVE_GHOSTTY_SMOKE"] == "1" else {
            throw XCTSkip("Skipped: set HERDCODE_LIVE_GHOSTTY_SMOKE=1 to run live Ghostty smoke")
        }

        let ghosttyBundleId = GhosttyNSWorkspaceActivator.bundleId
        let ghosttyURL = await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: ghosttyBundleId)
        }
        XCTAssertNotNil(
            ghosttyURL,
            "FAIL: Ghostty not found at bundle id '\(ghosttyBundleId)' — wrong id or not installed"
        )
        guard ghosttyURL != nil else { return }

        let herdrPath = "/opt/homebrew/bin/herdr"
        let agentListOutput = try runHerdrAgentList(herdrPath: herdrPath)
        guard let paneId = extractFirstPaneId(from: agentListOutput), !paneId.isEmpty else {
            throw XCTSkip("Skipped: no live herdr agents found — start a herdr session first")
        }

        try await activateFinder()
        try await Task.sleep(nanoseconds: 500_000_000)

        let events = LockedEvents()
        let recordingActivator = RecordingActivatorWrapper(
            inner: GhosttyNSWorkspaceActivator(),
            events: events,
            label: "activate"
        )
        let recordingExecutor = RecordingExecutorWrapper(
            herdrPath: herdrPath,
            events: events,
            label: "focus"
        )
        let logger = TestJumpLogger()

        let service = HerdrService(
            herdrPath: herdrPath,
            appActivator: recordingActivator,
            jumpExecutor: recordingExecutor,
            jumpLogger: logger
        )
        let monitor = await MainActor.run {
            StatusMonitor(herdrService: service, pollInterval: 999)
        }

        let agent = HerdrAgent(
            agent: "smoke",
            agentStatus: "working",
            cwd: "/tmp",
            focused: true,
            paneId: paneId,
            tabId: "tab-smoke",
            workspaceId: "ws-smoke",
            agentSession: nil
        )

        await monitor.jumpToAgent(agent)

        let eventList = events.snapshot()
        XCTAssertTrue(
            eventList.first?.hasPrefix("activate") == true,
            "Expected 'activate' to be first event, got: \(eventList)"
        )
        XCTAssertTrue(
            eventList.contains { $0.hasPrefix("focus") },
            "Expected 'focus' event, got: \(eventList)"
        )

        let ghosttyBecameFrontmost = await pollUntil(timeout: 3.0) {
            await MainActor.run {
                NSWorkspace.shared.frontmostApplication?.bundleIdentifier == ghosttyBundleId
            }
        }
        XCTAssertTrue(
            ghosttyBecameFrontmost,
            "FAIL: Ghostty did not become frontmost within 3s after jump"
        )

        let paneBecameFocused = await pollUntil(timeout: 3.0) {
            guard let output = try? runHerdrAgentList(herdrPath: herdrPath) else { return false }
            return output.contains("\"focused\":true") && output.contains(paneId)
        }
        XCTAssertTrue(
            paneBecameFocused,
            "FAIL: pane '\(paneId)' did not report focused==true within 3s"
        )

        NSLog("[HerdCodeLiveSmoke] Events: %@", eventList.joined(separator: ", "))
        NSLog("[HerdCodeLiveSmoke] Ghostty frontmost: %@", String(ghosttyBecameFrontmost))
        NSLog("[HerdCodeLiveSmoke] Pane focused: %@", String(paneBecameFocused))
    }

    private func runHerdrAgentList(herdrPath: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: herdrPath)
        process.arguments = ["agent", "list"]

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func extractFirstPaneId(from json: String) -> String? {
        let pattern = #"\"pane_id\"\s*:\s*\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: json, range: NSRange(json.startIndex..., in: json)),
              let range = Range(match.range(at: 1), in: json) else {
            return nil
        }

        let paneId = String(json[range])
        return paneId.isEmpty ? nil : paneId
    }

    private func pollUntil(timeout: TimeInterval, condition: @Sendable () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    @MainActor
    private func activateFinder() async throws {
        guard let finderURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
            throw HerdrError.activationFailed(bundleId: "com.apple.finder", reason: "Finder not found")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: finderURL, configuration: configuration)
    }
}

private struct RecordingActivatorWrapper: AppActivating {
    let inner: GhosttyNSWorkspaceActivator
    let events: LockedEvents
    let label: String

    @MainActor
    func activate() async throws {
        events.append("\(label)-start")
        try await inner.activate()
        events.append("\(label)-end")
    }
}

private struct RecordingExecutorWrapper: JumpExecuting {
    let herdrPath: String
    let events: LockedEvents
    let label: String

    func focusPane(_ paneId: String) async throws {
        events.append("\(label)-start")
        let executor = HerdrProcessJumpExecutor(herdrPath: herdrPath)
        try await executor.focusPane(paneId)
        events.append("\(label)-end")
    }
}
