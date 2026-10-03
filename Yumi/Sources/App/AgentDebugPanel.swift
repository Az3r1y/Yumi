import SwiftUI

/// The settings section that shows what the agent runtime is doing, and lets a developer start
/// or stop a run. A tool to check the runtime by eye, not a feature of the island: it only
/// reads `RuntimeAgent` and calls its public methods.
struct AgentDebugPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let agent = state.agent {
            AgentDebugContent(agent: agent, state: state)
        } else {
            Text("Off while filming.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

private struct AgentDebugContent: View {
    let agent: RuntimeAgent
    @ObservedObject var state: AppState
    @State private var intent = ""
    /// Off unless the person ticks it, for this request only.
    @State private var shareContext = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Works only when asked. Plans with Claude Code (no tools, your Claude Code login) or else the Anthropic key above; creating a file always asks first. What is on screen stays on the Mac unless you tick the box.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("What should Yumi do?", text: $intent)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(run)
                Button("Run", action: run)
                    .disabled(agent.isRunning || intent.nonEmptyTrimmed == nil)
            }
            Toggle("Show the model what is on screen (application, window, document name)", isOn: $shareContext)
                .font(.system(size: 11))
                .disabled(!state.context.isEnabled)
            HStack(spacing: 8) {
                Button("Check tools", action: checkTools)
                    .disabled(agent.isRunning)
                Button("Cancel") { agent.cancel() }
                    .disabled(!agent.isRunning)
            }
            .controlSize(.small)

            current
            events
        }
    }

    private var current: some View {
        let run = agent.current
        return VStack(alignment: .leading, spacing: 6) {
            caption("CURRENT AGENT")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("Planner", agent.planner.name)
                row("Tools", agent.availableTools.map { "\($0.id) (\($0.risk.rawValue))" }.joined(separator: ", "))
                row("Goal", run?.goal ?? run.map { $0.task.request.trimmedIntent } ?? "None")
                row("Status", "\(agent.state.rawValue) · \(agent.activity.rawValue)")
                row("Step", step(run?.task))
                if let error = run?.result?.error { row("Error", error.message) }
            }
            if let task = run?.task, task.plan != nil {
                ProgressView(value: task.progress)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var events: some View {
        let recent = (agent.current?.events ?? []).suffix(8).reversed()
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                caption("RECENT EVENTS")
                ForEach(Array(recent)) { event in
                    Text("\(Self.time.string(from: event.date))  \(event.summary)")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private func step(_ task: RuntimeTask?) -> String {
        guard let task, let plan = task.plan else { return "None" }
        let done = plan.steps.filter { $0.status.isFinished }.count
        guard let step = task.currentStep else { return "\(done)/\(plan.steps.count)" }
        let attempt = step.attempts > 1 ? ", try \(step.attempts)" : ""
        return "\(done)/\(plan.steps.count) · \(step.id): \(step.description) (\(step.status.rawValue)\(attempt))"
    }

    /// The context goes with the request only now, because the person asked; it reaches the
    /// model only when the box is ticked.
    private func run() {
        guard !agent.isRunning, intent.nonEmptyTrimmed != nil else { return }
        let request = AgentRequest(userIntent: intent, context: state.context.isEnabled ? state.context : nil,
                                   sharesContextWithModel: shareContext && state.context.isEnabled)
        Task { await agent.run(request) }
    }

    private func checkTools() {
        guard let plan = AgentPlan.toolCheck(agent.availableTools) else { return }
        let request = AgentRequest(userIntent: plan.goal, context: state.context.isEnabled ? state.context : nil)
        Task { await agent.execute(plan, for: request) }
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
