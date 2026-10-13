import SwiftUI

// What a Claude Code session does, seen from Yumi: the request, the action in progress, the
// last actions with their files and commands, the todo list and the files touched. Everything
// comes from the session's journal (Modules/ClaudeCode/ClaudeSessionJournal.swift), live.

struct SessionLive: View {
    let row: ModuleRow
    let journal: SessionJournal?

    private var color: Color {
        switch row.state {
        case .waiting: return IslandTheme.amber
        case .failure: return IslandTheme.red
        case .success: return IslandTheme.green
        case .busy, .neutral: return IslandSessions.color(row.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            head
            if let journal {
                if let current = journal.current {
                    StepLine(step: current, live: true)
                } else if row.state == .waiting || row.state == .failure {
                    Text(row.detail)
                        .font(IslandTheme.text(12.5, .semibold))
                        .foregroundStyle(color)
                        .lineLimit(2)
                } else if let summary = journal.summary {
                    Text(summary)
                        .font(IslandTheme.text(12, .medium))
                        .foregroundStyle(IslandTheme.fg)
                        .lineLimit(2)
                }
                HStack(alignment: .top, spacing: 16) {
                    // The last actions, newest first
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(journal.history.reversed().prefix(6).enumerated()), id: \.offset) { index, step in
                            StepLine(step: step, live: false)
                                .opacity(1 - Double(index) * 0.11)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !journal.todos.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(journal.todos.prefix(7).enumerated()), id: \.offset) { _, todo in
                                TodoLine(todo: todo, color: color)
                            }
                        }
                        .frame(width: 210, alignment: .leading)
                    }
                }
                if !journal.filesTouched.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(journal.filesTouched.suffix(8), id: \.self) { path in
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(IslandTheme.mono(10))
                                .foregroundStyle(IslandTheme.code)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)))
                        }
                    }
                }
            } else {
                Text(row.detail)
                    .font(IslandTheme.text(12.5, .medium))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The project, where it is, and the figures of the turn.
    private var head: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(row.title).font(IslandTheme.text(13, .semibold)).lineLimit(1)
                Text(row.label)
                    .font(IslandTheme.text(11.5))
                    .foregroundStyle(color)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let journal {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.figures(journal, now: context.date))
                            .font(IslandTheme.mono(10.5))
                            .foregroundStyle(IslandTheme.muted)
                            .lineLimit(1)
                    }
                }
            }
            if let request = journal?.request {
                Text("« \(request) »")
                    .font(IslandTheme.text(11.5))
                    .foregroundStyle(IslandTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// "12 min · 3 fichiers · 4 cmd · 1 échec"
    static func figures(_ journal: SessionJournal, now: Date) -> String {
        var parts = [FrenchText.minutes(now.timeIntervalSince(journal.started))]
        if let progress = journal.progress { parts.append(progress) }
        if !journal.filesTouched.isEmpty { parts.append(loc("\(journal.filesTouched.count) fich.")) }
        if journal.commands > 0 { parts.append(loc("\(journal.commands) cmd")) }
        if journal.failures > 0 { parts.append(loc("\(journal.failures) échec(s)")) }
        return parts.joined(separator: " · ")
    }
}

/// One action: its symbol, its verb, its target in code type.
private struct StepLine: View {
    let step: ToolStep
    let live: Bool
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        switch step.kind {
        case .edit:    return "pencil"
        case .read:    return "doc.text"
        case .command: return "terminal"
        case .search:  return "magnifyingglass"
        case .web:     return "globe"
        case .other:   return "sparkle"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: live ? 10.5 : 9, weight: .semibold))
                .frame(width: 14)
                .foregroundStyle(live ? IslandTheme.blue : IslandTheme.muted)
                .opacity(live && pulse ? 0.45 : 1)
            Text(step.sentence)
                .font(step.kind == .command ? IslandTheme.mono(live ? 12 : 10.5) : IslandTheme.text(live ? 12.5 : 11.5, live ? .semibold : .regular))
                .foregroundStyle(live ? IslandTheme.fg : IslandTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onAppear {
            guard live, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// One item of Claude's todo list.
private struct TodoLine: View {
    let todo: SessionTodo
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: todo.state == .completed ? "checkmark.circle.fill" : todo.state == .inProgress ? "circle.dotted" : "circle")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(todo.state == .completed ? IslandTheme.green : todo.state == .inProgress ? color : IslandTheme.faint)
            Text(todo.text)
                .font(IslandTheme.text(11, todo.state == .inProgress ? .semibold : .regular))
                .foregroundStyle(todo.state == .completed ? IslandTheme.faint : todo.state == .inProgress ? IslandTheme.fg : IslandTheme.muted)
                .strikethrough(todo.state == .completed)
                .lineLimit(1)
        }
    }
}
