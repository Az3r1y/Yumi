import Foundation

/// One thing Claude Code said on its output while answering a message.
enum ChatStreamEvent: Equatable, Sendable {
    /// The turn started; the session identifier is confirmed.
    case started(sessionID: String)
    /// Claude begins a new message: what it writes from here replaces the text shown so far.
    case messageStarted
    /// A few more words of the message being written (partial messages).
    case textDelta(String)
    /// Claude wrote text meant for the user: the complete block, once it is finished.
    case text(String)
    /// Claude is about to use a tool; what it will do with it is not known yet (partial messages).
    case toolAnnounced(id: String, name: String)
    /// Claude starts using a tool.
    case toolStarted(ChatToolUse)
    /// A tool finished. `failed` is true when it was refused or returned an error.
    case toolFinished(id: String, failed: Bool, output: String)
    /// Claude needs a permission before using a tool, and waits for the answer.
    case permissionRequested(ChatPermissionRequest)
    /// A pending permission request was answered by someone else (a hook): no answer is expected any more.
    case permissionCancelled(requestID: String)
    /// The turn is over.
    case finished(ChatTurnResult)
}

struct ChatToolUse: Equatable, Sendable {
    let id: String
    var name: String
    /// The command, the file path or the query, depending on the tool. Empty when there is none.
    var detail: String
    /// What the tool writes, when it writes: the content of the file, or the new text of an edit.
    var content: String = ""
}

struct ChatPermissionRequest: Equatable, Sendable {
    /// Identifier to quote in the answer.
    let requestID: String
    var toolUseID: String
    var toolName: String
    /// What the approval shows: the command for a shell tool, the file for an edit.
    var summary: String
    /// The tool input as received, to be sent back with an approval (Claude Code requires it).
    var inputJSON: Data
    /// The rules Claude Code proposes for "always allow", as received.
    var suggestionsJSON: Data?
}

struct ChatTurnResult: Equatable, Sendable {
    var text: String
    var isError: Bool
    var sessionID: String?
    /// Error messages given outside the text (an unknown session, for instance).
    var errors: [String]
}

enum ChatPermissionDecision: Equatable, Sendable {
    case allow
    /// Allow, and apply the rules Claude Code proposed so the same request is not asked again.
    case allowAlways
    case deny(message: String)

    /// What an answer of the island means. Only the two explicit approvals allow; a refusal,
    /// no answer in time, or anything unexpected refuses.
    init(islandAnswer: String) {
        switch islandAnswer {
        case "allow":  self = .allow
        case "always": self = .allowAlways
        case "deny":   self = .deny(message: ChatPhrases.refusedInNotch)
        default:       self = .deny(message: ChatPhrases.unansweredInNotch)
        }
    }
}

/// Reads and writes the `stream-json` lines exchanged with a `claude -p` process.
enum ClaudeStream {

    // MARK: Reading

    /// The events carried by one line of output. Lines Yumi has no use for (thinking, rate limits,
    /// partial tokens, echoes) give nothing; so does anything that is not JSON.
    static func events(fromLine line: String) -> [ChatStreamEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return [] }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init", let id = object["session_id"] as? String else { return [] }
            return [.started(sessionID: id)]

        case "assistant":
            // What a sub-agent says to its parent is not for the user.
            guard object["parent_tool_use_id"] as? String == nil else { return [] }
            // A message made up by Claude Code itself ("Not logged in"): the result line carries it as an error.
            let message = object["message"] as? [String: Any] ?? [:]
            guard object["error"] == nil, message["model"] as? String != "<synthetic>" else { return [] }
            return blocks(of: message).compactMap { block in
                switch block["type"] as? String {
                case "text":
                    let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.isEmpty ? nil : .text(text)
                case "tool_use":
                    guard let id = block["id"] as? String else { return nil }
                    let name = block["name"] as? String ?? "Tool"
                    let input = block["input"] as? [String: Any] ?? [:]
                    return .toolStarted(ChatToolUse(id: id, name: name, detail: detail(of: input),
                                                    content: input["content"] as? String ?? input["new_string"] as? String ?? ""))
                default:
                    return nil
                }
            }

        case "user":
            guard object["parent_tool_use_id"] as? String == nil else { return [] }
            return blocks(of: object["message"] as? [String: Any] ?? [:]).compactMap { block in
                guard block["type"] as? String == "tool_result", let id = block["tool_use_id"] as? String else { return nil }
                return .toolFinished(id: id, failed: block["is_error"] as? Bool ?? false, output: text(of: block["content"]))
            }

        case "stream_event":
            // Partial messages: the words as they are written, and tools as soon as they are named.
            guard object["parent_tool_use_id"] as? String == nil, let event = object["event"] as? [String: Any] else { return [] }
            switch event["type"] as? String {
            case "message_start":
                return [.messageStarted]
            case "content_block_start":
                guard let block = event["content_block"] as? [String: Any], block["type"] as? String == "tool_use",
                      let id = block["id"] as? String else { return [] }
                return [.toolAnnounced(id: id, name: block["name"] as? String ?? "Tool")]
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String, !text.isEmpty else { return [] }
                return [.textDelta(text)]
            default:
                return []
            }

        case "control_request":
            guard let requestID = object["request_id"] as? String,
                  let request = object["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool" else { return [] }
            let input = request["input"] as? [String: Any] ?? [:]
            let name = request["tool_name"] as? String ?? "Tool"
            return [.permissionRequested(ChatPermissionRequest(
                requestID: requestID,
                toolUseID: request["tool_use_id"] as? String ?? "",
                toolName: name,
                summary: permissionSummary(tool: name, input: input),
                inputJSON: (try? JSONSerialization.data(withJSONObject: input)) ?? Data("{}".utf8),
                suggestionsJSON: (request["permission_suggestions"] as? [Any])
                    .flatMap { try? JSONSerialization.data(withJSONObject: $0) }))]

        case "control_cancel_request":
            guard let requestID = object["request_id"] as? String else { return [] }
            return [.permissionCancelled(requestID: requestID)]

        case "result":
            return [.finished(ChatTurnResult(
                text: (object["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                isError: object["is_error"] as? Bool ?? false,
                sessionID: object["session_id"] as? String,
                errors: object["errors"] as? [String] ?? []))]

        default:
            return []
        }
    }

    /// The text of a tool result, which is either a string or a list of text blocks.
    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        return (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private static func blocks(of message: [String: Any]) -> [[String: Any]] {
        message["content"] as? [[String: Any]] ?? []
    }

    /// The part of a tool input worth showing.
    private static func detail(of input: [String: Any]) -> String {
        for key in ["command", "file_path", "notebook_path", "path", "query", "url", "pattern", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }

    /// What an approval shows. It must be what will run, not what the model says about it: the
    /// command or the path when the tool has one, otherwise the whole input. Always one line,
    /// so nothing hides behind a line break.
    static func permissionSummary(tool: String, input: [String: Any]) -> String {
        for key in ["command", "file_path", "notebook_path", "path", "url", "query", "pattern"] {
            if let value = input[key] as? String, !value.isEmpty { return oneLine(value) }
        }
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) else { return tool }
        return oneLine("\(tool) \(String(decoding: data, as: UTF8.self))")
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ⏎ ")
    }

    /// Among the changes Claude Code proposes with a request, the ones "always" may apply: rules
    /// that allow again what was just shown. Changing the permission mode or opening more folders
    /// would grant more than the user saw, so those are left out.
    static func rulesForAlways(_ suggestions: Data?) -> [[String: Any]] {
        guard let suggestions,
              let all = try? JSONSerialization.jsonObject(with: suggestions) as? [[String: Any]] else { return [] }
        return all.filter { $0["type"] as? String == "addRules" && $0["behavior"] as? String == "allow" }
    }

    // MARK: Writing

    /// The line that sends the user's message.
    static func userLine(_ text: String) -> String {
        line(["type": "user", "message": ["role": "user", "content": [["type": "text", "text": text]]]])
    }

    /// The line that answers a permission request.
    static func answerLine(to request: ChatPermissionRequest, _ decision: ChatPermissionDecision) -> String {
        var response: [String: Any]
        switch decision {
        case .allow, .allowAlways:
            // Claude Code refuses an approval that does not send the input back.
            response = ["behavior": "allow",
                        "updatedInput": (try? JSONSerialization.jsonObject(with: request.inputJSON)) ?? [String: Any]()]
            let rules = rulesForAlways(request.suggestionsJSON)
            if decision == .allowAlways, !rules.isEmpty {
                response["updatedPermissions"] = rules
            }
        case .deny(let message):
            response = ["behavior": "deny", "message": message]
        }
        return line(["type": "control_response",
                     "response": ["subtype": "success", "request_id": request.requestID, "response": response]])
    }

    private static func line(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

/// Cuts a stream of bytes into lines. Bytes arrive in arbitrary chunks; a line is only
/// given once its end has been seen.
struct LineBuffer: Sendable {
    private var pending = Data()

    /// Adds a chunk and returns the lines it completes.
    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let end = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let line = pending[pending.startIndex..<end]
            pending = Data(pending[pending.index(after: end)...])
            if !line.isEmpty { lines.append(String(decoding: line, as: UTF8.self)) }
        }
        return lines
    }

    /// What is left when the stream ends without a final newline.
    mutating func flush() -> String? {
        defer { pending = Data() }
        return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
}
