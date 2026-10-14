import AppKit

// The mails of Apple's Mail app: its unified inbox, read through Apple Events, every account the
// person set up in Mail (Gmail, iCloud, Outlook, work), and no password given to Yumi. Read only:
// nothing is marked, moved or sent. An answer becomes a draft opened in Mail, sent by the person.

/// Where the mails come from. Mail is the default; Gmail with an app password stays an option.
enum MailSource: String, CaseIterable, Sendable {
    case mailApp, gmail

    static let defaultsKey = "mail.source"

    /// Mail needs Apple Events, which the App Store build does not have.
    static var mailAppAvailable: Bool {
        #if APPSTORE
        return false
        #else
        return true
        #endif
    }

    /// The person's choice. Someone who had already connected Gmail before this choice existed
    /// keeps Gmail; everyone else starts with Mail.
    static func current(in defaults: UserDefaults = .standard, gmailConnected: Bool) -> MailSource {
        guard mailAppAvailable else { return .gmail }
        if let raw = defaults.string(forKey: defaultsKey), let source = MailSource(rawValue: raw) { return source }
        return gmailConnected ? .gmail : .mailApp
    }
}

/// Which mails count as important, for every source: flagged, or unread with an urgent subject,
/// and never a newsletter or an automatic mail. Gmail adds its own "important" label.
enum MailClassify {
    static let urgentWords = ["urgent", "important", "asap", "action requise", "action required", "deadline",
                              "échéance", "rappel", "reminder", "relance", "aujourd'hui", "today"]

    static func important(flagged: Bool, unread: Bool, bulk: Bool, subject: String) -> Bool {
        guard !bulk else { return false }
        if flagged { return true }
        let lower = subject.lowercased()
        return unread && urgentWords.contains { lower.contains($0) }
    }
}

/// The accounts of the mails, and the filter of the settings. Pure.
enum MailAccounts {
    static let hiddenKey = "mail.hiddenAccounts"

    /// Each account once, in alphabetical order; the empty name is left out.
    static func names(in mails: [GmailMail]) -> [String] {
        Array(Set(mails.map(\.account).filter { !$0.isEmpty })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The mails of the accounts the person kept.
    static func visible(_ mails: [GmailMail], hidden: Set<String>) -> [GmailMail] {
        hidden.isEmpty ? mails : mails.filter { !hidden.contains($0.account) }
    }

    static func hidden(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }
}

/// Reading what the script below prints. Pure.
enum MailAppParse {
    static let field: Character = "\u{1F}"
    static let record: Character = "\u{1E}"

    /// One record per mail: message id, account, sender, subject, seconds from now (negative),
    /// read (1 or 0), flagged (1 or 0), reply-to. Newest first.
    static func mails(from output: String, now: Date) -> [GmailMail] {
        output.split(separator: record, omittingEmptySubsequences: true).compactMap { line -> GmailMail? in
            let parts = line.split(separator: field, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 7 else { return nil }
            let messageID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let account = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let sender = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
            let date = Double(parts[4].trimmingCharacters(in: .whitespaces)).map { now.addingTimeInterval($0) }
            let unread = parts[5].trimmingCharacters(in: .whitespaces) != "1"
            let flagged = parts[6].trimmingCharacters(in: .whitespaces) == "1"
            let replyTo = parts.count > 7 ? GmailParse.address(parts[7]) : ""
            let address = GmailParse.address(sender)
            let bulk = GmailParse.isAutomatic(address)
            var mail = GmailMail(uid: stableID(messageID.isEmpty ? account + sender + subject + parts[4] : messageID),
                                 from: GmailParse.sender(sender), subject: subject, date: date, unread: unread, thread: nil)
            mail.account = account
            mail.bulk = bulk
            mail.important = MailClassify.important(flagged: flagged, unread: unread, bulk: bulk, subject: subject)
            mail.replyAddress = replyTo.isEmpty ? address : replyTo
            mail.messageID = messageID
            mail.source = .mailApp
            return mail
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// The same number for the same mail at every look (FNV-1a), positive.
    static func stableID(_ text: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return Int(truncatingIfNeeded: hash & UInt64(Int.max))
    }

    /// A text for an AppleScript string literal.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// The script that lists the latest `count` mails of each account's inbox. "NOACCOUNT" when
    /// Mail has no account. Mail answers slowly on a large inbox (a few seconds to a minute for
    /// 40 000 mails, mostly to find the range): each account costs ONE Apple Event that brings
    /// every property at once, never one event per mail.
    static func listScript(count: Int) -> String {
        """
        tell application "Mail"
            if (count of accounts) is 0 then return "NOACCOUNT"
            set fs to character id 31
            set rs to character id 30
            set out to ""
            set now to current date
            repeat with mb in (mailboxes of inbox)
                set acc to ""
                try
                    set acc to name of account of mb
                end try
                set total to count of messages of mb
                if total > 0 then
                    set n to total
                    if n > \(count) then set n to \(count)
                    set p to {message id, sender, subject, date received, read status, flagged status, reply to} of messages 1 thru n of mb
                    repeat with i from 1 to n
                        set r to "0"
                        if item i of item 5 of p then set r to "1"
                        set fl to "0"
                        if item i of item 6 of p then set fl to "1"
                        set rt to item i of item 7 of p
                        if rt is missing value then set rt to ""
                        set out to out & (item i of item 1 of p) & fs & acc & fs & (item i of item 2 of p) & fs & (item i of item 3 of p) & fs & ((item i of item 4 of p) - now) & fs & r & fs & fl & fs & rt & rs
                    end repeat
                end if
            end repeat
            return out
        end tell
        """
    }

    static func textScript(messageID: String) -> String {
        """
        tell application "Mail"
            set found to (messages of inbox whose message id is \(quoted(messageID)))
            if (count of found) is 0 then return ""
            return content of (item 1 of found)
        end tell
        """
    }

    /// A new message, filled in and opened in Mail: the person reads it and sends it, or not.
    static func draftScript(to address: String, subject: String, body: String) -> String {
        """
        tell application "Mail"
            set draft to make new outgoing message with properties {subject:\(quoted(subject)), content:\(quoted(body)), visible:true}
            tell draft to make new to recipient at end of to recipients with properties {address:\(quoted(address))}
            activate
        end tell
        """
    }
}

/// Talking to Mail through Apple Events, one script at a time, off the main thread.
enum MailAppScript {
    enum Failure: Error, Equatable { case closed, denied, noAccount, failed, timedOut }

    /// How long a script may take before the module stops waiting.
    static let timeout: TimeInterval = 90

    static let bundleID = "com.apple.mail"
    private static let queue = DispatchQueue(label: "app.yumi.mail-app")
    /// errAEEventNotPermitted: the person said no in the Automation prompt.
    private static let notAuthorized = -1743

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Runs a script. Never starts Mail to read: a closed Mail is an empty state, not an error.
    static func run(_ source: String, startingMail: Bool = false) async throws -> String {
        #if APPSTORE
        throw Failure.denied
        #else
        guard startingMail || isRunning else { throw Failure.closed }
        // An Apple Event can wait for ever: the Automation prompt left unanswered, Mail busy
        // with its own setup. The module gives up after `timeout`; the script ends on its own.
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                guard once.claim() else { return }
                if let error {
                    let code = error[NSAppleScript.errorNumber] as? Int
                    continuation.resume(throwing: code == notAuthorized ? Failure.denied : code == -600 ? Failure.closed : Failure.failed)
                } else {
                    continuation.resume(returning: output?.stringValue ?? "")
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { continuation.resume(throwing: Failure.timedOut) }
            }
        }
        #endif
    }

    static func latest(count: Int = 10) async throws -> [GmailMail] {
        let output = try await run(MailAppParse.listScript(count: count))
        if output == "NOACCOUNT" { throw Failure.noAccount }
        return MailAppParse.mails(from: output, now: Date())
    }

    static func text(of mail: GmailMail) async throws -> String {
        let raw = try await run(MailAppParse.textScript(messageID: mail.messageID))
        return GmailParse.readableText(raw)
    }

    /// Opens the answer as a draft in Mail. Mail does not send it: the person does.
    static func openDraft(to address: String, subject: String, body: String) async throws {
        _ = try await run(MailAppParse.draftScript(to: address, subject: subject, body: body), startingMail: true)
    }

    static func openMail() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
