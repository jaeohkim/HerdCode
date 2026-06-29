import SwiftUI

/// 메뉴바 드롭다운 전체 뷰
struct MenuBarView: View {
    @ObservedObject var monitor: StatusMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    herdrSection
                    Divider()
                    opencodeSection
                    if !monitor.state.opencodeTodos.isEmpty {
                        Divider()
                        todoSection
                    }
                }
            }
            .frame(maxHeight: 320)
            Divider()
            footerSection
        }
        .frame(width: 340)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Text(monitor.state.overallStatus.icon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("HerdCode")
                    .font(.headline)
                Text(monitor.state.overallStatus.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("새로고침")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.3))
    }

    // MARK: - Herdr Section

    private var herdrSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Herdr", count: monitor.state.runningHerdrSessionCount, total: monitor.state.herdrSessions.count)

            // Agent 상태 (활성인 것만)
            ForEach(monitor.state.herdrAgents) { agent in
                HerdrAgentRow(agent: agent)
            }

            // Session 목록
            ForEach(monitor.state.herdrSessions) { session in
                HerdrSessionRow(session: session)
            }

            if monitor.state.herdrAgents.isEmpty && monitor.state.herdrSessions.isEmpty {
                emptyRow("herdr 세션 없음")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - OpenCode Section

    private var opencodeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(
                "OpenCode",
                count: monitor.state.activeOpencodeSessionCount,
                total: monitor.state.opencodeSessions.count
            )

            ForEach(monitor.state.opencodeSessions.prefix(5)) { session in
                OpencodeSessionRow(session: session)
            }

            if monitor.state.opencodeSessions.isEmpty {
                emptyRow("활성 세션 없음")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - TODO Section

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("진행 중 TODO", count: monitor.state.inProgressTodoCount)

            ForEach(monitor.state.opencodeTodos.prefix(5)) { todo in
                TodoRow(todo: todo)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if let err = monitor.lastError {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("업데이트: \(monitor.state.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("종료") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, count: Int? = nil, total: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let count, let total {
                Text("\(count)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let count {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 2)
    }
}

// MARK: - Row Views

private struct HerdrAgentRow: View {
    let agent: HerdrAgent

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(agent.status == .working ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(agent.agent)
                .font(.callout)
            Spacer()
            Text(agent.status.label)
                .font(.caption)
                .foregroundStyle(agent.status == .working ? .green : .secondary)
            Text(shortPath(agent.cwd))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

private struct HerdrSessionRow: View {
    let session: HerdrSession

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.isRunning ? "terminal.fill" : "terminal")
                .font(.caption)
                .foregroundStyle(session.isRunning ? .primary : .tertiary)
            Text(session.name)
                .font(.callout)
            Spacer()
            Text(session.isRunning ? "실행 중" : "중지됨")
                .font(.caption2)
                .foregroundStyle(session.isRunning ? .secondary : .tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct OpencodeSessionRow: View {
    let session: OpencodeSession

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.isRecentlyActive ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 7, height: 7)
            Text(session.title)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(relativeTime(session.timeUpdated))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if session.cost > 0 {
                    Text(String(format: "$%.4f", session.cost))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "\(diff)초 전" }
        if diff < 3600 { return "\(diff / 60)분 전" }
        if diff < 86400 { return "\(diff / 3600)시간 전" }
        return "\(diff / 86400)일 전"
    }
}

private struct TodoRow: View {
    let todo: OpencodeTodo

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(todo.statusIcon)
                .font(.caption)
            Text(todo.content)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(todo.status == "in_progress" ? .primary : .secondary)
        }
        .padding(.vertical, 1)
    }
}
