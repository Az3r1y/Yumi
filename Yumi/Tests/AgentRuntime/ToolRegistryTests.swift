import Testing
import Foundation

@Suite struct ToolRegistryTests {
    @Test func registersAndFindsTools() throws {
        let registry = try ToolRegistry([FakeTool(id: "first"), FakeTool(id: "second", risk: .read)])
        #expect(registry.contains("first"))
        #expect(registry.tool(id: "second")?.riskLevel == .read)
        #expect(registry.tool(id: "third") == nil)
        #expect(registry.descriptors.map(\.id) == ["first", "second"])
    }

    @Test func refusesTheSameIdentifierTwice() {
        #expect(throws: ToolRegistry.RegistrationError.duplicate("same")) {
            try ToolRegistry([FakeTool(id: "same"), FakeTool(id: "same")])
        }
    }

    @Test func refusesIdentifiersAPlanCouldNotNameSafely() {
        for id in ["", "Upper", "with space", "1starts_with_digit", "dash-ed", String(repeating: "a", count: 65)] {
            #expect(throws: ToolRegistry.RegistrationError.invalidIdentifier(id)) { try ToolRegistry([FakeTool(id: id)]) }
        }
        #expect(ToolRegistry.isValidIdentifier("get_current_time"))
    }

    @Test func thePolicyHidesToolsAboveItsCeiling() throws {
        let registry = try ToolRegistry([FakeTool(id: "time"), FakeTool(id: "context", risk: .read),
                                         FakeTool(id: "write_file", risk: .write), FakeTool(id: "send_mail", risk: .external)])
        #expect(registry.descriptors(allowedBy: AgentPolicy()).map(\.id) == ["time", "context"])
        #expect(registry.descriptors(allowedBy: AgentPolicy(maximumRisk: .write)).map(\.id) == ["time", "context", "write_file"])
    }

    @Test func theStandardToolsOnlyRead() {
        let standard = ToolRegistry.standard
        #expect(standard.descriptors.map(\.id) == ["get_current_time", "get_current_context"])
        #expect(standard.descriptors.allSatisfy { $0.risk <= .read })
        #expect(standard.tool(id: "get_current_time")?.riskLevel == ToolRisk.none)
        #expect(standard.tool(id: "get_current_context")?.riskLevel == .read)
    }

    @Test func aSchemaRefusesWhatItDoesNotDeclare() {
        let schema = ToolInputSchema(fields: [
            .init(name: "path", type: .string, required: true, description: "A file"),
            .init(name: "limit", type: .number, required: false, description: "How many"),
        ])
        #expect(schema.problem(with: ["path": .string("a")]) == nil)
        #expect(schema.problem(with: ["path": .string("a"), "limit": .number(3)]) == nil)
        #expect(schema.problem(with: [:]) == "missing argument path")
        #expect(schema.problem(with: ["path": .number(1)]) == "path must be a string")
        #expect(schema.problem(with: ["path": .string("a"), "force": .bool(true)]) == "unknown argument force")
    }

    @Test func toolValuesAreScalarsOnly() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(ToolValue.self, from: Data("true".utf8)) == .bool(true))
        #expect(try decoder.decode(ToolValue.self, from: Data("2.5".utf8)) == .number(2.5))
        #expect(try decoder.decode(ToolValue.self, from: Data(#""x""#.utf8)) == .string("x"))
        #expect(throws: DecodingError.self) { try decoder.decode(ToolValue.self, from: Data(#"{"a": 1}"#.utf8)) }
        #expect(throws: DecodingError.self) { try decoder.decode(ToolValue.self, from: Data("[1]".utf8)) }
    }

    @Test func riskLevelsAreOrdered() {
        #expect(ToolRisk.none < .read && ToolRisk.read < .write && ToolRisk.write < .external)
    }
}

@Suite struct StandardToolsTests {
    private func context(_ snapshot: ContextSnapshot?) -> ToolContext {
        ToolContext(runID: UUID(), stepID: "step-1", snapshot: snapshot, now: Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func currentTimeGivesTheMomentOfTheStep() async throws {
        let tool = GetCurrentTimeTool(timeZone: TimeZone(identifier: "Europe/Paris")!)
        let output = try await tool.execute([:], in: context(nil))
        #expect(output.values["iso8601"] == .string("2026-09-21T16:13:20+02:00"))
        #expect(output.values["timeZone"] == .string("Europe/Paris"))
    }

    @Test func currentContextGivesOnlyWhatIsInFront() async throws {
        let output = try await GetCurrentContextTool().execute([:], in: context(editorSnapshot()))
        #expect(output.values["available"] == .bool(true))
        #expect(output.values["application"] == .string("Visual Studio Code"))
        #expect(output.values["document"] == .string("main.swift"))
        #expect(output.values["previousApplication"] == .string("Terminal"))
        // Neither the folder of the file nor the other recent applications leave the runtime.
        let all = output.values.values.map(\.description).joined(separator: " ") + output.summary
        #expect(!all.contains("/Users/someone"))
        #expect(!all.contains("PrivateDiary"))
    }

    @Test func currentContextSaysSoWhenThereIsNone() async throws {
        for snapshot in [nil, ContextSnapshot.disabled()] {
            let output = try await GetCurrentContextTool().execute([:], in: context(snapshot))
            #expect(output.values == ["available": .bool(false)])
        }
    }
}
