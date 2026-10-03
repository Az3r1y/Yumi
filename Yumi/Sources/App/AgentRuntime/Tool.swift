import Foundation

/// Something the runtime can do for a step of a plan. A tool describes itself (`descriptor`)
/// and does one thing (`execute`). It never decides whether it may run: the executor checks
/// the policy and asks the `PermissionManager` before calling it.
///
/// `execute` runs away from the main actor and must honour task cancellation.
protocol Tool: Sendable {
    var descriptor: ToolDescriptor { get }
    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput
    /// What a call with these arguments would do, for the permission system. nil when the tool
    /// cannot say: its risk then decides alone, and nothing remembered can cover it.
    func action(for arguments: ToolArguments) -> ToolAction?
    /// Checks, after a successful call, that the effect is really there (the file exists and
    /// holds what was asked). nil when it is, otherwise why not. Reads only: it never repairs.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String?
    /// What can be known before asking the person: a refused place, a folder Yumi cannot
    /// reach, a file already there. nil when nothing stands in the way, otherwise the reason, in
    /// words for the person. Reads only. Checked again by `execute`: things can change meanwhile.
    func check(_ arguments: ToolArguments) async -> String?
}

extension Tool {
    func action(for arguments: ToolArguments) -> ToolAction? { nil }
    /// A tool that changes nothing has nothing to check beyond its output.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? { nil }
    func check(_ arguments: ToolArguments) async -> String? { nil }

    var id: String { descriptor.id }
    var name: String { descriptor.name }
    var description: String { descriptor.description }
    var inputSchema: ToolInputSchema { descriptor.inputSchema }
    var riskLevel: ToolRisk { descriptor.risk }
}

/// What the runtime and the planner know about a tool, without running it.
struct ToolDescriptor: Equatable, Codable, Sendable {
    /// Lowercase, snake case: `get_current_time`. What a plan refers to.
    var id: String
    var name: String
    /// One sentence for the planner: what it gives back, when it is useful.
    var description: String
    var inputSchema: ToolInputSchema
    /// Set by the code of the tool, never by a plan or a model.
    var risk: ToolRisk
    /// Values every successful output contains. The executor rejects an output without them.
    var outputKeys: [String]
}

/// How much a tool can affect the person. Ordered: each level includes the ones before it.
enum ToolRisk: String, Codable, Sendable, CaseIterable, Comparable {
    /// Reads nothing personal and changes nothing (the time).
    case none
    /// Reads the person's data, on this Mac, without changing it (the current context).
    case read
    /// Changes something on this Mac (a file, a setting). Always asks first.
    case write
    /// Leaves the Mac or cannot be undone (send, publish, pay, delete). Always asks first.
    case external

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    static func < (lhs: ToolRisk, rhs: ToolRisk) -> Bool { lhs.order < rhs.order }
}

/// A scalar argument or output value. Plans carry nothing else: no nested objects, no code.
enum ToolValue: Equatable, Sendable, Codable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Only strings, numbers and booleans are accepted")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }

    var description: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): String(value)
        }
    }

    var type: ToolInputSchema.FieldType {
        switch self {
        case .string: .string
        case .number: .number
        case .bool: .bool
        }
    }
}

typealias ToolArguments = [String: ToolValue]

/// The arguments a tool accepts. Kept flat on purpose: a field has a name, a type, and is
/// required or not. Anything not declared is refused.
struct ToolInputSchema: Equatable, Codable, Sendable {
    enum FieldType: String, Codable, Sendable { case string, number, bool }

    struct Field: Equatable, Codable, Sendable {
        var name: String
        var type: FieldType
        var required: Bool
        var description: String
    }

    var fields: [Field]

    static let empty = ToolInputSchema(fields: [])

    /// Why the arguments do not fit, or nil when they do.
    func problem(with arguments: ToolArguments) -> String? {
        for key in arguments.keys.sorted() where !fields.contains(where: { $0.name == key }) {
            return "unknown argument \(key)"
        }
        for field in fields {
            guard let value = arguments[field.name] else {
                if field.required { return "missing argument \(field.name)" }
                continue
            }
            if value.type != field.type { return "\(field.name) must be a \(field.type.rawValue)" }
        }
        return nil
    }
}

/// What a tool gives back: one readable sentence and a few named values.
struct ToolOutput: Equatable, Codable, Sendable {
    var summary: String
    var values: [String: ToolValue]

    init(summary: String, values: [String: ToolValue] = [:]) {
        self.summary = summary
        self.values = values
    }
}

/// What a tool receives besides its arguments. Only what the request already carried: a tool
/// never gets the runtime, the registry, the permissions, or a way to capture more context.
struct ToolContext: Sendable {
    var runID: UUID
    var stepID: String
    /// The snapshot given with the request, nil when there was none.
    var snapshot: ContextSnapshot?
    var now: Date
}

/// How a tool reports that it could not do its job. Any other error counts as `failed`.
enum ToolError: Error, Equatable, Sendable {
    /// The arguments are wrong. Trying again would not help.
    case invalidInput(String)
    /// Not possible right now (busy, offline). Worth another try.
    case unavailable(String)
    /// It went wrong. Trying again would not help.
    case failed(String)
}
