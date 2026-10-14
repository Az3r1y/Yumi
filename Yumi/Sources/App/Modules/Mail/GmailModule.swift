import AppKit
import Network

/// A read-only conversation with Gmail's IMAP server (imap.gmail.com, TLS): log in with an app
/// password, look at the inbox without touching it (EXAMINE), read the headers of the latest
/// mails, log out. Nothing is ever written, moved or marked read.
final class GmailIMAP: @unchecked Sendable {
    enum Failure: Error, Equatable { case connection, refused, answer }

    private let connection: NWConnection
    private var buffer = Data()
    private var tag = 0

    init(host: String = "imap.gmail.com") {
        connection = NWConnection(host: NWEndpoint.Host(host), port: 993, using: .tls)
    }

    /// The latest `count` mails of the inbox, newest first.
    static func latest(address: String, password: String, count: Int = 8) async throws -> [GmailMail] {
        let session = GmailIMAP()
        defer { session.connection.cancel() }
        try await session.open()
        _ = try await session.untagged()
        let login = try await session.command("LOGIN \(quoted(address)) \(quoted(password))")
        guard login.ok else { throw Failure.refused }
        let inbox = try await session.command("EXAMINE INBOX")
        guard inbox.ok, let total = GmailParse.exists(in: String(decoding: inbox.data, as: UTF8.self)) else { throw Failure.answer }
        guard total > 0 else { return [] }
        let first = max(1, total - count + 1)
        let fetch = try await session.command("FETCH \(first):\(total) (UID FLAGS X-GM-THRID X-GM-LABELS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE REPLY-TO MESSAGE-ID LIST-UNSUBSCRIBE)])")
        guard fetch.ok else { throw Failure.answer }
        _ = try? await session.command("LOGOUT")
        return GmailParse.mails(fromFetch: fetch.data)
    }

    /// The readable text of one mail, its first few thousand bytes, without marking it read.
    static func text(of uid: Int, address: String, password: String) async throws -> String {
        let session = GmailIMAP()
        defer { session.connection.cancel() }
        try await session.open()
        _ = try await session.untagged()
        guard try await session.command("LOGIN \(quoted(address)) \(quoted(password))").ok else { throw Failure.refused }
        guard try await session.command("EXAMINE INBOX").ok else { throw Failure.answer }
        let answer = try await session.command("UID FETCH \(uid) (BODY.PEEK[TEXT]<0.12000>)")
        _ = try? await session.command("LOGOUT")
        guard answer.ok else { throw Failure.answer }
        let raw = String(decoding: answer.data, as: UTF8.self)
        // The literal: everything after the first "{n}\r\n"
        guard let open = raw.range(of: "}\r\n") else { return "" }
        return GmailParse.readableText(String(raw[open.upperBound...]))
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // MARK: The wire

    private func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            connection.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready: once.done = true; continuation.resume()
                case .failed, .cancelled: once.done = true; continuation.resume(throwing: Failure.connection)
                case .waiting: once.done = true; continuation.resume(throwing: Failure.connection)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
                if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if error != nil || complete { continuation.resume(throwing: Failure.connection) }
                else { continuation.resume(returning: Data()) }
            }
        }
    }

    /// The greeting the server sends first.
    private func untagged() async throws -> Data {
        while !buffer.contains(Array("\r\n".utf8)) { buffer += try await receive() }
        let data = buffer
        buffer = Data()
        return data
    }

    /// Sends one command, waits for its tagged answer. `ok` is false for NO and BAD.
    private func command(_ text: String) async throws -> (ok: Bool, data: Data) {
        tag += 1
        let name = "y\(tag)"
        let line = Data("\(name) \(text)\r\n".utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: line, completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: Failure.connection) } else { continuation.resume() }
            })
        }
        let marker = Array("\r\n\(name) ".utf8)
        let start = Array("\(name) ".utf8)
        var waited = 0
        while true {
            let bytes = [UInt8](buffer)
            if let at = Self.lineStart(of: marker, start: start, in: bytes),
               let end = Self.index(of: Array("\r\n".utf8), in: bytes, from: at) {
                let status = String(decoding: bytes[at..<end], as: UTF8.self)
                let data = Data(bytes[0..<end])
                buffer = Data(bytes[(end + 2)...])
                return (status.hasPrefix("\(name) OK"), data)
            }
            buffer += try await receive()
            waited += 1
            if waited > 4000 { throw Failure.answer }
        }
    }

    private static func lineStart(of marker: [UInt8], start: [UInt8], in bytes: [UInt8]) -> Int? {
        if bytes.starts(with: start) { return 0 }
        return index(of: marker, in: bytes, from: 0).map { $0 + 2 }
    }

    private static func index(of needle: [UInt8], in bytes: [UInt8], from: Int) -> Int? {
        guard bytes.count >= needle.count, from <= bytes.count - needle.count else { return nil }
        for i in from...(bytes.count - needle.count) where bytes[i] == needle[0] && Array(bytes[i..<i + needle.count]) == needle {
            return i
        }
        return nil
    }
}

/// The mails the island can answer: the module keeps it up to date, the sheet reads it.
@MainActor
final class GmailInbox: ObservableObject {
    static let shared = GmailInbox()
    @Published private(set) var mails: [GmailMail] = []
    /// Every account seen in the inbox, filtered or not: the settings list them.
    @Published private(set) var accounts: [String] = []
    func show(_ mails: [GmailMail]) { if mails != self.mails { self.mails = mails } }
    func showAccounts(_ accounts: [String]) { if accounts != self.accounts { self.accounts = accounts } }
}

/// The mails module: the latest mails of the inbox, unread ones first in the figures. Read from
/// Apple's Mail app (every account set up there, no password), or from Gmail with an app
/// password kept in the Keychain; asked every two minutes while the module is selected.
/// Its id stays "gmail" so the settings and the place of the module carry over.
@MainActor
final class GmailModule: YumiModule {
    let id = "gmail"
    var category: ModuleCategory { .day }

    static let pollInterval: TimeInterval = 120
    static let addressKey = "gmail.address"
    static let passwordKey = "gmail-app-password"

    enum Connection: Equatable {
        case notSet, connected, refused, offline
        /// Mail is the source but is not open, has no account, or the person refused the access.
        case mailClosed, mailNoAccount, mailDenied
    }

    private let credentials: @MainActor () -> (address: String, password: String)?
    private let source: @MainActor () -> MailSource
    private let hiddenAccounts: @MainActor () -> Set<String>
    private let fetch: @Sendable (String, String) async throws -> [GmailMail]
    private let fetchMailApp: @Sendable () async throws -> [GmailMail]
    private let onNewMail: @MainActor (GmailMail, Int) -> Void
    /// Opens the settings, where the address and the app password go.
    private let onConnect: @MainActor () -> Void
    private var onChange: (@MainActor () -> Void)?
    private var polling: Task<Void, Never>?
    private var rowObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var mails: [GmailMail] = []
    private var connection = Connection.notSet
    /// The mails already seen, to notice the ones that arrive. nil until the first look.
    private var seen: Set<Int>?
    private var currentSource = MailSource.mailApp

    init(credentials: @escaping @MainActor () -> (address: String, password: String)?,
         source: @escaping @MainActor () -> MailSource = { .gmail },
         hiddenAccounts: @escaping @MainActor () -> Set<String> = { [] },
         fetch: @escaping @Sendable (String, String) async throws -> [GmailMail] = { try await GmailIMAP.latest(address: $0, password: $1) },
         fetchMailApp: @escaping @Sendable () async throws -> [GmailMail] = { try await MailAppScript.latest() },
         onNewMail: @escaping @MainActor (GmailMail, Int) -> Void = { _, _ in },
         onConnect: @escaping @MainActor () -> Void = {}) {
        self.credentials = credentials
        self.source = source
        self.hiddenAccounts = hiddenAccounts
        self.fetchMailApp = fetchMailApp
        self.onConnect = onConnect
        self.fetch = fetch
        self.onNewMail = onNewMail
    }

    var snapshot: ModuleSnapshot {
        GmailSummary.snapshot(mails: mails, connection: connection, now: Date(), source: currentSource)
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        rowObserver = NotificationCenter.default.addObserver(forName: .moduleRowAction, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["module"] as? String == "gmail", let row = note.userInfo?["row"] as? String else { return }
            MainActor.assumeIsolated { self?.open(row) }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .gmailSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
        restart()
    }

    func stop() {
        onChange = nil
        polling?.cancel()
        polling = nil
        for observer in [rowObserver, settingsObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
        rowObserver = nil
        settingsObserver = nil
    }

    private func restart() {
        polling?.cancel()
        seen = nil
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.look()
                try? await Task.sleep(for: .seconds(GmailModule.pollInterval), tolerance: .seconds(10))
            }
        }
    }

    /// One look at the inbox. Internal so tests can drive it.
    func look() async {
        let source = source()
        if source != currentSource { currentSource = source; seen = nil; mails = [] }
        do {
            let all: [GmailMail]
            switch source {
            case .mailApp:
                all = try await fetchMailApp()
            case .gmail:
                guard let credentials = credentials() else {
                    connection = .notSet
                    show([])
                    onChange?()
                    return
                }
                all = try await fetch(credentials.address, credentials.password)
            }
            connection = .connected
            GmailInbox.shared.showAccounts(MailAccounts.names(in: all))
            let latest = MailAccounts.visible(all, hidden: hiddenAccounts())
            if let seen {
                // Only what matters gets a word: the important mails, never a newsletter
                let arrived = latest.filter { !seen.contains($0.uid) && $0.unread && $0.important }
                if let first = arrived.first { onNewMail(first, arrived.count) }
            }
            seen = (seen ?? []).union(all.map(\.uid))
            show(latest)
        } catch GmailIMAP.Failure.refused {
            connection = .refused
        } catch MailAppScript.Failure.closed {
            connection = .mailClosed
            show([])
        } catch MailAppScript.Failure.noAccount {
            connection = .mailNoAccount
            show([])
        } catch MailAppScript.Failure.denied {
            connection = .mailDenied
            show([])
        } catch {
            if mails.isEmpty { connection = .offline }
        }
        onChange?()
    }

    private func show(_ latest: [GmailMail]) {
        mails = latest
        GmailInbox.shared.show(latest)
    }

    func perform(_ action: ModuleAction) {
        switch connection {
        case .notSet, .refused, .mailDenied, .mailNoAccount:
            onConnect()
        case .mailClosed:
            MailAppScript.openMail()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                await self?.look()
            }
        default:
            if currentSource == .mailApp { MailAppScript.openMail() }
            else if let url = URL(string: "https://mail.google.com/mail/u/0/#inbox") { NSWorkspace.shared.open(url) }
        }
    }

    private func open(_ row: String) {
        guard let uid = Int(row), let mail = mails.first(where: { $0.uid == uid }) else { return }
        if mail.source == .mailApp {
            // message:// opens the mail itself in Mail
            let id = mail.messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            if let url = URL(string: "message://%3C" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id) + "%3E") {
                NSWorkspace.shared.open(url)
            }
        } else if let url = mail.url {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notification.Name {
    /// The source, the accounts shown, or Gmail's address or app password changed in the settings.
    static let gmailSettingsChanged = AppIdentity.notification("gmailSettingsChanged")
}

/// What the island shows of the inbox.
enum GmailSummary {
    static func snapshot(mails: [GmailMail], connection: GmailModule.Connection, now: Date,
                         source: MailSource = .gmail) -> ModuleSnapshot {
        let mailApp = source == .mailApp
        var snapshot = ModuleSnapshot(id: "gmail", name: mailApp ? "Mail" : "Gmail", colorHex: mailApp ? "#3E8BFF" : "#EA4335",
                                      status: "", title: "", subtitle: "",
                                      primaryAction: mailApp ? loc("Ouvrir Mail") : loc("Ouvrir Gmail"), secondaryAction: nil)
        snapshot.symbol = "envelope.fill"
        snapshot.primarySymbol = "arrow.up.forward"
        switch connection {
        case .notSet:
            snapshot.title = loc("Branche ta boîte Gmail")
            snapshot.subtitle = loc("Dans Réglages, Modules : ton adresse et un mot de passe d'application.")
            snapshot.primaryAction = loc("Brancher")
            snapshot.primarySymbol = "link"
            return snapshot
        case .refused:
            snapshot.title = loc("Gmail refuse le mot de passe")
            snapshot.subtitle = loc("Il faut un mot de passe d'application de 16 lettres, pas ton mot de passe Google : Réglages, Modules.")
            snapshot.primaryAction = loc("Réglages")
            return snapshot
        case .mailClosed:
            snapshot.title = loc("Mail est fermé")
            snapshot.subtitle = loc("Ouvre l'app Mail et je lis ta boîte de réception, sans rien y toucher.")
            snapshot.primaryAction = loc("Ouvrir Mail")
            return snapshot
        case .mailNoAccount:
            snapshot.title = loc("Aucun compte dans Mail")
            snapshot.subtitle = loc("Ajoute ton compte dans l'app Mail, ou choisis Gmail dans Réglages, Modules.")
            snapshot.primaryAction = loc("Réglages")
            return snapshot
        case .mailDenied:
            snapshot.title = loc("Je n'ai pas accès à Mail")
            snapshot.subtitle = loc("Réglages Système, Confidentialité, Automatisation : autorise Yumi à contrôler Mail.")
            snapshot.primaryAction = loc("Réglages")
            return snapshot
        case .offline where mails.isEmpty:
            snapshot.title = mailApp ? loc("Mail ne répond pas") : loc("Gmail ne répond pas")
            snapshot.subtitle = loc("Je réessaie dans deux minutes.")
            return snapshot
        case .connected, .offline:
            break
        }
        let unread = mails.filter(\.unread).count
        let important = mails.filter { $0.important && $0.unread }.count
        snapshot.status = important > 0 ? loc("\(important) importants") : unread == 0 ? loc("à jour") : loc("\(unread) non lus")
        snapshot.needsAttention = important > 0
        // The important ones first, then the others, newest first in each
        let mails = mails.filter(\.important) + mails.filter { !$0.important }
        if let latest = mails.first {
            snapshot.title = latest.subject.isEmpty ? loc("(sans objet)") : latest.subject
            snapshot.subtitle = latest.from
        } else {
            snapshot.title = loc("Boîte vide")
        }
        let several = MailAccounts.names(in: mails).count > 1
        snapshot.rows = mails.map { mail in
            ModuleRow(id: String(mail.uid), title: mail.subject.isEmpty ? loc("(sans objet)") : mail.subject,
                      detail: several && !mail.account.isEmpty ? "\(mail.from) · \(mail.account)" : mail.from,
                      state: mail.important && mail.unread ? .waiting : mail.unread ? .busy : .neutral,
                      label: mail.date.map { when($0, now: now) } ?? "",
                      date: mail.date, action: String(mail.uid))
        }
        return snapshot
    }

    /// "14:02" today, "hier", or "13 oct.".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return FrenchText.clock(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return loc("hier") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// Sends one mail through Gmail's SMTP server (smtp.gmail.com, TLS), from the person's
/// address, with the same app password. Only called by the "Envoyer" button of a reply the
/// person read: nothing is ever sent on its own.
final class GmailSMTP: @unchecked Sendable {
    enum Failure: Error, Equatable { case connection, refused, rejected(String) }

    private let connection = NWConnection(host: "smtp.gmail.com", port: 465, using: .tls)
    private var buffer = ""

    static func send(from address: String, password: String, to recipient: String, subject: String,
                     inReplyTo messageID: String, body: String) async throws {
        let smtp = GmailSMTP()
        defer { smtp.connection.cancel() }
        try await smtp.open()
        try await smtp.expect("220")
        try await smtp.say("EHLO yumi.local", expect: "250")
        let plain = Data("\0\(address)\0\(password)".utf8).base64EncodedString()
        do { try await smtp.say("AUTH PLAIN \(plain)", expect: "235") } catch { throw Failure.refused }
        try await smtp.say("MAIL FROM:<\(address)>", expect: "250")
        try await smtp.say("RCPT TO:<\(recipient)>", expect: "250")
        try await smtp.say("DATA", expect: "354")
        let message = GmailCompose.message(from: address, to: recipient, subject: subject, inReplyTo: messageID, body: body)
        try await smtp.say(message + "\r\n.", expect: "250")
        try? await smtp.say("QUIT", expect: "221")
    }

    private func open() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            connection.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready: once.done = true; continuation.resume()
                case .failed, .cancelled, .waiting: once.done = true; continuation.resume(throwing: Failure.connection)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func say(_ line: String, expect code: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: Failure.connection) } else { continuation.resume() }
            })
        }
        try await expect(code)
    }

    /// Reads one reply (its last line is "250 ..." with a space) and checks its code.
    private func expect(_ code: String) async throws {
        while true {
            let lines = buffer.components(separatedBy: "\r\n")
            if let last = lines.dropLast().last(where: { $0.count >= 4 && $0[$0.index($0.startIndex, offsetBy: 3)] == " " }) {
                buffer = ""
                guard last.hasPrefix(code) else { throw Failure.rejected(last) }
                return
            }
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
                    if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else if error != nil || complete { continuation.resume(throwing: Failure.connection) }
                    else { continuation.resume(returning: Data()) }
                }
            }
            buffer += String(decoding: data, as: UTF8.self)
        }
    }
}

/// Writing the answer as a mail. Pure.
enum GmailCompose {
    /// "Re: Point produit", without piling up "Re: Re:".
    static func replySubject(_ subject: String) -> String {
        subject.lowercased().hasPrefix("re:") ? subject : "Re: " + subject
    }

    /// The whole message: headers, then the text, lines starting with a dot doubled.
    static func message(from: String, to: String, subject: String, inReplyTo: String, body: String) -> String {
        var headers = [
            "From: <\(from)>",
            "To: <\(to)>",
            "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: 8bit",
        ]
        if !inReplyTo.isEmpty {
            headers.append("In-Reply-To: \(inReplyTo)")
            headers.append("References: \(inReplyTo)")
        }
        let text = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.hasPrefix(".") ? "." + $0 : $0 }
            .joined(separator: "\r\n")
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + text
    }
}
