import Foundation

/// Runs an accepted plan, one step after the other. For each step it checks the tool against
/// the registry and the policy again, asks the `PermissionManager` (every step, silently when it
/// is safe), runs the tool with a time limit, checks its output, and applies the
/// `RecoveryPolicy` when something goes wrong. Then it verifies the whole.
///
/// It never throws and never stops the app: whatever happens, it returns the task in a
/// finished state (completed, failed or cancelled) with its result.
@MainActor
struct AgentExecutor {
    let tools: ToolRegistry
    let permissions: any PermissionManager
    let policy: AgentPolicy
    let recovery: RecoveryPolicy
    let verifier: any AgentVerifier
    let clock: @Sendable () -> Date
    /// Waits before a retry. Injected by the tests.
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    /// Called after every change of the task, with the event it caused if any.
    typealias Publish = @MainActor (RuntimeTask, AgentEvent.Kind?) -> Void

    func execute(_ task: RuntimeTask, publish: @escaping Publish) async -> RuntimeTask {
        let ended = await perform(task, publish: publish)
        // However the run ended, nothing it was allowed for itself alone can be used again.
        await permissions.finishRun(task.id)
        return ended
    }

    private func perform(_ task: RuntimeTask, publish: @escaping Publish) async -> RuntimeTask {
        let run = Run(task: task, publish: publish)
        guard let plan = task.plan, !plan.steps.isEmpty else {
            return run.end(.failed, error: .invalidPlan("there is no plan"), at: clock())
        }
        var retriesUsed = 0

        steps: for index in plan.steps.indices {
            if Task.isCancelled { return run.end(.cancelled, error: .cancelled, at: clock()) }
            run.task.currentStepIndex = index
            let step = run.step(index)

            // The plan was checked when it was made; the registry and the policy decide again here.
            guard let tool = tools.tool(id: step.toolID) else {
                return run.fail(index, .unknownTool(step.toolID), at: clock())
            }
            let descriptor = tool.descriptor
            guard policy.allows(descriptor.risk) else {
                return run.fail(index, .toolNotAllowed(tool: descriptor.id, risk: descriptor.risk), at: clock())
            }
            if let problem = descriptor.inputSchema.problem(with: step.arguments) {
                return run.fail(index, .invalidArguments(tool: descriptor.id, reason: problem), at: clock())
            }

            // Every step goes through the permission manager, whatever its risk: a safe step comes
            // back allowed at once and silently, so asking costs nothing and nothing can skip it.
            let request = permissionRequest(for: step, tool: tool, in: task, goal: plan.goal)
            let upcoming = plan.steps[(index + 1)...].compactMap { next -> AgentPermissionRequest? in
                guard let nextTool = tools.tool(id: next.toolID), policy.allows(nextTool.descriptor.risk),
                      nextTool.descriptor.inputSchema.problem(with: next.arguments) == nil else { return nil }
                return permissionRequest(for: next, tool: nextTool, in: task, goal: plan.goal)
            }
            let decision: PermissionDecision
            switch await permissions.evaluate(request, upcoming: upcoming) {
            case .allow:
                decision = .granted
            case .deny(let reason):
                // The policy says never: the step fails and, unless it is optional, the run stops.
                let error = AgentError.permissionDenied(tool: descriptor.id, reason: reason)
                if step.isOptional {
                    run.update(index, event: .stepSkipped(stepID: step.id)) {
                        $0.status = .skipped
                        $0.error = error
                    }
                    continue steps
                }
                return run.fail(index, error, at: clock())
            case .ask(let approval):
                run.update(index, state: .awaitingApproval, event: .approvalRequired(request)) {
                    $0.status = .awaitingApproval
                    $0.requiresApproval = true
                }
                let answer = await permissions.decision(on: approval)
                if Task.isCancelled { return run.end(.cancelled, error: .cancelled, at: clock()) }
                if answer == .granted {
                    run.update(index, event: .approvalGranted(stepID: step.id)) { $0.status = .pending }
                }
                decision = answer
            }
            if Task.isCancelled { return run.end(.cancelled, error: .cancelled, at: clock()) }

            switch decision {
            case .granted:
                break
            case .cancelled:
                return run.end(.cancelled, error: .cancelled, at: clock())
            case .expired:
                // Nothing runs on an approval nobody gave. Asking again is a new run.
                let error = AgentError.approvalExpired(tool: descriptor.id)
                run.update(index, event: .approvalExpired(stepID: step.id)) { $0.error = error }
                return run.end(.cancelled, error: error, at: clock())
            case .denied(let reason):
                run.update(index, event: .approvalDenied(stepID: step.id, reason: reason)) { _ in }
                let error = AgentError.permissionDenied(tool: descriptor.id, reason: reason)
                let action = recovery.decide(after: error, attempt: 1, retriesUsed: retriesUsed, optional: step.isOptional)
                switch action {
                case .skip:
                    run.update(index, event: .stepSkipped(stepID: step.id)) {
                        $0.status = .skipped
                        $0.error = error
                    }
                    continue steps
                case .retry, .cancel:
                    // Asking again would only insist: a refusal ends the run.
                    run.update(index) { $0.error = error }
                    return run.end(.cancelled, error: error, at: clock())
                case .fail:
                    return run.fail(index, error, at: clock())
                }
            }

            var attempt = 0
            while true {
                attempt += 1
                run.update(index, state: .executing, event: .stepStarted(stepID: step.id, attempt: attempt)) {
                    $0.status = .executing
                    $0.attempts = attempt
                    $0.error = nil
                }
                let context = ToolContext(runID: task.id, stepID: step.id, snapshot: task.request.context, now: clock())
                let outcome = await Self.invoke(tool, step.arguments, in: context, timeout: recovery.stepTimeout)
                if Task.isCancelled { return run.end(.cancelled, error: .cancelled, at: clock()) }

                let error: AgentError
                switch outcome {
                case .success(let output):
                    if let problem = Self.problem(with: output, of: descriptor) {
                        error = .outputRejected(tool: descriptor.id, reason: problem)
                    } else {
                        run.update(index, event: .stepCompleted(stepID: step.id, summary: output.summary)) {
                            $0.status = .completed
                            $0.output = output
                        }
                        continue steps
                    }
                case .failure(let failure):
                    error = failure
                }

                let action = recovery.decide(after: error, attempt: attempt, retriesUsed: retriesUsed, optional: step.isOptional)
                run.update(index, event: .stepFailed(stepID: step.id, error: error, recovery: action)) { $0.error = error }
                switch action {
                case .retry:
                    retriesUsed += 1
                    do { try await sleep(recovery.retryDelay * attempt) } catch {}
                    if Task.isCancelled { return run.end(.cancelled, error: .cancelled, at: clock()) }
                case .skip:
                    run.update(index, event: .stepSkipped(stepID: step.id)) { $0.status = .skipped }
                    continue steps
                case .cancel:
                    return run.end(.cancelled, error: error, at: clock())
                case .fail:
                    return run.fail(index, error, at: clock())
                }
            }
        }

        run.task.currentStepIndex = nil
        run.task.state = .verifying
        run.publish(run.task, .verificationStarted)
        if let error = await verifier.verify(run.task) {
            return run.end(.failed, error: error, at: clock())
        }
        if Task.isCancelled { return run.end(.cancelled, error: .cancelled, at: clock()) }
        return run.end(.completed, error: nil, at: clock())
    }

    /// What the permission manager is told about a step. The risk and the action come from the
    /// tool's code; the planner only contributes the reason, shown as such.
    private func permissionRequest(for step: AgentStep, tool: any Tool, in task: RuntimeTask, goal: String) -> AgentPermissionRequest {
        let descriptor = tool.descriptor
        return AgentPermissionRequest(runID: task.id, stepID: step.id, goal: goal, reason: step.description,
                                      toolID: descriptor.id, toolName: descriptor.name, risk: descriptor.risk,
                                      arguments: step.arguments, action: tool.action(for: step.arguments),
                                      requiresApproval: step.requiresApproval || policy.requiresApproval(for: descriptor.risk))
    }

    // MARK: - Running a tool

    /// Runs the tool away from the main actor, stops it after `timeout`, and turns whatever it
    /// throws into an `AgentError`.
    nonisolated private static func invoke(_ tool: any Tool, _ arguments: ToolArguments, in context: ToolContext,
                                           timeout: Duration) async -> Result<ToolOutput, AgentError> {
        let id = tool.descriptor.id
        do {
            let output = try await withThrowingTaskGroup(of: ToolOutput?.self) { group in
                group.addTask { try await tool.execute(arguments, in: context) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
            guard let output else { return .failure(.toolTimedOut(tool: id)) }
            return .success(output)
        } catch let error as ToolError {
            switch error {
            case .invalidInput(let reason): return .failure(.invalidArguments(tool: id, reason: reason))
            case .unavailable(let reason): return .failure(.toolFailed(tool: id, reason: reason, transient: true))
            case .failed(let reason): return .failure(.toolFailed(tool: id, reason: reason, transient: false))
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch {
            return .failure(.toolFailed(tool: id, reason: String(describing: error), transient: false))
        }
    }

    /// Why an output does not keep the tool's promise, or nil.
    private static func problem(with output: ToolOutput, of descriptor: ToolDescriptor) -> String? {
        if output.summary.nonEmptyTrimmed == nil { return "empty summary" }
        if let missing = descriptor.outputKeys.first(where: { output.values[$0] == nil }) { return "missing \(missing)" }
        return nil
    }
}

/// The task being executed and the way to publish its changes.
@MainActor
private final class Run {
    var task: RuntimeTask
    let publish: AgentExecutor.Publish

    init(task: RuntimeTask, publish: @escaping AgentExecutor.Publish) {
        self.task = task
        self.publish = publish
    }

    func step(_ index: Int) -> AgentStep { task.plan!.steps[index] }

    func update(_ index: Int, state: ExecutionState? = nil, event: AgentEvent.Kind? = nil,
                _ change: (inout AgentStep) -> Void) {
        change(&task.plan!.steps[index])
        if let state { task.state = state }
        publish(task, event)
    }

    func fail(_ index: Int, _ error: AgentError, at date: Date) -> RuntimeTask {
        update(index) {
            $0.status = .failed
            $0.error = error
        }
        return end(.failed, error: error, at: date)
    }

    /// Ends the run. The terminal event is the runtime's to publish.
    func end(_ status: AgentResult.Status, error: AgentError?, at date: Date) -> RuntimeTask {
        task.finish(status, error: error, at: date)
        publish(task, nil)
        return task
    }
}
