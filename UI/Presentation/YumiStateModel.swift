import Foundation
import Combine

// MARK: - Presentation state (UI layer)

/// What Yumi as a whole should show, derived from the sessions.
/// Precedence: errors first, then pending user input, then activity.
/// This is a UI concern: it describes what to present, not what is true.
enum YumiPresentationState: Equatable {
    case idle
    case working
    case permissionRequired
    case questionRequired
    case completed
    case errored

    init(sessions: [Session]) {
        if sessions.contains(where: { $0.status == .errored }) {
            self = .errored
        } else if sessions.contains(where: {
            if case .requestingPermission = $0.activity { return true }
            return false
        }) {
            self = .permissionRequired
        } else if sessions.contains(where: {
            if case .asking = $0.activity { return true }
            return false
        }) {
            self = .questionRequired
        } else if sessions.contains(where: { $0.status == .completed }) {
            self = .completed
        } else if sessions.contains(where: { $0.status == .running }) {
            self = .working
        } else {
            self = .idle
        }
    }
}

// MARK: - SwiftUI bridge (presentation layer)

/// Live, immutable snapshot of the Core for SwiftUI. The SessionStore actor
/// owns the truth; this class mirrors it on the main actor so views never
/// touch the actor directly. Created in the composition root — no singletons.
@MainActor
final class YumiStateModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var presentationState: YumiPresentationState = .idle

    func update(from snapshot: [SessionID: Session]) {
        sessions = snapshot.values.sorted { $0.title < $1.title }
        presentationState = YumiPresentationState(sessions: sessions)
    }
}
