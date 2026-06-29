import SwiftUI

private let kFontScale = "HerdCode.fontScale"
private let fontScaleMin: Double = 0.8
private let fontScaleMax: Double = 1.4
private let fontScaleStep: Double = 0.1

struct MenuBarView: View {
    @ObservedObject var monitor: StatusMonitor
    @AppStorage(kFontScale) private var fontScale: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                herdrSection
                Divider()
                opencodeSection
            }
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
            Button { fontScale = max(fontScaleMin, fontScale - fontScaleStep) } label: {
                Text("A").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("글자 크기 줄이기")
            .disabled(fontScale <= fontScaleMin)

            Button { fontScale = min(fontScaleMax, fontScale + fontScaleStep) } label: {
                Text("A").font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("글자 크기 늘리기")
            .disabled(fontScale >= fontScaleMax)

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
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Herdr", count: monitor.state.herdrAgents.filter { $0.status == .working }.count, total: monitor.state.herdrAgents.count + monitor.state.herdrSessions.count)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                subSectionTitle("Agents", count: monitor.state.herdrAgents.filter { $0.status == .working }.count, total: monitor.state.herdrAgents.count)
                if monitor.state.herdrAgents.isEmpty {
                    emptyRow("agent 없음")
                } else {
                    ForEach(monitor.state.herdrAgents) { agent in
                        HerdrAgentRow(agent: agent, fontScale: fontScale) {
                            Task { await monitor.jumpToAgent(agent) }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 4)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                subSectionTitle("Sessions", count: monitor.state.runningHerdrSessionCount, total: monitor.state.herdrSessions.count)
                if monitor.state.herdrSessions.isEmpty {
                    emptyRow("세션 없음")
                } else {
                    ForEach(monitor.state.herdrSessions) { session in
                        HerdrSessionRow(session: session, fontScale: fontScale)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    // MARK: - OpenCode Section

    private var opencodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(
                "OpenCode",
                count: monitor.state.activeOpencodeSessionCount,
                total: monitor.state.opencodeSessions.count
            )
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)

            VStack(alignment: .leading, spacing: 4) {
                subSectionTitle("Sessions", count: monitor.state.activeOpencodeSessionCount, total: monitor.state.opencodeSessions.count)
                if monitor.state.opencodeSessions.isEmpty {
                    emptyRow("활성 세션 없음")
                } else {
                    ForEach(monitor.state.opencodeSessions) { session in
                        OpencodeSessionRow(
                            session: session,
                            fontScale: fontScale,
                            onTap: monitor.rowState(for: session).isEnabled
                                ? { Task { await monitor.jumpToSession(session) } }
                                : nil
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 4)

            if !monitor.state.opencodeTodos.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 4) {
                    subSectionTitle("Todos", count: monitor.state.inProgressTodoCount, total: monitor.state.opencodeTodos.count)
                    ForEach(monitor.state.opencodeTodos.prefix(5)) { todo in
                        TodoRow(todo: todo, fontScale: fontScale)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 6)
            } else {
                Spacer().frame(height: 2)
            }
        }
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

    private func subSectionTitle(_ title: String, count: Int? = nil, total: Int? = nil) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            if let count, let total {
                Text("\(count)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.25))
            } else if let count {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            Spacer()
        }
    }

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
            .font(.system(size: scaled(12), weight: .regular))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 2)
    }

    private func scaled(_ base: CGFloat) -> CGFloat { base * fontScale }
}

// MARK: - Row Views

private struct HerdrAgentRow: View {
    let agent: HerdrAgent
    let fontScale: Double
    let onTap: (() -> Void)?

    var body: some View {
        let rowState = TerminalJumpResolver.rowState(for: agent)
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(agent.status == .working ? Color.green : Color.gray.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(agent.agent)
                    .font(.system(size: 13 * fontScale))
                Spacer()
                Text(agent.status.label)
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(agent.status == .working ? .green : .secondary)
                Text(shortPath(agent.cwd))
                    .font(.system(size: 10 * fontScale))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!rowState.isEnabled)
        .help(rowState.isEnabled ? "" : rowState.helpText)
    }

    private func shortPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

private struct HerdrSessionRow: View {
    let session: HerdrSession
    let fontScale: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.isRunning ? "terminal.fill" : "terminal")
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(session.isRunning ? .primary : .tertiary)
            Text(session.name)
                .font(.system(size: 13 * fontScale))
            Spacer()
            Text(session.isRunning ? "실행 중" : "중지됨")
                .font(.system(size: 10 * fontScale))
                .foregroundStyle(session.isRunning ? .secondary : .tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct OpencodeSessionRow: View {
    let session: OpencodeSession
    let fontScale: Double
    let onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.isRecentlyActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 7, height: 7)
                Text(session.title)
                    .font(.system(size: 13 * fontScale))
                    .lineLimit(1)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(relativeTime(session.timeUpdated))
                        .font(.system(size: 10 * fontScale))
                        .foregroundStyle(.tertiary)
                    if session.cost > 0 {
                        Text(String(format: "$%.4f", session.cost))
                            .font(.system(size: 10 * fontScale))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .help(onTap == nil ? "현재 연결된 terminal 없음" : "")
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
    let fontScale: Double

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(todo.statusIcon)
                .font(.system(size: 11 * fontScale))
            Text(todo.content)
                .font(.system(size: 11 * fontScale))
                .lineLimit(2)
                .foregroundStyle(todo.status == "in_progress" ? .primary : .secondary)
        }
        .padding(.vertical, 1)
    }
}
