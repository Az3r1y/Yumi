import SwiftUI

// The list under a module's activity: one line per Claude Code session, per pull request,
// per GitHub event. Sober lines, like the rows of the overview: a dot in the colour of the
// state, the name, what it does, the state in words, the time. Past a few lines it scrolls.

struct ModuleRowsList: View {
    let module: ModuleSnapshot
    /// Sessions say since when; events and pull requests say when.
    var elapsed = false

    /// Lines seen at once; the others scroll.
    var lines = 5
    private var limit: CGFloat { CGFloat(lines) * ModuleRowLine.height + 40 + (open.isEmpty ? 0 : 110) }
    @Environment(\.islandLayerShown) private var shown
    /// The lines unfolded to show their details.
    @State private var open: Set<String> = {
        #if DEBUG
        // Captures: `YUMI_ISLAND_UNFOLD=<row id>` opens a line from the start
        if let id = ProcessInfo.processInfo.environment["YUMI_ISLAND_UNFOLD"] { return [id] }
        #endif
        return []
    }()

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
                        ModuleRowLine(row: row, time: time(row, now: shown ? context.date : .now), unfolded: open.contains(row.id),
                                      tick: row.check.map { check in { IslandActions.row(module.id, check) } }) {
                            if !row.details.isEmpty {
                                withAnimation(.islandSpring(0.35)) {
                                    if open.contains(row.id) { open.remove(row.id) } else { open.insert(row.id) }
                                }
                            } else if let action = row.action {
                                IslandActions.row(module.id, action)
                            }
                        }
                        if open.contains(row.id) {
                            RowDetails(lines: row.details) {
                                if let action = row.action { IslandActions.row(module.id, action) }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
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
    var unfolded = false
    /// Ticks the box of the line, when it has one.
    var tick: (() -> Void)? = nil
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
        HStack(spacing: 0) {
            if let tick {
                Button(action: tick) {
                    Image(systemName: "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(row.state == .failure ? IslandTheme.red : IslandTheme.muted)
                        .frame(width: 20, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(loc("Marquer comme terminée"))
                .accessibilityLabel(loc("Marquer « \(row.title) » comme terminée"))
            }
            line
        }
    }

    private var line: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if tick == nil { Circle().fill(color).frame(width: 6, height: 6) }
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
                if let progress = row.progress {
                    Text(progress)
                        .font(IslandTheme.round(10.5, .bold))
                        .monospacedDigit()
                        .foregroundStyle(IslandTheme.fg)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .fixedSize()
                }
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
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity((hover || unfolded) && clickable ? 0.09 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .onHover { hover = $0 }
        .accessibilityLabel("\(row.title), \(row.detail), \(row.label)")
    }

    private var clickable: Bool { row.action != nil || !row.details.isEmpty }
}

/// The details of an unfolded line, then the button that opens where it runs.
private struct RowDetails: View {
    let lines: [String]
    let open: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(IslandTheme.text(11, line.hasPrefix("·") ? .regular : .medium))
                    .foregroundStyle(line.hasPrefix("·") ? IslandTheme.muted : IslandTheme.fg)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextButton(label: loc("Ouvrir le terminal"), action: open)
        }
        .padding(.leading, 20)
        .padding(.trailing, 7)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
