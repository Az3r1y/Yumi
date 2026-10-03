import Foundation

/// The date and time at the moment the step runs, in the Mac's time zone.
struct GetCurrentTimeTool: Tool {
    var timeZone: TimeZone = .current

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "get_current_time",
            name: "Current time",
            description: "Returns the current date and time, with the time zone of this Mac.",
            inputSchema: .empty,
            risk: .none,
            outputKeys: ["iso8601", "timeZone"])
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        let iso = formatter.string(from: context.now)
        return ToolOutput(summary: "It is \(iso).",
                          values: ["iso8601": .string(iso), "timeZone": .string(timeZone.identifier)])
    }
}
