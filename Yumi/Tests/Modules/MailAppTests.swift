import Foundation
import Testing

@Suite struct MailAppTests {
    private let fs = "\u{1F}", rs = "\u{1E}"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ id: String, _ account: String, _ sender: String, _ subject: String,
                        _ ago: Int, read: Bool, flagged: Bool = false, replyTo: String = "") -> String {
        [id, account, sender, subject, String(-ago), read ? "1" : "0", flagged ? "1" : "0", replyTo].joined(separator: fs) + rs
    }

    private var sample: String {
        record("<a@x>", "iCloud", "Léa Martin <lea@icloud.com>", "Point produit", 600, read: false)
        + record("<b@x>", "Pro", "Paul <paul@boite.fr>", "URGENT : contrat à signer", 60, read: false, replyTo: "Juridique <legal@boite.fr>")
        + record("<c@x>", "Gmail", "Newsletter <newsletter@shop.com>", "Urgent : -50 % aujourd'hui", 30, read: false)
        + record("<d@x>", "Pro", "Marc <marc@boite.fr>", "Compte rendu", 7200, read: true, flagged: true)
    }

    @Test func mailOutputBecomesMailsNewestFirst() {
        let mails = MailAppParse.mails(from: sample, now: now)
        #expect(mails.map(\.messageID) == ["<c@x>", "<b@x>", "<a@x>", "<d@x>"])
        let lea = mails[2]
        #expect(lea.from == "Léa Martin")
        #expect(lea.account == "iCloud")
        #expect(lea.subject == "Point produit")
        #expect(lea.unread)
        #expect(lea.date == now.addingTimeInterval(-600))
        #expect(lea.replyAddress == "lea@icloud.com")
        #expect(lea.source == .mailApp)
        #expect(mails[1].replyAddress == "legal@boite.fr")
    }

    @Test func importantApartLikeGmail() {
        let mails = MailAppParse.mails(from: sample, now: now)
        func mail(_ id: String) -> GmailMail { mails.first { $0.messageID == id }! }
        #expect(mail("<b@x>").important)          // unread, urgent subject, a person
        #expect(mail("<d@x>").important)          // flagged
        #expect(!mail("<a@x>").important)
        #expect(!mail("<c@x>").important)         // a newsletter is never important
        #expect(mail("<c@x>").bulk)
        let snapshot = GmailSummary.snapshot(mails: mails, connection: .connected, now: now, source: .mailApp)
        #expect(snapshot.name == "Mail")
        #expect(snapshot.rows.prefix(2).map(\.id) == [String(mail("<b@x>").uid), String(mail("<d@x>").uid)])
        // Several accounts: each row says which
        #expect(snapshot.rows.first?.detail == "Paul · Pro")
    }

    @Test func classifying() {
        #expect(MailClassify.important(flagged: true, unread: false, bulk: false, subject: ""))
        #expect(MailClassify.important(flagged: false, unread: true, bulk: false, subject: "Action required: invoice"))
        #expect(!MailClassify.important(flagged: false, unread: false, bulk: false, subject: "Urgent"))
        #expect(!MailClassify.important(flagged: true, unread: true, bulk: true, subject: "Urgent"))
        #expect(!MailClassify.important(flagged: false, unread: true, bulk: false, subject: "Déjeuner ?"))
    }

    @Test func brokenOrEmptyOutputGivesNoMail() {
        #expect(MailAppParse.mails(from: "", now: now).isEmpty)
        #expect(MailAppParse.mails(from: "garbage" + rs + "a\(fs)b" + rs, now: now).isEmpty)
    }

    @Test func theSameMailKeepsItsNumber() {
        let first = MailAppParse.mails(from: sample, now: now).map(\.uid)
        let again = MailAppParse.mails(from: sample, now: now.addingTimeInterval(120)).map(\.uid)
        #expect(first == again)
        #expect(Set(first).count == first.count)
        #expect(first.allSatisfy { $0 >= 0 })
    }

    @Test func accountFilter() {
        let mails = MailAppParse.mails(from: sample, now: now)
        #expect(MailAccounts.names(in: mails) == ["Gmail", "iCloud", "Pro"])
        #expect(MailAccounts.visible(mails, hidden: ["Pro"]).map(\.account).sorted() == ["Gmail", "iCloud"])
        #expect(MailAccounts.visible(mails, hidden: []).count == 4)
    }

    @Test func mailIsTheDefaultSourceButAConnectedGmailStays() {
        let d = UserDefaults(suiteName: "mail-source-\(UUID().uuidString)")!
        #expect(MailSource.current(in: d, gmailConnected: false) == .mailApp)
        #expect(MailSource.current(in: d, gmailConnected: true) == .gmail)
        d.set("mailApp", forKey: MailSource.defaultsKey)
        #expect(MailSource.current(in: d, gmailConnected: true) == .mailApp)
    }

    @Test func scriptStringsAreEscaped() {
        #expect(MailAppParse.quoted(#"Il a dit "oui" \ ok"#) == #""Il a dit \"oui\" \\ ok""#)
        let draft = MailAppParse.draftScript(to: "lea@icloud.com", subject: "Re: \"Point\"", body: "Merci")
        #expect(draft.contains(#"subject:"Re: \"Point\"""#))
        #expect(!draft.contains("send"))
    }

    @MainActor @Test func closedMailIsAClearEmptyState() async {
        let module = GmailModule(credentials: { nil }, source: { .mailApp },
                                 fetchMailApp: { throw MailAppScript.Failure.closed })
        await module.look()
        #expect(module.snapshot.title == loc("Mail est fermé"))
        #expect(module.snapshot.rows.isEmpty)
        let denied = GmailModule(credentials: { nil }, source: { .mailApp },
                                 fetchMailApp: { throw MailAppScript.Failure.denied })
        await denied.look()
        #expect(denied.snapshot.title == loc("Je n'ai pas accès à Mail"))
    }

    @MainActor @Test func hiddenAccountsAreLeftOutAndNewImportantMailIsTold() async {
        final class Box: @unchecked Sendable { var output = "" }
        let box = Box()
        box.output = record("<a@x>", "iCloud", "Léa <lea@icloud.com>", "Salut", 60, read: false)
        var told: [String] = []
        let module = GmailModule(credentials: { nil }, source: { .mailApp }, hiddenAccounts: { ["Perso"] },
                                 fetchMailApp: { [now] in MailAppParse.mails(from: box.output, now: now) },
                                 onNewMail: { mail, _ in told.append(mail.subject) })
        await module.look()
        #expect(told.isEmpty)
        box.output += record("<b@x>", "iCloud", "Paul <paul@x.fr>", "Urgent : réponse", 10, read: false)
            + record("<c@x>", "Perso", "Max <max@x.fr>", "Urgent aussi", 5, read: false)
        await module.look()
        #expect(told == ["Urgent : réponse"])
        #expect(module.snapshot.rows.count == 2)
    }
}
