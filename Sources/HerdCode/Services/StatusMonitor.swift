import Foundation
import AppKit

@MainActor
final class StatusMonitor: ObservableObject {

    @Published var state = AppState()
    @Published var lastError: String?

    private let herdr: HerdrService
    private let opencode: OpencodeService

    private var timer: Timer?
    private let pollInterval: TimeInterval

    private var previousOverallStatus: AgentStatus = .unknown
    private var previousWorkingCount: Int = 0

    init(pollInterval: TimeInterval = 5.0, herdrService: HerdrService? = nil) {
        self.pollInterval = pollInterval
        self.herdr = herdrService ?? HerdrService()
        self.opencode = OpencodeService()
    }

    convenience init(herdrService: HerdrService, pollInterval: TimeInterval = 5.0) {
        self.init(pollInterval: pollInterval, herdrService: herdrService)
    }

    func rowState(for agent: HerdrAgent) -> AgentRowState {
        TerminalJumpResolver.rowState(for: agent)
    }

    func rowState(for session: OpencodeSession) -> AgentRowState {
        TerminalJumpResolver.rowState(for: session, agents: state.herdrAgents)
    }

    // Jump errors are surfaced via lastError (best-effort; may be overwritten by the next poll cycle).
    // The authoritative jump-failure log line is written by JumpLogger with prefix [HerdCodeJumpError].
    func jumpToAgent(_ agent: HerdrAgent) async {
        let target = rowState(for: agent).focusTarget
        guard let paneId = target else { return }
        do {
            try await herdr.focusPane(paneId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func jumpToSession(_ session: OpencodeSession) async {
        let target = rowState(for: session).focusTarget
        guard let paneId = target else { return }
        do {
            try await herdr.focusPane(paneId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func start() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() async {
        var herdrSessions:    [HerdrSession]    = state.herdrSessions
        var herdrAgents:      [HerdrAgent]      = state.herdrAgents
        var herdrWorkspaces:  [HerdrWorkspace]  = state.herdrWorkspaces
        var ocSessions:       [OpencodeSession] = state.opencodeSessions
        var ocTodos:          [OpencodeTodo]    = state.opencodeTodos
        var errors:           [String]          = []

        do { herdrSessions  = try await herdr.fetchSessions()            } catch { errors.append("herdr sessions: \(error.localizedDescription)") }
        do { herdrAgents    = try await herdr.fetchAgents()              } catch { errors.append("herdr agents: \(error.localizedDescription)") }
        do { herdrWorkspaces = try await herdr.fetchWorkspaces()         } catch { errors.append("herdr workspaces: \(error.localizedDescription)") }
        do { ocSessions     = try await opencode.fetchRecentSessions(limit: 10) } catch { errors.append("opencode sessions: \(error.localizedDescription)") }

        let activeSids = ocSessions.filter { $0.isActive }.map { $0.id }
        do { ocTodos = try await opencode.fetchTodos(for: activeSids)   } catch { errors.append("opencode todos: \(error.localizedDescription)") }

        let newState = AppState(
            herdrSessions:    herdrSessions,
            herdrAgents:      herdrAgents,
            herdrWorkspaces:  herdrWorkspaces,
            opencodeSessions: ocSessions,
            opencodeTodos:    ocTodos,
            lastUpdated:      Date()
        )

        detectChangesAndNotify(newState: newState)
        state = newState
        lastError = errors.isEmpty ? nil : errors.joined(separator: " | ")
    }

    private func detectChangesAndNotify(newState: AppState) {
        let newStatus = newState.overallStatus
        let newCount  = newState.workingAgentCount

        defer {
            previousOverallStatus = newStatus
            previousWorkingCount  = newCount
        }

        guard previousOverallStatus != .unknown else { return }

        if previousOverallStatus == .working && newStatus != .working {
            sendNotification(
                title: "✅ 작업 완료",
                body: "모든 AI 에이전트가 대기 상태로 전환됐습니다."
            )
            return
        }

        if previousOverallStatus == .working &&
           newStatus == .working &&
           newCount < previousWorkingCount {
            sendNotification(
                title: "⚡ 에이전트 완료",
                body: "\(previousWorkingCount - newCount)개 에이전트가 완료. 현재 \(newCount)개 진행 중."
            )
        }
    }

    private func sendNotification(title: String, body: String) {
        NSLog("[HerdCode] %@: %@", title, body)
    }
}
