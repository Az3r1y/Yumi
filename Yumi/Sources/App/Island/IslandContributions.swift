import SwiftUI

// The contribution grid of GitHub, drawn with Yumi's colours (or GitHub's green, in the
// settings): 52 weeks, one square a day. Hovering or clicking a day says its count.

struct ContributionGrid: View {
    let calendar: ContributionCalendar
    var cell: CGFloat = 5
    var gap: CGFloat = 1.5
    /// The day under the pointer, or the one clicked.
    @Binding var selected: ContributionDay?
    @AppStorage(GitHubContributions.paletteKey) private var palette = "yumi"

    var body: some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(calendar.weeks.suffix(53).enumerated()), id: \.offset) { _, week in
                VStack(spacing: gap) {
                    ForEach(week) { day in
                        RoundedRectangle(cornerRadius: cell * 0.28)
                            .fill(Self.color(level: day.level, palette: palette))
                            .frame(width: cell, height: cell)
                            .overlay(RoundedRectangle(cornerRadius: cell * 0.28)
                                .strokeBorder(Color.white.opacity(selected == day ? 0.8 : 0), lineWidth: 1))
                            .onHover { inside in
                                if inside { selected = day } else if selected == day { selected = nil }
                            }
                            .onTapGesture { selected = day }
                            .accessibilityLabel(Self.sentence(for: day))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Level 0 to 4 in Yumi's violet, or GitHub's greens.
    static func color(level: Int, palette: String) -> Color {
        if palette == "github" {
            let greens = ["#2D333B", "#0E4429", "#006D32", "#26A641", "#39D353"]
            return Color(hex: greens[max(0, min(4, level))])
        }
        guard level > 0 else { return Color.white.opacity(0.08) }
        return IslandTheme.violet.opacity([0, 0.35, 0.55, 0.78, 1][min(4, level)])
    }

    /// "12 contributions le 3 octobre", "Aucune contribution le 3 octobre".
    static func sentence(for day: ContributionDay) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        let date = parser.date(from: day.date).map(formatter.string(from:)) ?? day.date
        switch day.count {
        case 0:  return loc("Aucune contribution le \(date)")
        case 1:  return loc("Une contribution le \(date)")
        default: return loc("\(day.count) contributions le \(date)")
        }
    }
}

/// The grid in the island's GitHub view: compact, the total and the streak on one line, or
/// the day under the pointer.
struct IslandContributions: View {
    @ObservedObject private var contributions = GitHubContributions.shared
    @AppStorage(GitHubContributions.inIslandKey) private var shown = true
    @State private var selected: ContributionDay?

    var body: some View {
        if shown, let calendar = contributions.calendar {
            VStack(alignment: .leading, spacing: 4) {
                ContributionGrid(calendar: calendar, cell: 5, gap: 1.5, selected: $selected)
                Text(selected.map(ContributionGrid.sentence(for:)) ?? Self.summary(calendar))
                    .font(IslandTheme.text(10.5, .medium))
                    .foregroundStyle(IslandTheme.muted)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
    }

    /// "1 204 contributions cette année · série de 6 jours".
    static func summary(_ calendar: ContributionCalendar) -> String {
        let streak = calendar.streak(today: GitHubContributionsFeed.day(.now))
        let total = calendar.total.formatted(.number.locale(AppLanguage.locale))
        let year = loc("\(total) contributions sur un an")
        guard streak > 0 else { return year }
        return year + " · " + (streak == 1 ? loc("série d'un jour") : loc("série de \(streak) jours"))
    }
}
