import Foundation

/// The tools the runtime may use, by identifier. Built once by whoever creates the runtime:
/// neither a plan nor a model can add a tool to it.
struct ToolRegistry: Sendable {
    enum RegistrationError: Error, Equatable, Sendable {
        case duplicate(String)
        case invalidIdentifier(String)
    }

    private var tools: [String: any Tool] = [:]
    /// Registration order, so that the planner always sees the tools in the same order.
    private var order: [String] = []

    init() {}

    init(_ tools: [any Tool]) throws(RegistrationError) {
        for tool in tools { try register(tool) }
    }

    /// The tools Yumi has today: they only read, and only what the request already carries.
    static let standard: ToolRegistry = {
        var registry = ToolRegistry()
        try? registry.register(GetCurrentTimeTool())
        try? registry.register(GetCurrentContextTool())
        return registry
    }()

    mutating func register(_ tool: any Tool) throws(RegistrationError) {
        let id = tool.descriptor.id
        guard Self.isValidIdentifier(id) else { throw .invalidIdentifier(id) }
        guard tools[id] == nil else { throw .duplicate(id) }
        tools[id] = tool
        order.append(id)
    }

    func tool(id: String) -> (any Tool)? { tools[id] }

    func contains(_ id: String) -> Bool { tools[id] != nil }

    var isEmpty: Bool { order.isEmpty }

    /// Every tool, in registration order.
    var descriptors: [ToolDescriptor] { order.compactMap { tools[$0]?.descriptor } }

    /// The tools a policy lets the runtime use at all.
    func descriptors(allowedBy policy: AgentPolicy) -> [ToolDescriptor] {
        descriptors.filter { $0.risk <= policy.maximumRisk }
    }

    /// `get_current_time`: lowercase letters, digits and underscores, starting with a letter.
    static func isValidIdentifier(_ id: String) -> Bool {
        guard let first = id.unicodeScalars.first, ("a"..."z").contains(first), id.count <= 64 else { return false }
        return id.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }
}
