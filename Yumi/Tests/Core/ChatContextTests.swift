import Foundation
import Testing

// yumi/contexte-chat: what of the window in front leaves with a chat message.

@Suite struct ChatContextTests {
    private let page = ChatContext.window(app: "Safari", title: "Dossier Martin – contrat", url: "https://mail.example.com/thread/42?client=martin")

    @Test func aDetachedContextGoesNowhere() {
        for explicit in [false, true] {
            #expect(ChatContextPolicy.outgoing(page, attached: false, explicit: explicit) == nil)
            #expect(ChatContextPolicy.outgoing(.file(name: "a.pdf", path: "/x/a.pdf"), attached: false, explicit: explicit) == nil)
        }
        // Every engine builds its message from what this gives: nothing attached, nothing added.
        let message = ChatPhrases.message(query: "Salut", context: ChatContextPolicy.outgoing(page, attached: false, explicit: false))
        #expect(message == "Salut")
        #expect(!message.contains("Safari") && !message.contains("Martin") && !message.contains("example"))
    }

    @Test func withoutAGestureAPageGoesByItsDomainOnly() {
        let sent = ChatContextPolicy.outgoing(page, attached: true, explicit: false)
        #expect(sent == .window(app: "Safari", title: "Dossier Martin – contrat", url: "mail.example.com"))
        let message = ChatPhrases.message(query: "Salut", context: sent)
        #expect(message.contains("mail.example.com"))
        #expect(!message.contains("/thread/42") && !message.contains("client=martin") && !message.contains("https://"))
        #expect(ChatContextPolicy.domain(of: "not a url") == nil)
        #expect(ChatContextPolicy.outgoing(.window(app: "Notes", title: "Courses", url: nil), attached: true, explicit: false)
                == .window(app: "Notes", title: "Courses", url: nil))
    }

    @Test func aGestureKeepsWhatItAlwaysSent() {
        #expect(ChatContextPolicy.outgoing(page, attached: true, explicit: true) == page)
        let file = ChatContext.file(name: "devis.pdf", path: "/Users/moi/Library/Application Support/Yumi/inbox/devis.pdf")
        #expect(ChatContextPolicy.outgoing(file, attached: true, explicit: true) == file)
        #expect(ChatPhrases.message(query: "Résume", context: page).contains("https://mail.example.com/thread/42"))
    }
}
