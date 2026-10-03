import SwiftUI

// The list under a module's activity: one line per Claude Code session, per pull request,
// per GitHub event. Sober lines, like the rows of the overview: a dot in the colour of the
// state, the name, what it does, the state in words, the time. Past a few lines it scrolls.

struct ModuleRowsList: View {
    let module: ModuleSnapshot
    /// Sessions say since when; events and pull requests say when.
    var elapsed = false

    /// Five lines are seen at once; the others scroll.
    private let limit: CGFloat = 5 * ModuleRowLine.height + 40
    @Environment(\.islandLayerShown) private var shown

    var body: some View {
        ScrollView(.vertical) {
            // The times move on by themselves, slowly, and only while the island shows them
            TimelineView(.periodic(from: .now, by: shown ? 30 : 3600)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(module.rows) { row in
                        if let section = row.section {
                            Text(section)
                                .font(IslandTheme.text(10.5, .semibold))
                                .foregroundStyle(IslandTheme.faint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, 7)
                                .padding(.top, row.id == module.rows.first?.id ? 0 : 6)
                                .padding(.bottom, 1)
                        }
                        ModuleRowLine(row: row, time: time(row, now: shown ? context.date : .now)) {
                            if let action = row.action { IslandActions.row(module.id, action) }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(maxHeight: limit)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func time(_ row: ModuleRow, now: Date) -> String {
        guard let date = row.date else { return "" }
        return elapsed ? RowTime.elapsed(since: date, now: now) : RowTime.clock(date, now: now)
    }
}

/// One line: dot, title, detail, state, time.
private struct ModuleRowLine: View {
    static let height: CGFloat = 24
    let row: ModuleRow
    let time: String
    let action: () -> Void
    @State private var hover = false

    private var color: Color {
        switch row.state {
        case .neutral: return IslandTheme.faint
        case .busy:    return IslandTheme.blue
        case .waiting: return IslandTheme.amber
        case .success: return IslandTheme.green
        case .failure: return IslandTheme.red
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(row.title)
                    .font(IslandTheme.text(12, .semibold))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(row.detail)
                    .font(IslandTheme.text(11.5, .regular))
                    .foregroundStyle(IslandTheme.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.label)
                    .font(IslandTheme.text(11, .semibold))
                    .foregroundStyle(row.state == .neutral ? IslandTheme.muted : color)
                    .lineLimit(1)
                    .fixedSize()
                if !time.isEmpty {
                    Text(time)
                        .font(IslandTheme.round(11, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(IslandTheme.faint)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            .padding(.horizontal, 7)
            .frame(height: Self.height)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover && row.action != nil ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.action == nil)
        .onHover { hover = $0 }
        .accessibilityLabel("\(row.title), \(row.detail), \(row.label)")
    }
}
