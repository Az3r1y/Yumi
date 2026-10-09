import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, choose, prompt
    case searching, result, note, settings, greeting
    /// Detail of one module (the one in `IslandModel.selectedModuleID`).
    case module
    /// First launch: Yumi asks the person's first name.
    case welcome
    /// Everything Yumi remembers, to read, correct and erase.
    case memory
    /// The quick task field and the day's list of its destination.
    case quickTask
}

// MARK: - What the island shows (design/yumi/maquette/reference.html)

/// The eight views of the open island. Several legacy `IslandView` values, still set by
/// the hook server and the chat service, land on the same screen.
enum IslandScreen: String, CaseIterable {
    /// `home` is the overview ("Tous"): what the island opens on when nothing is urgent.
    case home, working, alert, finished, error, module, talk, drop, settings, welcome, memory, quickTask

    /// The screen for what the application says right now. A view that names a screen wins;
    /// on the home view, only what is urgent takes its place.
    static func resolve(view: IslandView, state: BotState, approvalPending: Bool) -> IslandScreen {
        switch view {
        case .approval, .question:                      return .alert
        case .finished:                                 return .finished
        case .error:                                    return .error
        case .prompt, .searching, .result, .note:       return .talk
        case .upload, .choose:                          return .drop
        case .module:                                   return .module
        case .settings:                                 return .settings
        case .welcome:                                  return .welcome
        case .memory:                                   return .memory
        case .quickTask:                                return .quickTask
        case .overview, .empty, .confused, .greeting:
            if approvalPending { return .alert }
            switch state {
            case .approval, .question:                  return .alert
            case .error:                                return .error
            case .finished:                             return .finished
            case .working, .thinking, .searching, .idle, .ratelimit, .sleeping, .dizzy:
                return .home
            }
        }
    }
}

/// The shape the island has right now. `drip` and `greet` only exist during the launch,
/// `bye` during the goodbye.
enum IslandStage: String, CaseIterable {
    case hidden, compact, open, drip, greet, bye
    /// Folded, and a little larger: Yumi is saying something.
    case speak
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
    /// How far the folded island sticks out on each side of the notch. It grows with what is
    /// live on the right (see `FoldedIsland.ear`).
    var compactEar: CGFloat = IslandConst.compactExtra / 2
    /// The left of the notch holds the menus of the app in front: the folded island starts at
    /// the notch and Yumi sits on its right (`FoldedIsland.side`).
    var foldedRight = false
    /// Width of the island while Yumi speaks, and its height under the notch.
    var speakWidth: CGFloat = 0
    var speakBand: CGFloat = 0

    /// The mock-up has a 32 pt notch. A taller one pushes the launch shapes down by the difference.
    var notchDelta: CGFloat { max(0, notchHeight - IslandConst.mockNotchHeight) }

    /// Open island: the mock-up starts its content 8 pt under the top edge, which a real notch
    /// would cover. The content then starts just under the notch instead.
    var openInset: CGFloat { hasNotch ? max(0, notchHeight + 8 - IslandConst.openPaddingTop * IslandConst.openScale) : 0 }

    func size(_ stage: IslandStage, openHeight: CGFloat) -> CGSize {
        let k = IslandConst.openScale, l = IslandConst.launchScale
        switch stage {
        case .hidden:  return CGSize(width: notchWidth, height: notchHeight)
        case .compact: return CGSize(width: notchWidth + compactEar * 2, height: notchHeight)
        case .speak:   return CGSize(width: speakWidth, height: notchHeight + speakBand)
        case .open:    return CGSize(width: IslandConst.expandedWidth * IslandConst.openScale, height: openHeight)
        case .drip:    return CGSize(width: (notchWidth + IslandConst.dripExtra) * l, height: IslandConst.dripHeight * l + notchDelta)
        case .greet:   return CGSize(width: IslandConst.greetWidth * l, height: IslandConst.greetHeight * l + notchDelta)
        case .bye:     return CGSize(width: IslandConst.byeWidth * l, height: IslandConst.byeHeight * l + notchDelta)
        }
    }

    /// How far right of the notch's middle the island is drawn: same width, its left ear
    /// slid under the notch.
    func shift(_ stage: IslandStage) -> CGFloat {
        stage == .compact && foldedRight ? compactEar : 0
    }

    func cornerRadius(_ stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden, .compact: return IslandConst.roundedCorner
        case .speak:            return 20
        case .open:             return IslandConst.expandedCorner * IslandConst.openScale
        case .greet, .bye:      return IslandConst.expandedCorner * IslandConst.launchScale
        case .drip:             return IslandConst.dripCorner * IslandConst.launchScale
        }
    }

    /// `SEATS`: [x in the island, y, scale, opacity]. The rim width of each seat is the
    /// character's own business: it derives it from the size it is drawn at.
    func seat(_ stage: IslandStage) -> IslandSeat {
        let k = IslandConst.openScale, l = IslandConst.launchScale
        switch stage {
        case .hidden:
            return IslandSeat(x: 0, y: notchHeight / 2 - 2, scale: 0.05, opacity: 0)
        case .speak:
            return IslandSeat(x: 32 - speakWidth / 2, y: notchHeight + speakBand / 2 - 2, scale: 0.36, opacity: 1)
        case .compact:
            // On the right, the mirror of his place on the left: at the outer end, what is
            // live between him and the notch
            return IslandSeat(x: foldedRight ? notchWidth / 2 + compactEar * 2 - 28 : 28 - (notchWidth + compactEar * 2) / 2,
                              y: notchHeight / 2, scale: 0.27, opacity: 1)
        case .open:
            return IslandSeat(x: (50 - IslandConst.expandedWidth / 2) * k, y: 56 * k + openInset, scale: 0.68 * k, opacity: 1)
        case .drip:
            return IslandSeat(x: 0, y: 62 * l + notchDelta, scale: 0.42 * l, opacity: 1)
        case .greet:
            return IslandSeat(x: (130 - IslandConst.greetWidth / 2) * l, y: 84 * l + notchDelta, scale: l, opacity: 1)
        case .bye:
            return IslandSeat(x: (150 - IslandConst.byeWidth / 2) * l, y: 62 * l + notchDelta, scale: 0.86 * l, opacity: 1)
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
    /// Set when Yumi's own agent asks (Permissions/): the island shows its short sentence, and
    /// its details on demand, instead of a command.
    var agentRequest: ApprovalRequest? = nil
    /// The request this card answers (`HookServer`). A click answers this one or nothing: the
    /// queue may have moved on (an expiry, a withdrawal) between the drawing and the click.
    var requestID: String? = nil
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
    var isIntegration: Bool = false  // true for the permanent Claude Code task
    var emote: BotEmote? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
}

enum AgentSource: Equatable {
    case claudeCode
}

// MARK: - Constants (sizes of design/yumi/maquette/reference.html)

enum IslandConst {
    static let notchWidth: CGFloat  = 184
    static let notchHeight: CGFloat = 32
    /// The compact island sticks out this much on both sides of the notch (344 for a 184 notch).
    static let compactExtra: CGFloat = 160
    /// Folded island, right of the notch: paddings, the colour dot, the longest live text,
    /// and the buttons that appear on hover.
    static let foldedLeading: CGFloat = 10
    static let foldedTrailing: CGFloat = 14
    /// The black of the folded island fades out over this much at each end.
    static let foldedFade: CGFloat = 26
    static let foldedDot: CGFloat = 7
    static let foldedGap: CGFloat = 7
    static let foldedTextMax: CGFloat = 190
    static let foldedControl: CGFloat = 22
    static let foldedControlGap: CGFloat = 4
    /// Open island: 480 wide in the mock-up. On a real screen that frame is too tight around
    /// its content, so the island is wider and airier than the mock-up while its text stays
    /// close to the mock-up's size.
    static let expandedWidth: CGFloat = 600
    /// Zoom of what the open island and its second square contain (text, Yumi, buttons).
    /// The island is `expandedWidth × openScale` wide; the panel below has to stay wider.
    static let openScale: CGFloat = 1.1
    /// Zoom of the launch (the drop and the greeting).
    static let launchScale: CGFloat = 1.25
    static let openHeightDefault: CGFloat = 150
    static let openHeightMax: CGFloat = 340
    /// Left column of the open island: Yumi's seat and his caption.
    static let seatColumn: CGFloat = 92
    /// `.act { padding: 18px 22px 8px 0; min-height: 102px }`
    static let openPaddingTop: CGFloat = 18
    static let openPaddingBottom: CGFloat = 8
    static let openPaddingTrailing: CGFloat = 22
    static let actMinHeight: CGFloat = 76
    /// The notch of the mock-up. A taller real notch pushes the launch shapes down by the difference.
    static let mockNotchHeight: CGFloat = 32
    /// Launch: the drop under the notch, then the wide greeting.
    static let dripExtra: CGFloat = 12
    static let dripHeight: CGFloat = 102
    static let greetWidth: CGFloat = 260
    static let greetHeight: CGFloat = 150
    /// The goodbye: a little wider, Yumi in the middle.
    static let byeWidth: CGFloat = 300
    static let byeHeight: CGFloat = 132
    /// The second square, detached under the island.
    /// The bubble of the second activity, detached from the folded island.
    static let bubbleWidth: CGFloat = 34
    static let bubbleGap: CGFloat = 10

    static let roundedCorner: CGFloat = 14    // hidden and compact
    static let expandedCorner: CGFloat = 38   // open and greeting
    static let dripCorner: CGFloat = 80

    /// Size of the transparent panel the island lives in.
    static let panelWidth: CGFloat = 880
    static let panelHeight: CGFloat = 680
}
