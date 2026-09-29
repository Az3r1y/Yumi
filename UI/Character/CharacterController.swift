import Foundation
import AppKit
import Combine

/// Main-actor controller that bridges the Core presentation state to the
/// character layer and owns the animation controller. Lives in the
/// composition root's wiring: events → presentation → character.
///
/// Lifetime: one instance for the whole app run (owned by AppDelegate), so
/// the Reduce Motion observer is registered once and never removed — the
/// block captures `self` weakly, so nothing is retained.
@MainActor
final class CharacterController: ObservableObject {
    let animationController = CharacterAnimationController()

    init() {
        // Respect macOS Reduce Motion from the start, and follow changes.
        animationController.setReduceMotion(
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.animationController.setReduceMotion(
                    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
    }

    /// Maps the Core presentation state onto character presentation states.
    /// This is where "Session = X, Character = Y" decisions live.
    func sync(presentationState: YumiPresentationState) {
        let characterState: CharacterState
        switch presentationState {
        case .idle: characterState = .idle
        case .working: characterState = .working
        case .permissionRequired, .questionRequired: characterState = .waiting
        case .completed: characterState = .happy
        case .errored: characterState = .errored
        }
        animationController.setState(characterState)
    }

    /// Reactions triggered by presentation transitions (called by the pump
    /// when the state *changes*).
    func react(to transition: YumiPresentationTransition) {
        switch transition {
        case .toCompleted:
            animationController.playReaction(.celebrate, at: now())
        case .toErrored:
            animationController.playReaction(.error, at: now())
        case .toWaiting:
            animationController.playReaction(.surprise, at: now())
        case .toWorking:
            animationController.playOneShot(.peek, at: now())
        case .toIdle:
            break
        }
    }

    private func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}

/// A change of the presentation state, used to fire one-shot reactions.
enum YumiPresentationTransition: Equatable {
    case toIdle
    case toWorking
    case toWaiting
    case toCompleted
    case toErrored

    static func between(_ old: YumiPresentationState, _ new: YumiPresentationState) -> YumiPresentationTransition? {
        guard old != new else { return nil }
        switch new {
        case .idle: return .toIdle
        case .working: return .toWorking
        case .permissionRequired, .questionRequired: return .toWaiting
        case .completed: return .toCompleted
        case .errored: return .toErrored
        }
    }
}
