import AppKit
import SwiftUI

// The Gmail sheet: the important mails first, the rest under them. A mail chosen, Yumi reads it
// and suggests an answer the person can change. "Envoyer" sends it from their address; "Annuler"
// drops it. Nothing leaves without that click.

struct GmailSheet: View {
    @ObservedObject private var inbox = GmailInbox.shared
    @State private var chosen: GmailMail?
    @State private var draft = ""
    @State private var step = Step.reading

    enum Step: Equatable { case reading, thinking, editing, sending, sent, failed(String) }

    private var credentials: (address: String, password: String)? {
        guard let address = UserDefaults.standard.string(forKey: GmailModule.addressKey), !address.isEmpty,
              let password = KeychainStore.shared.get(GmailModule.passwordKey), !password.isEmpty else { return nil }
        return (address, password)
    }

    var body: some View {
        Group {
            if let chosen {
                reply(to: chosen)
            } else {
                list
            }
        }
        // An answer being written keeps the island open when the person clicks elsewhere
        .onChange(of: step) { _, step in
            IslandModel.shared.hasDraft = [.thinking, .editing, .sending].contains(step)
        }
        .onDisappear { IslandModel.shared.hasDraft = false }
    }

    // MARK: The inbox

    private var list: some View {
        let important = inbox.mails.filter(\.important)
        let others = inbox.mails.filter { !$0.important }
        return VStack(alignment: .leading, spacing: 8) {
            if inbox.mails.isEmpty {
                ActSub(text: credentials == nil ? loc("Branche Gmail dans les réglages, Plus de réglages.") : loc("Rien de neuf dans ta boîte."))
            }
            if !important.isEmpty {
                section(loc("Importants"), important.prefix(4), color: IslandTheme.amber)
            }
            if !others.isEmpty {
                section(loc("Le reste"), others.prefix(important.isEmpty ? 5 : 3), color: IslandTheme.muted)
            }
        }
    }

    private func section(_ title: String, _ mails: ArraySlice<GmailMail>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(IslandTheme.text(9.5, .bold))
                .tracking(0.8)
                .foregroundStyle(color)
            ForEach(mails) { mail in
                Button { choose(mail) } label: { MailLine(mail: mail) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Answering one mail

    @ViewBuilder private func reply(to mail: GmailMail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { withAnimation(.islandSpring(0.4)) { reset() } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("Retour"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(mail.subject.isEmpty ? loc("(sans objet)") : mail.subject)
                        .font(IslandTheme.text(12.5, .semibold)).lineLimit(1)
                    Text(loc("De \(mail.from)")).font(IslandTheme.text(11)).foregroundStyle(IslandTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                TextButton(label: loc("Ouvrir dans Gmail")) { if let url = mail.url { NSWorkspace.shared.open(url) } }
                    .fixedSize()
            }
            switch step {
            case .reading:
                HStack {
                    Button { suggest(for: mail) } label: {
                        Label(loc("Yumi propose une réponse"), systemImage: "sparkles")
                            .font(IslandTheme.text(12, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(IslandTheme.violet))
                    }
                    .buttonStyle(RoundPress())
                    if mail.bulk {
                        ActSub(text: loc("Mail automatique : pas besoin de répondre."))
                    }
                }
            case .thinking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    ActSub(text: loc("Je lis le mail et j'écris une réponse…"))
                }
            case .editing, .sending, .failed:
                TextEditor(text: $draft)
                    .font(IslandTheme.text(12.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 104)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                    .disabled(step == .sending)
                HStack(spacing: 8) {
                    Text(loc("À \(mail.replyAddress)")).font(IslandTheme.text(11)).foregroundStyle(IslandTheme.muted).lineLimit(1)
                    if case .failed(let reason) = step {
                        Text(reason).font(IslandTheme.text(11, .medium)).foregroundStyle(IslandTheme.red).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button(loc("Annuler")) { withAnimation(.islandSpring(0.4)) { reset() } }
                        .buttonStyle(.plain)
                        .font(IslandTheme.text(12, .medium))
                        .foregroundStyle(IslandTheme.muted)
                    Button { send(mail) } label: {
                        Label(step == .sending ? loc("Envoi…") : loc("Envoyer"), systemImage: "paperplane.fill")
                            .font(IslandTheme.text(12, .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(IslandTheme.green))
                    }
                    .buttonStyle(RoundPress())
                    .disabled(step == .sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .sent:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(IslandTheme.green)
                    ActSub(text: loc("Envoyé à \(mail.replyAddress)."))
                }
            }
        }
    }

    private func choose(_ mail: GmailMail) {
        withAnimation(.islandSpring(0.4)) {
            chosen = mail
            step = .reading
            draft = ""
        }
        IslandActions.tap()
    }

    private func reset() {
        chosen = nil
        draft = ""
        step = .reading
    }

    /// Reads the mail, then asks the model for a short answer in its language.
    private func suggest(for mail: GmailMail) {
        guard let credentials else { return }
        step = .thinking
        IslandModel.shared.setMood(.thinking)
        let name = AppState.shared.userName
        Task {
            let text = (try? await GmailIMAP.text(of: mail.uid, address: credentials.address, password: credentials.password)) ?? ""
            let request = LLMRequest(
                system: """
                Tu es Yumi et tu aides la personne à répondre à un mail. Écris seulement le texte de la réponse, \
                sans objet ni explication : court, naturel, poli, dans la langue du mail, au ton du mail. \
                N'invente aucun fait, aucune date, aucun engagement : là où il faut une information que tu n'as pas, \
                écris [à compléter]. \(name.map { "Signe « \($0) »." } ?? "Ne signe pas.")
                """,
                messages: [LLMMessage(role: .user, content: """
                De : \(mail.from)
                Objet : \(mail.subject)

                \(String(text.prefix(5000)))
                """)],
                expectsJSON: false,
                maxOutputTokens: 700)
            do {
                let answer = try await EngineFactory.planner.complete(request)
                await MainActor.run {
                    draft = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    step = .editing
                    IslandModel.shared.setMood(nil)
                    IslandModel.shared.pose(.pop)
                }
            } catch {
                await MainActor.run {
                    step = .failed(loc("Aucun moteur ne répond : écris ta réponse ici."))
                    IslandModel.shared.setMood(nil)
                }
            }
        }
    }

    /// The click on "Envoyer": the only way an answer leaves.
    private func send(_ mail: GmailMail) {
        guard let credentials, !mail.replyAddress.isEmpty else { return }
        step = .sending
        let body = draft
        Task {
            do {
                try await GmailSMTP.send(from: credentials.address, password: credentials.password, to: mail.replyAddress,
                                         subject: GmailCompose.replySubject(mail.subject), inReplyTo: mail.messageID, body: body)
                await MainActor.run {
                    step = .sent
                    SoundEngine.shared.play("send")
                    IslandModel.shared.pose(.celebrate)
                }
            } catch {
                await MainActor.run { step = .failed(loc("L'envoi a échoué, rien n'est parti.")) }
            }
        }
    }
}

/// One mail in the list: unread dot, sender, subject, time.
private struct MailLine: View {
    let mail: GmailMail
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(mail.unread ? (mail.important ? IslandTheme.amber : IslandTheme.blue) : Color.clear)
                .frame(width: 6, height: 6)
            Text(mail.from)
                .font(IslandTheme.text(12, mail.unread ? .semibold : .regular))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            Text(mail.subject.isEmpty ? loc("(sans objet)") : mail.subject)
                .font(IslandTheme.text(12))
                .foregroundStyle(mail.unread ? IslandTheme.fg : IslandTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(mail.date.map { GmailSummary.when($0, now: .now) } ?? "")
                .font(IslandTheme.text(10.5))
                .foregroundStyle(IslandTheme.muted)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
