import Foundation

// MARK: - Agent Status

enum AgentStatus: String, Codable {
    case working
    case idle
    case stopped
    case unknown

    var icon: String {
        switch self {
        case .working: return "⚡"
        case .idle:    return "💤"
        case .stopped: return "⏹"
        case .unknown: return "❓"
        }
    }

    var label: String {
        switch self {
        case .working: return "작업 중"
        case .idle:    return "대기 중"
        case .stopped: return "중지됨"
        case .unknown: return "알 수 없음"
        }
    }
}

// MARK: - Herdr Models

/// herdr session list 결과
struct HerdrSession: Identifiable, Codable {
    let name: String
    let status: String   // "running" | "stopped"
    let directory: String
    let socket: String

    var id: String { name }

    var isRunning: Bool { status == "running" }
}

/// herdr agent list 결과 (JSON 래퍼)
struct HerdrAgentListResult: Codable {
    let agents: [HerdrAgent]
    let type: String
}

struct HerdrAgentListResponse: Codable {
    let id: String
    let result: HerdrAgentListResult
}

/// 개별 agent 항목
struct HerdrAgent: Identifiable, Codable {
    let agent: String
    let agentStatus: String   // "working" | "idle"
    let cwd: String
    let focused: Bool
    let paneId: String
    let tabId: String
    let workspaceId: String
    let agentSession: HerdrAgentSession?

    var id: String { paneId }

    var status: AgentStatus {
        AgentStatus(rawValue: agentStatus) ?? .unknown
    }

    enum CodingKeys: String, CodingKey {
        case agent
        case agentStatus  = "agent_status"
        case cwd
        case focused
        case paneId       = "pane_id"
        case tabId        = "tab_id"
        case workspaceId  = "workspace_id"
        case agentSession = "agent_session"
    }
}

struct HerdrAgentSession: Codable {
    let source: String
    let agent: String
    let kind: String
    let value: String   // opencode session ID
}

/// herdr workspace list 결과
struct HerdrWorkspaceListResult: Codable {
    let workspaces: [HerdrWorkspace]
    let type: String
}

struct HerdrWorkspaceListResponse: Codable {
    let id: String
    let result: HerdrWorkspaceListResult
}

struct HerdrWorkspace: Identifiable, Codable {
    let workspaceId: String
    let label: String
    let agentStatus: String
    let focused: Bool
    let tabCount: Int
    let paneCount: Int

    var id: String { workspaceId }

    var status: AgentStatus {
        AgentStatus(rawValue: agentStatus) ?? .unknown
    }

    enum CodingKeys: String, CodingKey {
        case workspaceId  = "workspace_id"
        case label
        case agentStatus  = "agent_status"
        case focused
        case tabCount     = "tab_count"
        case paneCount    = "pane_count"
    }
}

// MARK: - OpenCode Models

/// opencode DB session 테이블 행
struct OpencodeSession: Identifiable {
    let id: String
    let title: String
    let projectId: String
    let timeCreated: Date
    let timeUpdated: Date
    let timeArchived: Date?
    let agent: String?
    let model: String?
    let cost: Double
    let tokensInput: Int
    let tokensOutput: Int

    var isActive: Bool { timeArchived == nil }

    /// 마지막 업데이트 기준 활성 여부 (5분 이내)
    var isRecentlyActive: Bool {
        Date().timeIntervalSince(timeUpdated) < 300
    }
}

/// opencode DB todo 테이블 행
struct OpencodeTodo: Identifiable {
    let sessionId: String
    let content: String
    let status: String   // "pending" | "in_progress" | "completed" | "cancelled"
    let priority: String
    let position: Int

    var id: String { "\(sessionId)-\(position)" }

    var statusIcon: String {
        switch status {
        case "completed":  return "✅"
        case "in_progress": return "🔄"
        case "cancelled":  return "❌"
        default:           return "⏳"
        }
    }
}

// MARK: - Aggregated App State

struct AppState {
    var herdrSessions: [HerdrSession] = []
    var herdrAgents: [HerdrAgent] = []
    var herdrWorkspaces: [HerdrWorkspace] = []
    var opencodeSessions: [OpencodeSession] = []
    var opencodeTodos: [OpencodeTodo] = []
    var lastUpdated: Date = Date()

    /// 전체 agent 중 working 상태인 것 수
    var workingAgentCount: Int {
        herdrAgents.filter { $0.status == .working }.count
    }

    /// 실행 중인 herdr 세션 수
    var runningHerdrSessionCount: Int {
        herdrSessions.filter { $0.isRunning }.count
    }

    /// 활성 opencode 세션 수 (아카이브되지 않은 것)
    var activeOpencodeSessionCount: Int {
        opencodeSessions.filter { $0.isActive }.count
    }

    /// 전체 진행 중 TODO 수
    var inProgressTodoCount: Int {
        opencodeTodos.filter { $0.status == "in_progress" }.count
    }

    /// 메뉴바 아이콘에 표시할 전체 상태
    var overallStatus: AgentStatus {
        if workingAgentCount > 0 { return .working }
        if runningHerdrSessionCount > 0 { return .idle }
        return .stopped
    }

    /// 메뉴바 타이틀 문자열
    var menuBarTitle: String {
        let icon = overallStatus.icon
        if workingAgentCount > 0 {
            return "\(icon) \(workingAgentCount)"
        }
        return icon
    }

    func todosFor(_ session: OpencodeSession) -> [OpencodeTodo] {
        opencodeTodos.filter { $0.sessionId == session.id }
    }
}
