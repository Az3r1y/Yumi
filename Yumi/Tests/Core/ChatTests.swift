import Testing
import Foundation

// The chat's pure half (Core/Chat): finding and launching Claude Code, reading its output,
// answering its permission requests. The sample lines are real output of claude 2.1.185,
// shortened.

@Suite struct ClaudeCLITests {
    private let home = "/Users/moi"

    @Test func findsTheBinaryInTheUsualFoldersWhenThePathIsBare() {
        let finderPath = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        func locate(_ present: Set<String>) -> String? {
            ClaudeCLI.locate(environment: finderPath, home: home, isExecutable: present.contains)
        }
        #expect(locate(["/opt/homebrew/bin/claude"]) == "/opt/homebrew/bin/claude")
        #expect(locate(["/usr/local/bin/claude"]) == "/usr/local/bin/claude")
        #expect(locate(["/Users/moi/.claude/local/claude"]) == "/Users/moi/.claude/local/claude")
        #expect(locate(["/Users/moi/.local/bin/claude"]) == "/Users/moi/.local/bin/claude")
        #expect(locate([]) == nil)
        // Several installs: the order of the list decides.
        #expect(locate(["/Users/moi/.local/bin/claude", "/opt/homebrew/bin/claude"]) == "/opt/homebrew/bin/claude")
    }

    @Test func thePathOfTheAppComesFirst() {
        let found = ClaudeCLI.locate(environment: ["PATH": "/custom/bin:/usr/bin"], home: home,
                                     isExecutable: ["/custom/bin/claude", "/opt/homebrew/bin/claude"].contains)
        #expect(found == "/custom/bin/claude")
        #expect(ClaudeCLI.locate(environment: [:], home: home, isExecutable: { _ in false }) == nil)
    }

    @Test func argumentsOfAFirstMessage() {
        let arguments = ClaudeCLI.arguments(session: .new("11111111-2222-4333-8444-555555555555"), systemPrompt: "Tu es Yumi.")
        #expect(arguments == ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                              "--include-partial-messages",
                              "--permission-prompt-tool", "stdio", "--permission-mode", "default",
                              "--session-id", "11111111-2222-4333-8444-555555555555",
                              "--append-system-prompt", "Tu es Yumi."])
    }

    @Test func laterMessagesResumeTheSession() {
        let arguments = ClaudeCLI.arguments(session: .resume("abc"), systemPrompt: "p",
                                            readableFolders: ["/inbox"], extra: ["--model", "haiku"])
        #expect(arguments.contains("--resume"))
        #expect(!arguments.contains("--session-id"))
        #expect(Array(arguments.suffix(4)) == ["--add-dir", "/inbox", "--model", "haiku"])
    }

    @Test func noArgumentEverSkipsPermissions() {
        let all = ClaudeCLI.arguments(session: .new("id"), systemPrompt: "p") + ClaudeCLI.arguments(session: .resume("id"), systemPrompt: "p")
        #expect(!all.contains { $0.contains("dangerously") || $0 == "bypassPermissions" || $0 == "acceptEdits" || $0 == "dontAsk" })
        let mode = all.firstIndex(of: "--permission-mode").map { all[$0 + 1] }
        #expect(mode == "default")
    }

    @Test func theEnvironmentGetsAPathAndLosesBilledCredentials() {
        let base = ["PATH": "/usr/bin:/bin", "HOME": home, "ANTHROPIC_API_KEY": "sk-secret", "ANTHROPIC_AUTH_TOKEN": "t",
                    "CLAUDECODE": "1", "CLAUDE_CODE_ENTRYPOINT": "cli", "LANG": "fr_FR.UTF-8"]
        let environment = ClaudeCLI.environment(from: base, binary: "/Users/moi/.local/bin/claude", home: home)
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["ANTHROPIC_AUTH_TOKEN"] == nil)
        #expect(environment["CLAUDECODE"] == nil)
        #expect(environment["CLAUDE_CODE_ENTRYPOINT"] == nil)
        #expect(environment["LANG"] == "fr_FR.UTF-8")
        #expect(environment["HOME"] == home)
        let path = environment["PATH"]!.split(separator: ":").map(String.init)
        #expect(Array(path.prefix(2)) == ["/usr/bin", "/bin"])
        for folder in ["/opt/homebrew/bin", "/usr/local/bin", "/Users/moi/.local/bin", "/usr/sbin", "/sbin"] {
            #expect(path.contains(folder))
        }
        #expect(Set(path).count == path.count)
    }

    @Test func theChatFolder() {
        // By default, where files usually arrive: the Downloads folder the system reports.
        #expect(ChatFolder.path(stored: nil, home: home, downloads: "/Users/moi/Downloads") == "/Users/moi/Downloads")
        #expect(ChatFolder.path(stored: "  ", home: home, downloads: "/Volumes/x/Téléchargements") == "/Volumes/x/Téléchargements")
        #expect(ChatFolder.downloads == FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
        #expect(ChatFolder.path(stored: nil) == ChatFolder.downloads)
        #expect(ChatFolder.path(stored: "~/dev/projet", home: home) == "/Users/moi/dev/projet")
        #expect(ChatFolder.path(stored: "~", home: home) == home)
        #expect(ChatFolder.path(stored: "/Volumes/travail", home: home) == "/Volumes/travail")
        #expect(ChatFolder.key == "chatFolder")
    }

    @Test func theRegistryRemembersChatSessions() {
        let registry = ChatSessionRegistry()
        #expect(!registry.contains("a"))
        registry.insert("a")
        #expect(registry.contains("a"))
        registry.remove("a")
        #expect(!registry.contains("a"))
    }
}

@Suite struct ClaudeStreamTests {
    private let initLine = #"{"type":"system","subtype":"init","cwd":"/tmp/x","session_id":"1fa56d39-e14f-478a-b74b-6730fae02f82","tools":["Bash","Read","Write"],"mcp_servers":[],"model":"claude-haiku-4-5-20251001","permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.185"}"#
    private let textLine = #"{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"msg_01","type":"message","role":"assistant","content":[{"type":"text","text":"ok"}],"stop_reason":null},"parent_tool_use_id":null,"session_id":"1fa56d39","uuid":"94713a96"}"#
    private let thinkingLine = #"{"type":"assistant","message":{"id":"msg_01","role":"assistant","content":[{"type":"thinking","thinking":"The user asks...","signature":"Eqk"}]},"parent_tool_use_id":null,"session_id":"1fa56d39"}"#
    private let toolUseLine = #"{"type":"assistant","message":{"id":"msg_02","role":"assistant","content":[{"type":"tool_use","id":"toolu_012Tj","name":"Write","input":{"file_path":"/tmp/x/hello.txt","content":"hi"},"caller":{"type":"direct"}}]},"parent_tool_use_id":null,"session_id":"a0311b65"}"#
    private let toolResultLine = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_012Tj","type":"tool_result","content":"File created successfully at: /tmp/x/hello.txt"}]},"parent_tool_use_id":null,"session_id":"a0311b65","tool_use_result":{"type":"create","filePath":"/tmp/x/hello.txt"}}"#
    private let deniedResultLine = #"{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01HzQ","type":"tool_result","is_error":true,"content":"Refused by the user"}]},"parent_tool_use_id":null,"session_id":"a0311b65"}"#
    private let controlLine = #"{"type":"control_request","request_id":"86a8a41b-1","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"touch made-by-bash.txt","description":"Create a file"},"description":"Create a file","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch made-by-bash.txt"}],"behavior":"allow","destination":"localSettings"}],"blocked_path":"/tmp/x/made-by-bash.txt","tool_use_id":"toolu_018QG"}}"#
    private let cancelLine = #"{"type":"control_cancel_request","request_id":"86a8a41b-1"}"#
    private let resultLine = #"{"type":"result","subtype":"success","is_error":false,"duration_ms":1546,"num_turns":1,"result":"ok\n","stop_reason":"end_turn","session_id":"1fa56d39-e14f-478a-b74b-6730fae02f82","total_cost_usd":0.0146,"permission_denials":[],"terminal_reason":"completed"}"#

    @Test func theTurnStartsWithItsSession() {
        #expect(ClaudeStream.events(fromLine: initLine) == [.started(sessionID: "1fa56d39-e14f-478a-b74b-6730fae02f82")])
    }

    @Test func textIsKeptAndThinkingIsNot() {
        #expect(ClaudeStream.events(fromLine: textLine) == [.text("ok")])
        #expect(ClaudeStream.events(fromLine: thinkingLine).isEmpty)
    }

    @Test func aToolIsFollowedFromStartToEnd() {
        #expect(ClaudeStream.events(fromLine: toolUseLine)
                == [.toolStarted(ChatToolUse(id: "toolu_012Tj", name: "Write", detail: "/tmp/x/hello.txt", content: "hi"))])
        #expect(ClaudeStream.events(fromLine: toolResultLine)
                == [.toolFinished(id: "toolu_012Tj", failed: false, output: "File created successfully at: /tmp/x/hello.txt")])
        #expect(ClaudeStream.events(fromLine: deniedResultLine) == [.toolFinished(id: "toolu_01HzQ", failed: true, output: "Refused by the user")])
    }

    @Test func aPermissionRequestCarriesWhatTheAnswerNeeds() throws {
        let events = ClaudeStream.events(fromLine: controlLine)
        guard case .permissionRequested(let request)? = events.first, events.count == 1 else {
            Issue.record("Expected one permission request")
            return
        }
        #expect(request.requestID == "86a8a41b-1")
        #expect(request.toolUseID == "toolu_018QG")
        #expect(request.toolName == "Bash")
        #expect(request.summary == "touch made-by-bash.txt")
        let input = try JSONSerialization.jsonObject(with: request.inputJSON) as? [String: String]
        #expect(input == ["command": "touch made-by-bash.txt", "description": "Create a file"])
        #expect(request.suggestionsJSON != nil)
        #expect(ClaudeStream.events(fromLine: cancelLine) == [.permissionCancelled(requestID: "86a8a41b-1")])
    }

    @Test func theResultEndsTheTurn() {
        #expect(ClaudeStream.events(fromLine: resultLine)
                == [.finished(ChatTurnResult(text: "ok", isError: false, sessionID: "1fa56d39-e14f-478a-b74b-6730fae02f82", errors: []))])
    }

    @Test func errorsComeInTwoShapes() {
        // Not logged in: a made-up assistant line that must not be shown as an answer, then an error result.
        let synthetic = #"{"type":"assistant","message":{"id":"aaf0","model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"Not logged in · Please run /login"}]},"parent_tool_use_id":null,"session_id":"7a05","error":"authentication_failed"}"#
        #expect(ClaudeStream.events(fromLine: synthetic).isEmpty)
        let loggedOut = #"{"type":"result","subtype":"success","is_error":true,"num_turns":1,"result":"Not logged in · Please run /login","session_id":"7a05"}"#
        guard case .finished(let first)? = ClaudeStream.events(fromLine: loggedOut).first else { Issue.record("no result"); return }
        #expect(first.isError)
        #expect(ChatPhrases.failure(first) == ChatPhrases.notLoggedIn)
        #expect(!ChatPhrases.isUnknownSession(first))

        // Unknown session: no text, the message is in "errors".
        let unknown = #"{"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":0,"session_id":"8098","errors":["No conversation found with session ID: 8098"]}"#
        guard case .finished(let second)? = ClaudeStream.events(fromLine: unknown).first else { Issue.record("no result"); return }
        #expect(second.text.isEmpty)
        #expect(ChatPhrases.isUnknownSession(second))
    }

    @Test func everythingElseIsIgnored() {
        let ignored = [
            #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"},"session_id":"1fa5"}"#,
            #"{"type":"system","subtype":"thinking_tokens","estimated_tokens":108,"session_id":"1fa5"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"The user"}}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"sub-agent"}},"parent_tool_use_id":"toolu_parent"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_stop","index":1}}"#,
            #"{"type":"control_response","response":{"subtype":"success","request_id":"init_1","response":{}}}"#,
            #"{"type":"control_request","request_id":"x","request":{"subtype":"something_new"}}"#,
            // What a sub-agent says and does is its parent's business.
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"sub-agent talking"}]},"parent_tool_use_id":"toolu_parent"}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"toolu_sub"}]},"parent_tool_use_id":"toolu_parent"}"#,
            #"{"type":"user","message":{"role":"user","content":"[Your previous response had no visible output.]"},"isSynthetic":true}"#,
            "Error: something on a line that is not JSON",
            "",
            "[1, 2, 3]",
        ]
        for line in ignored { #expect(ClaudeStream.events(fromLine: line).isEmpty, "\(line)") }
    }

    // MARK: Writing

    private func object(_ line: String) throws -> [String: Any] {
        #expect(line.hasSuffix("\n"))
        #expect(!line.dropLast().contains("\n"))
        return try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    @Test func theUserLine() throws {
        let sent = try object(ClaudeStream.userLine("Crée un fichier \"notes.txt\"\nmerci"))
        #expect(sent["type"] as? String == "user")
        let message = try #require(sent["message"] as? [String: Any])
        #expect(message["role"] as? String == "user")
        let content = try #require(message["content"] as? [[String: String]])
        #expect(content == [["type": "text", "text": "Crée un fichier \"notes.txt\"\nmerci"]])
    }

    private var request: ChatPermissionRequest {
        guard case .permissionRequested(let request)? = ClaudeStream.events(fromLine: controlLine).first else {
            fatalError("sample line must parse")
        }
        return request
    }

    @Test func anApprovalSendsTheInputBack() throws {
        let answer = try object(ClaudeStream.answerLine(to: request, .allow))
        #expect(answer["type"] as? String == "control_response")
        let envelope = try #require(answer["response"] as? [String: Any])
        #expect(envelope["subtype"] as? String == "success")
        #expect(envelope["request_id"] as? String == "86a8a41b-1")
        let response = try #require(envelope["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "allow")
        #expect(response["updatedInput"] as? [String: String] == ["command": "touch made-by-bash.txt", "description": "Create a file"])
        #expect(response["updatedPermissions"] == nil)
    }

    @Test func alwaysAddsTheProposedRules() throws {
        let answer = try object(ClaudeStream.answerLine(to: request, .allowAlways))
        let response = try #require((answer["response"] as? [String: Any])?["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "allow")
        #expect(response["updatedInput"] != nil)
        let rules = try #require(response["updatedPermissions"] as? [[String: Any]])
        #expect(rules.first?["type"] as? String == "addRules")

        // Without a proposal, "always" is a plain approval.
        var bare = request
        bare.suggestionsJSON = nil
        let plain = try object(ClaudeStream.answerLine(to: bare, .allowAlways))
        #expect(((plain["response"] as? [String: Any])?["response"] as? [String: Any])?["updatedPermissions"] == nil)
    }

    @Test func aRefusalCarriesItsReason() throws {
        let answer = try object(ClaudeStream.answerLine(to: request, .deny(message: ChatPhrases.refusedInNotch)))
        let response = try #require((answer["response"] as? [String: Any])?["response"] as? [String: Any])
        #expect(response["behavior"] as? String == "deny")
        #expect(response["message"] as? String == ChatPhrases.refusedInNotch)
        #expect(response["updatedInput"] == nil)
    }

    // MARK: Lines

    @Test func linesAreRebuiltFromArbitraryChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        #expect(buffer.append(Data("1}\n{\"b\":2}\n{\"c\"".utf8)) == ["{\"a\":1}", "{\"b\":2}"])
        #expect(buffer.append(Data(":3}\n\n".utf8)) == ["{\"c\":3}"])
        #expect(buffer.flush() == nil)
        #expect(buffer.append(Data("sans fin".utf8)).isEmpty)
        #expect(buffer.flush() == "sans fin")
        #expect(buffer.flush() == nil)
    }

    @Test func aCharacterCutBetweenTwoChunksSurvives() {
        let bytes = Array("{\"t\":\"café\"}\n".utf8)
        var buffer = LineBuffer()
        let cut = bytes.firstIndex(of: 0xC3)! + 1   // inside the two bytes of "é"
        #expect(buffer.append(Data(bytes[..<cut])).isEmpty)
        #expect(buffer.append(Data(bytes[cut...])) == ["{\"t\":\"café\"}"])
    }
}

@Suite struct ChatPhrasesTests {
    @Test func theMessageCarriesWhatWasAttached() {
        #expect(ChatPhrases.message(query: "Résume", context: nil) == "Résume")
        #expect(ChatPhrases.message(query: "Résume", context: .window(app: "Safari", title: "Open-Meteo", url: "https://open-meteo.com"))
                == "[Contexte joint : fenêtre de Safari, « Open-Meteo », https://open-meteo.com]\n\nRésume")
        #expect(ChatPhrases.message(query: "Résume", context: .window(app: "Notes", title: "", url: nil))
                == "[Contexte joint : fenêtre de Notes]\n\nRésume")
        #expect(ChatPhrases.message(query: "Résume", context: .file(name: "devis.pdf", path: "/inbox/devis.pdf"))
                == "[Fichier joint : /inbox/devis.pdf]\n\nRésume")
        #expect(ChatPhrases.message(query: "Résume", context: .file(name: "devis.pdf", path: nil))
                == "[Fichier joint : devis.pdf]\n\nRésume")
    }

    @Test func eachActionGetsItsLine() {
        func line(_ name: String, _ detail: String, _ outcome: ChatToolOutcome = .done) -> String? {
            ChatPhrases.action(ChatToolUse(id: "t", name: name, detail: detail), outcome: outcome)
        }
        #expect(line("Write", "/Users/moi/Documents/Yumi/notes.txt") == "Fichier créé : notes.txt")
        #expect(line("Edit", "/a/b/main.swift") == "Fichier modifié : main.swift")
        #expect(line("Bash", "swift build") == "Commande lancée : swift build")
        #expect(line("WebSearch", "météo Paris") == "Recherche web : météo Paris")
        #expect(line("WebFetch", "https://open-meteo.com/en/docs") == "Page lue : open-meteo.com")
        #expect(line("Bash", "swift build", .failed) == "Commande en échec : swift build")
        #expect(line("Bash", "rm -rf build", .refused) == "Commande refusée : rm -rf build")
        #expect(line("Write", "/a/notes.txt", .refused) == "Écriture refusée : notes.txt")
        #expect(line("Write", "/a/notes.txt", .failed) == "Fichier non écrit : notes.txt")
        #expect(line("mcp__x__send", "", .refused) == "Action refusée : mcp__x__send")
    }

    @Test func lookingIsNotAnAction() {
        for name in ["Read", "Grep", "Glob", "LS", "TodoWrite", "ToolSearch"] {
            #expect(ChatPhrases.action(ChatToolUse(id: "t", name: name, detail: "x"), outcome: .done) == nil)
            #expect(ChatPhrases.action(ChatToolUse(id: "t", name: name, detail: "x"), outcome: .failed) == nil)
        }
    }

    @Test func longCommandsAreCutToOneLine() {
        let long = String(repeating: "a", count: 200) + "\nsecond line"
        let line = ChatPhrases.action(ChatToolUse(id: "t", name: "Bash", detail: long), outcome: .done)!
        #expect(!line.contains("\n"))
        #expect(line.hasSuffix("…"))
        #expect(line.count == "Commande lancée : ".count + 60)
    }

    @Test func failures() {
        #expect(ChatPhrases.failure(ChatTurnResult(text: "", isError: true, sessionID: nil, errors: [])) == ChatPhrases.stopped)
        #expect(ChatPhrases.failure(ChatTurnResult(text: "Invalid API key · Please run /login", isError: true, sessionID: nil, errors: []))
                == ChatPhrases.notLoggedIn)
        #expect(ChatPhrases.failure(ChatTurnResult(text: "API Error: 529 overloaded", isError: true, sessionID: nil, errors: []))
                == "Claude Code a rencontré une erreur : API Error: 529 overloaded")
        #expect(ChatPhrases.notInstalled.contains("claude.ai/install.sh"))
        #expect(!ChatPhrases.notInstalled.contains("\n"))
    }

    @Test func theSystemPromptNamesTheFolderAndForbidsWorkarounds() {
        let prompt = ChatPhrases.systemPrompt(characterName: "Yumi", folder: "/Users/moi/Documents/Yumi")
        #expect(prompt.contains("Yumi"))
        #expect(prompt.contains("/Users/moi/Documents/Yumi"))
        #expect(prompt.contains("contourner"))
    }
}

@Suite struct ChatPermissionTests {
    @Test func onlyAnExplicitApprovalAllows() {
        #expect(ChatPermissionDecision(islandAnswer: "allow") == .allow)
        #expect(ChatPermissionDecision(islandAnswer: "always") == .allowAlways)
        #expect(ChatPermissionDecision(islandAnswer: "deny") == .deny(message: ChatPhrases.refusedInNotch))
        for other in ["ask", "", "ALLOW", "yes", "allow "] {
            #expect(ChatPermissionDecision(islandAnswer: other) == .deny(message: ChatPhrases.unansweredInNotch))
        }
    }

    @Test func alwaysOnlyKeepsRulesForWhatWasShown() {
        let suggestions = Data(#"[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch x.txt"}],"behavior":"allow","destination":"localSettings"},{"type":"addDirectories","directories":["/Users/moi"],"destination":"session"},{"type":"setMode","mode":"acceptEdits","destination":"session"}]"#.utf8)
        let rules = ClaudeStream.rulesForAlways(suggestions)
        #expect(rules.count == 1)
        #expect(rules.first?["type"] as? String == "addRules")
        // Only a change of mode proposed: "always" is then a plain approval.
        #expect(ClaudeStream.rulesForAlways(Data(#"[{"type":"setMode","mode":"acceptEdits","destination":"session"}]"#.utf8)).isEmpty)
        #expect(ClaudeStream.rulesForAlways(nil).isEmpty)
    }

    @Test func theSummaryShowsWhatWillRun() {
        #expect(ClaudeStream.permissionSummary(tool: "Bash", input: ["command": "echo ok\nrm -rf ~/x", "description": "Print ok"])
                == "echo ok ⏎ rm -rf ~/x")
        #expect(ClaudeStream.permissionSummary(tool: "Write", input: ["file_path": "/a/b.txt", "content": "x"]) == "/a/b.txt")
        // No known key: the input itself, never the description the model wrote.
        #expect(ClaudeStream.permissionSummary(tool: "mcp__mail__send", input: ["description": "harmless", "to": "x@y.z"])
                == #"mcp__mail__send {"description":"harmless","to":"x@y.z"}"#)
        #expect(ClaudeStream.permissionSummary(tool: "Task", input: [:]) == "Task")
    }

    @Test func foldersAreComparedByComponents() {
        #expect(ChatFolder.contains("/Users/moi/Library/Yumi/inbox/a.pdf", in: "/Users/moi/Library/Yumi/inbox"))
        #expect(ChatFolder.contains("/Users/moi/Library/Yumi/inbox", in: "/Users/moi/Library/Yumi/inbox"))
        #expect(!ChatFolder.contains("/Users/moi/Library/Yumi/inbox-old/a.pdf", in: "/Users/moi/Library/Yumi/inbox"))
        #expect(!ChatFolder.contains("/Users/moi/Library/Yumi/inbox/../secret.txt", in: "/Users/moi/Library/Yumi/inbox"))
    }
}
