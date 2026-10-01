import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, uploading, choose, mail, prompt
    case searching, result, note, settings, greeting
    /// Detail of one module (the one in `IslandModel.selectedModuleID`).
    case module
}

// MARK: - What the island shows (design/yumi/maquette/reference.html)

/// The eight views of the open island. Several legacy `IslandView` values, still set by
/// the hook server and the chat service, land on the same screen.
enum IslandScreen: String, CaseIterable {
    case home, working, alert, finished, error, module, talk, drop

    /// The screen for what the application says right now. A view that names a screen wins;
    /// on the home view, the state of the agent decides, so that the island always shows
    /// the most useful thing.
    static func resolve(view: IslandView, state: BotState, approvalPending: Bool) -> IslandScreen {
        switch view {
        case .approval, .question:                      return .alert
        case .finished:                                 return .finished
        case .error:                                    return .error
        case .prompt, .searching, .result, .note:       return .talk
        case .upload, .uploading, .choose, .mail:       return .drop
        case .module:                                   return .module
        case .overview, .empty, .confused, .settings, .greeting:
            if approvalPending { return .alert }
            switch state {
            case .working, .thinking, .searching:       return .working
            case .approval, .question:                  return .alert
            case .error:                                return .error
            case .finished:                             return .finished
            case .idle, .ratelimit, .sleeping, .dizzy:  return .home
            }
        }
    }
}

/// The shape the island has right now. `drip` and `greet` only exist during the launch.
enum IslandStage: String, CaseIterable {
    case hidden, compact, open, drip, greet
}

/// Where Yumi sits (`SEATS` in the mock-up): the centre of his 100 × 84 box, as an offset
/// from the centre of the island and a distance from the top of the screen, and his scale.
struct IslandSeat: Equatable {
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var opacity: Double

    /// Side of the square frame given to `BotCanvasView`: his body, 84 units wide, takes
    /// 68.4 % of it (1.14 × the "diameter" of the layouts, which is 0.6 × the frame).
    static func frameSide(scale: CGFloat) -> CGFloat { 84 * scale / 0.684 }
}

/// Sizes and seats of the mock-up, fitted to the notch of this Mac.
struct IslandLayout: Equatable {
    var notchWidth: CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight
    /// A real notch hides whatever is drawn behind it; a screen without one shows everything.
    var hasNotch = false

    /// The mock-up has a 32 pt notch. A taller one pushes the launch shapes down by the difference.
    var notchDelta: CGFloat { max(0, notchHeight - IslandConst.mockNotchHeight) }

    /// Open island: the mock-up starts its content 8 pt under the top edge, which a real notch
    /// would cover. The content then starts just under the notch instead.
    var openInset: CGFloat { hasNotch ? max(0, notchHeight + 2 - IslandConst.openPaddingTop) : 0 }

    func size(_ stage: IslandStage, openHeight: CGFloat) -> CGSize {
        let k = IslandConst.openScale
        switch stage {
        case .hidden:  return CGSize(width: notchWidth, height: notchHeight)
        case .compact: return CGSize(width: notchWidth + IslandConst.compactExtra, height: notchHeight)
        case .open:    return CGSize(width: IslandConst.expandedWidth * IslandConst.openScale, height: openHeight)
        case .drip:    return CGSize(width: (notchWidth + IslandConst.dripExtra) * k, height: IslandConst.dripHeight * k + notchDelta)
        case .greet:   return CGSize(width: IslandConst.greetWidth * k, height: IslandConst.greetHeight * k + notchDelta)
        }
    }

    func cornerRadius(_ stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden, .compact: return IslandConst.roundedCorner
        case .open, .greet:     return IslandConst.expandedCorner * IslandConst.openScale
        case .drip:             return IslandConst.dripCorner * IslandConst.openScale
        }
    }

    /// `SEATS`: [x in the island, y, scale, opacity]. The rim width of each seat is the
    /// character's own business: it derives it from the size it is drawn at.
    func seat(_ stage: IslandStage) -> IslandSeat {
        let k = IslandConst.openScale
        switch stage {
        case .hidden:
            return IslandSeat(x: 0, y: notchHeight / 2 - 2, scale: 0.05, opacity: 0)
        case .compact:
            return IslandSeat(x: 28 - (notchWidth + IslandConst.compactExtra) / 2, y: notchHeight / 2, scale: 0.27, opacity: 1)
        case .open:
            return IslandSeat(x: (50 - IslandConst.expandedWidth / 2) * k, y: 48 * k + openInset, scale: 0.66 * k, opacity: 1)
        case .drip:
            return IslandSeat(x: 0, y: 62 * k + notchDelta, scale: 0.42 * k, opacity: 1)
        case .greet:
            return IslandSeat(x: (118 - IslandConst.greetWidth / 2) * k, y: 94 * k + notchDelta, scale: k, opacity: 1)
        }
    }
}

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - Approval info (pending PermissionRequest from Claude Code)

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for persistent integration pills
    var emote: BotEmote? = nil
    var miniEye: EyeShape? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
}

enum AgentSource: Equatable {
    case claudeCode
    case n8n
}

// MARK: - Constants (sizes of design/yumi/maquette/reference.html)

enum IslandConst {
    static let notchWidth: CGFloat  = 184
    static let notchHeight: CGFloat = 32
    /// The compact island sticks out this much on both sides of the notch (344 for a 184 notch).
    static let compactExtra: CGFloat = 160
    /// Open island: 480 wide in the mock-up, as low as the content allows.
    static let expandedWidth: CGFloat = 480
    /// The open island, its second square and the launch are the mock-up enlarged by this
    /// much: at its own size it reads too small on a real screen. Change this one number to
    /// resize (the panel below has to stay wider than 480 × this).
    static let openScale: CGFloat = 1.4
    static let openHeightDefault: CGFloat = 150
    static let openHeightMax: CGFloat = 300
    /// Left column of the open island: Yumi's seat and his caption.
    static let seatColumn: CGFloat = 96
    static let openPaddingTop: CGFloat = 8
    /// The notch of the mock-up. A taller real notch pushes the launch shapes down by the difference.
    static let mockNotchHeight: CGFloat = 32
    /// Launch: the drop under the notch, then the wide greeting.
    static let dripExtra: CGFloat = 12
    static let dripHeight: CGFloat = 102
    static let greetWidth: CGFloat = 420
    static let greetHeight: CGFloat = 168
    /// The second square, detached under the island.
    static let drawerWidth: CGFloat = 288
    static let drawerGap: CGFloat = 8

    static let roundedCorner: CGFloat = 14    // hidden and compact
    static let expandedCorner: CGFloat = 24   // open and greeting
    static let dripCorner: CGFloat = 80

    /// Size of the transparent panel the island lives in.
    static let panelWidth: CGFloat = 880
    static let panelHeight: CGFloat = 680
}
