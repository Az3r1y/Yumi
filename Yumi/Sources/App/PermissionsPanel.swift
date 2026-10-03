import SwiftUI

/// What Yumi may do without asking, and what it decided lately. The person can take back a
/// permission and clear the history. These are Yumi's own permissions; the access macOS gives
/// the app (calendar, Accessibility…) is a separate matter, handled in System Settings.
struct PermissionsPanel: View {
    @ObservedObject var state: AppState

    var body: some View {
        if let permissions = state.permissions {
            PermissionsContent(permissions: permissions)
        } else {
            Text("Off while filming.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

private struct PermissionsContent: View {
    let permissions: LocalPermissionManager

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Je lis l'heure et mon propre contexte sans te demander. Pour modifier, envoyer ou supprimer, je te demande d'abord. Rien d'ici ne remplace les autorisations de macOS.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            caption("CE QUE TU M'AS PERMIS")
            let granted = permissions.sessionPermissions + permissions.rememberedPermissions
            if granted.isEmpty {
                Text("Rien pour l'instant.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(granted) { permission in
                HStack {
                    Text(describe(permission)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Retirer") { permissions.revoke(permission.id) }.controlSize(.small)
                }
            }
            if !permissions.policy.rules.isEmpty {
                caption("RÈGLES")
                ForEach(permissions.policy.rules) { rule in
                    HStack {
                        Text("\(rule.effect.rawValue) · \(rule.toolID)\(rule.kind.map { " · \($0.rawValue)" } ?? "")")
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button("Retirer") { permissions.removeRule(rule.id) }.controlSize(.small)
                    }
                }
            }

            HStack {
                caption("HISTORIQUE")
                Spacer()
                Button("Effacer") { permissions.audit.clear() }
                    .controlSize(.small)
                    .disabled(permissions.audit.entries.isEmpty)
            }
            if permissions.audit.entries.isEmpty {
                Text("Aucune décision.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(permissions.audit.entries.suffix(30).reversed()) { entry in
                Text(line(entry))
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }

    private func describe(_ permission: Permission) -> String {
        let place = permission.container.map { ($0 as NSString).lastPathComponent }
            ?? permission.resources.map { ($0.identifier as NSString).lastPathComponent }.joined(separator: ", ")
        return "\(permission.toolID)\(permission.kind.map { " · \($0.rawValue)" } ?? "") · \(place) · \(permission.scope.label)"
    }

    private func line(_ entry: PermissionAuditEntry) -> String {
        var parts = [Self.time.string(from: entry.date), entry.toolID, entry.decision.rawValue, "risque \(entry.risk.label)"]
        if !entry.resources.isEmpty {
            parts.append(entry.resources.joined(separator: ", ") + (entry.resourceCount > entry.resources.count ? "…" : ""))
        }
        if let scope = entry.scope { parts.append(scope.label) }
        return parts.joined(separator: " · ")
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
    }
}
