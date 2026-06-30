import Foundation
import AppKit

protocol OpencodeProviding: Sendable {
    func fetchRecentSessions(limit: Int) async throws -> [OpencodeSession]
    func fetchTodos(for sessionIds: [String]) async throws -> [OpencodeTodo]
}

extension OpencodeService: OpencodeProviding {}

@MainActor
final class StatusMonitor: ObservableObject {

    @Published var state = AppState()
    @Published var lastError: String?

    private let herdr: HerdrService
    private let opencode: any OpencodeProviding
    private let claudeCode: any ClaudeCodeProviding
    private let remoteTargets: [HerdrTarget]
    private let remoteServiceFactory: @Sendable (HerdrTarget) -> HerdrService

    private var timer: Timer?
    private let pollInterval: TimeInterval

    private var previousOverallStatus: AgentStatus = .unknown
    private var previousWorkingCount: Int = 0

    init(
        pollInterval: TimeInterval = 5.0,
        herdrService: HerdrService? = nil,
        targets: [HerdrTarget]? = nil,
        remoteTargetConfig: RemoteTargetConfig = RemoteTargetConfig(),
        opencodeService: (any OpencodeProviding)? = nil,
        claudeCodeService: (any ClaudeCodeProviding)? = nil,
        remoteServiceFactory: @escaping @Sendable (HerdrTarget) -> HerdrService = { target in
            guard let remote = target.remote, let session = target.session else {
                return HerdrService()
            }
            return HerdrService(
                commandRunner: HerdrService.sshCommandRunner(
                    remote: remote,
                    session: session,
                    herdrPath: target.herdrPath
                )
            )
        }
    ) {
        self.pollInterval = pollInterval
        self.herdr = herdrService ?? HerdrService()
        self.opencode = opencodeService ?? OpencodeService()
        self.claudeCode = claudeCodeService ?? ClaudeCodeService()
        self.remoteTargets = (targets ?? remoteTargetConfig.loadTargets()).filter { !$0.isLocal }
        self.remoteServiceFactory = remoteServiceFactory
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
        var localSessions:    [HerdrSession]    = state.herdrSessions.filter { $0.targetLabel == HerdrTarget.local.label }
        var localAgents:      [HerdrAgent]      = state.herdrAgents.filter { $0.targetLabel == HerdrTarget.local.label }
        var herdrWorkspaces:  [HerdrWorkspace]  = state.herdrWorkspaces
        var ocSessions:       [OpencodeSession] = state.opencodeSessions
        var ocTodos:          [OpencodeTodo]    = state.opencodeTodos
        var ccSessions:       [ClaudeCodeSession] = state.claudeCodeSessions
        var remoteOpencodeSessions: [RemoteOpencodeSession] = []
        var errors:           [String]          = []

        do { localSessions  = localizedSessions(try await herdr.fetchSessions(), target: .local) } catch { errors.append("herdr sessions: \(error.localizedDescription)") }
        do { localAgents    = localizedAgents(try await herdr.fetchAgents(), target: .local) } catch { errors.append("herdr agents: \(error.localizedDescription)") }
        do { herdrWorkspaces = try await herdr.fetchWorkspaces()         } catch { errors.append("herdr workspaces: \(error.localizedDescription)") }
        do { ocSessions     = try await opencode.fetchRecentSessions(limit: 10) } catch { errors.append("opencode sessions: \(error.localizedDescription)") }

        let activeSids = ocSessions.filter { $0.isActive }.map { $0.id }
        do { ocTodos = try await opencode.fetchTodos(for: activeSids)   } catch { errors.append("opencode todos: \(error.localizedDescription)") }

        do {
            ccSessions = try await claudeCode.fetchSessions()
        } catch {
            errors.append("claudeCode: \(error.localizedDescription)")
        }

        var herdrSessions = localSessions
        var herdrAgents = localAgents

        for target in remoteTargets {
            let remoteService = remoteServiceFactory(target)

            do {
                let remoteSessions = localizedSessions(try await remoteService.fetchSessions(), target: target)
                herdrSessions.append(contentsOf: remoteSessions)
                remoteOpencodeSessions.append(
                    contentsOf: remoteSessions.map {
                        RemoteOpencodeSession(targetLabel: target.label, sessionId: $0.name, isRunning: $0.isRunning)
                    }
                )
            } catch {
                errors.append("\(target.label) herdr sessions: \(error.localizedDescription)")
            }

            do {
                let remoteAgents = localizedAgents(try await remoteService.fetchAgents(), target: target)
                herdrAgents.append(contentsOf: remoteAgents)
            } catch {
                errors.append("\(target.label) herdr agents: \(error.localizedDescription)")
            }
        }

        let newState = AppState(
            herdrSessions:    herdrSessions,
            herdrAgents:      herdrAgents,
            herdrWorkspaces:  herdrWorkspaces,
            opencodeSessions: ocSessions,
            remoteOpencodeSessions: remoteOpencodeSessions,
            opencodeTodos:    ocTodos,
            claudeCodeSessions: ccSessions,
            lastUpdated:      Date()
        )

        detectChangesAndNotify(newState: newState)
        state = newState
        lastError = errors.isEmpty ? nil : errors.joined(separator: " | ")
    }

    private func localizedSessions(_ sessions: [HerdrSession], target: HerdrTarget) -> [HerdrSession] {
        sessions.map {
            var session = $0
            session.targetLabel = target.label
            return session
        }
    }

    private func localizedAgents(_ agents: [HerdrAgent], target: HerdrTarget) -> [HerdrAgent] {
        agents.map { agent in
            let isLocalTarget = target.isLocal
            return HerdrAgent(
                agent: agent.agent,
                agentStatus: agent.agentStatus,
                cwd: agent.cwd,
                focused: isLocalTarget ? agent.focused : false,
                paneId: isLocalTarget ? agent.paneId : "",
                tabId: agent.tabId,
                workspaceId: agent.workspaceId,
                agentSession: isLocalTarget ? agent.agentSession : nil,
                targetLabel: target.label
            )
        }
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
