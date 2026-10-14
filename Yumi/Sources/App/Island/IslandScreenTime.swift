import SwiftUI

/// Screen time in the open island: today against the threshold, then today hour by hour, the
/// last seven days, and the figures of the last two weeks (`ScreenTimeSummary`).
struct ScreenTimeActivity: View {
    let module: ModuleSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActRow {
                ActMeta(color: module.color, text: "\(module.name) · \(module.status)").riseIn(0)
                ActTitle(text: module.title).riseIn(1)
                ActSub(text: module.subtitle).riseIn(2)
                if let progress = module.progress {
                    ActProgress(progress: progress).riseIn(3)
                }
            } trail: {
                RoundButton(symbol: module.primarySymbol ?? "gearshape.fill", label: module.primaryAction) {
                    IslandActions.module(module.id, "primary")
                }
            }
            HStack(alignment: .bottom, spacing: 18) {
                if let hours = module.pages["hours"], !hours.isEmpty {
                    ScreenTimeBars(rows: hours, color: module.color, caption: loc("aujourd'hui"), shownLabels: [hours.first, hours.last])
                }
                if let days = module.pages["days"] {
                    ScreenTimeBars(rows: days, color: Color(hex: ScreenTimeSummary.calm), caption: loc("7 jours"),
                                   shownLabels: days.map { $0 })
                }
                Spacer(minLength: 0)
            }
            .riseIn(4)
            if let figures = module.pages["figures"], !figures.isEmpty {
                Text(figures.map { "\($0.title) \($0.label)" }.joined(separator: " · "))
                    .font(IslandTheme.text(10, .medium))
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .riseIn(5)
            }
        }
    }
}

/// Small bars, one per line of the page: its minutes are in `detail`. A day over the threshold
/// is drawn red.
private struct ScreenTimeBars: View {
    let rows: [ModuleRow]
    let color: Color
    let caption: String
    /// The lines whose title is written under their bar.
    let shownLabels: [ModuleRow?]

    var body: some View {
        let values = rows.map { Int($0.detail) ?? 0 }
        let top = max(values.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(row.state == .failure ? IslandTheme.red : color.opacity(values[index] > 0 ? 0.9 : 0.25))
                            .frame(width: 6, height: max(2, 26 * CGFloat(values[index]) / CGFloat(top)))
                            .help(Text(verbatim: "\(row.title) · \(row.label)"))
                        Text(shownLabels.contains { $0?.id == row.id } ? row.title : " ")
                            .font(IslandTheme.text(8, .medium))
                            .foregroundStyle(IslandTheme.faint)
                            .fixedSize()
                            .frame(width: 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(row.title) : \(row.label)"))
                }
            }
            .frame(height: 38, alignment: .bottom)
            Text(caption)
                .font(IslandTheme.text(9, .medium))
                .foregroundStyle(IslandTheme.faint)
        }
    }
}
