import SwiftUI
import AppKit

/// The settings section that shows what the Context Engine sees right now, and turns it off.
/// A tool to check the engine by eye, not a feature of the island.
struct ContextDebugPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Observe the front application and window", isOn: $state.contextEnabled)
                .disabled(!LaunchPlan.current.context)
            Text("Stays on this Mac, in memory only. No screen capture, no keystrokes, nothing sent to a model.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let context = state.context
            if context.isEnabled {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    current(context, now: timeline.date)
                }
                if context.accessibility == .notGranted {
                    HStack(spacing: 8) {
                        Text("Window titles need the Accessibility permission.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Open System Settings") { NSWorkspace.shared.open(AccessibilityPermission.settingsURL) }
                            .controlSize(.small)
                    }
                }
                list("RECENT", context.recentApplications.map(\.name))
                list("EVENTS", context.recentEvents.prefix(6).map { "\(Self.time.string(from: $0.date))  \($0.summary)" })
            } else {
                Text(LaunchPlan.current.context ? "Off." : "Off while filming.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func current(_ context: ContextSnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("CURRENT CONTEXT")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Application", context.activeApplication.map { app in
                    let since = context.activeApplicationDuration(at: now).map { " · \(ContextFormat.duration($0))" } ?? ""
                    return app.name + since
                } ?? "None")
                row("Window", window(context))
                row("Previous", context.previousApplication?.name ?? "None")
                row("Session", context.sessionDuration(at: now).map(ContextFormat.duration) ?? "Away")
                row("Activity", context.activity.prefix(3)
                    .map { "\($0.label) \(Int(($0.share * 100).rounded()))%" }
                    .joined(separator: " · ").nonEmpty ?? "Not enough yet")
                row("Yumi", context.presence.rawValue)
            }
        }
    }

    private func window(_ context: ContextSnapshot) -> String {
        switch context.accessibility {
        case .unavailable: return "Not available in this build"
        case .notGranted: return "Not readable"
        case .granted:
            guard let window = context.activeWindow else { return "None" }
            return window.title.isEmpty ? (window.documentPath.map { ($0 as NSString).lastPathComponent } ?? "Untitled") : window.title
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                caption(title)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
