struct AgentRowState: Equatable {
    let uiKey: String
    let isEnabled: Bool
    let focusTarget: String?
    let helpText: String
}

enum TerminalJumpResolver {
    private static let disabledHelpText = "현재 연결된 terminal 없음"

    static func rowState(for agent: HerdrAgent) -> AgentRowState {
        let hasPane = !agent.paneId.isEmpty
        return AgentRowState(
            uiKey: agent.paneId.isEmpty ? "\(agent.agent)|\(agent.tabId)|\(agent.workspaceId)" : agent.paneId,
            isEnabled: hasPane,
            focusTarget: hasPane ? agent.paneId : nil,
            helpText: hasPane ? "" : disabledHelpText
        )
    }

    static func rowState(for session: OpencodeSession, agents: [HerdrAgent]) -> AgentRowState {
        guard let winner = agents
            .filter(isLiveMapped(to: session))
            .sorted(by: preferredAgent)
            .first,
              !winner.paneId.isEmpty else {
            return disabledSessionRowState(for: session)
        }

        return AgentRowState(
            uiKey: session.id,
            isEnabled: true,
            focusTarget: winner.paneId,
            helpText: ""
        )
    }

    private static func disabledSessionRowState(for session: OpencodeSession) -> AgentRowState {
        AgentRowState(
            uiKey: session.id,
            isEnabled: false,
            focusTarget: nil,
            helpText: disabledHelpText
        )
    }

    private static func isLiveMapped(to session: OpencodeSession) -> (HerdrAgent) -> Bool {
        { agent in
            guard let agentSession = agent.agentSession else { return false }
            return agentSession.source == "herdr:opencode"
                && agentSession.kind == "id"
                && agentSession.value == session.id
        }
    }

    private static func preferredAgent(_ lhs: HerdrAgent, _ rhs: HerdrAgent) -> Bool {
        if lhs.focused != rhs.focused {
            return lhs.focused && !rhs.focused
        }

        let lhsWorking = lhs.agentStatus == "working"
        let rhsWorking = rhs.agentStatus == "working"
        if lhsWorking != rhsWorking {
            return lhsWorking && !rhsWorking
        }

        return lhs.paneId < rhs.paneId
    }
}
