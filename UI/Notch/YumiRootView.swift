import SwiftUI

/// Display mode of the notch island, driven by NotchWindowController (FSM output).
enum NotchMode: Equatable {
    case hidden
    case compact
    case expanded
}

/// Observable view-model bridging the AppKit controller and SwiftUI.
@MainActor
final class GreetingSequenceController: ObservableObject {
    @Published var mode: NotchMode = .hidden
    /// Counts greeting runs so the canvas restarts its timeline on each entry.
    @Published private(set) var greetingRunID: Int = 0
    /// True only while the FSM is in the greeting state (.coucou).
    @Published private(set) var showGreeting: Bool = false

    func begin() {
        greetingRunID += 1
        showGreeting = true
    }

    func reset() {
        showGreeting = false
    }
}

/// Single source of truth for island dimensions — shared by the SwiftUI view
/// and the AppKit hover hit-testing (no duplication).
enum NotchGeometry {
    static let notchWidth: CGFloat = 184
    static let notchHeight: CGFloat = 32
    static let compactExtra: CGFloat = 160
    static let expandedWidth: CGFloat = 640
    static let expandedHeight: CGFloat = 150

    static func width(for mode: NotchMode) -> CGFloat {
        switch mode {
        case .hidden: return notchWidth
        case .compact: return notchWidth + compactExtra
        case .expanded: return expandedWidth
        }
    }

    static func height(for mode: NotchMode) -> CGFloat {
        mode == .expanded ? expandedHeight : notchHeight
    }
}

/// Root view rendered inside the 720×320 transparent panel.
/// The island is drawn top-center; everything else is transparent (the panel
/// itself toggles click-through, so no hit-testing is needed here).
struct YumiRootView: View {
    @EnvironmentObject var greeting: GreetingSequenceController

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)

            ZStack(alignment: .topLeading) {
                // Black island shape glued to the top edge
                YumiShape()
                    .fill(Color.black)
                    .frame(width: islandWidth, height: islandHeight)

                // Content
                if greeting.mode == .expanded {
                    if greeting.showGreeting {
                        GreetingCanvasView(runID: greeting.greetingRunID)
                            .frame(width: NotchGeometry.expandedWidth, height: NotchGeometry.expandedHeight)
                            .offset(x: (islandWidth - NotchGeometry.expandedWidth) / 2)
                            .clipShape(YumiShape())
                            .transition(.opacity)
                    } else {
                        homeContent
                    }
                } else if greeting.mode == .compact {
                    // Sprite peeking next to the notch
                    YumiSprite(state: .idle, size: 20)
                        .offset(x: 40, y: 16)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var islandWidth: CGFloat { NotchGeometry.width(for: greeting.mode) }
    private var islandHeight: CGFloat { NotchGeometry.height(for: greeting.mode) }

    @ViewBuilder
    private var homeContent: some View {
        // Minimal expanded placeholder — real session views come in step 4.
        VStack(alignment: .leading, spacing: 4) {
            Text("Yumi")
                .font(.system(size: 15, weight: .semibold))
            Text("No sessions yet — the Claude Code connector arrives in step 3.")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
        .foregroundStyle(.white)
        .padding(.leading, 24)
        .padding(.top, 24)
        .frame(width: NotchGeometry.expandedWidth, alignment: .leading)
    }
}

// MARK: - Island shape

/// Island silhouette: sharp top corners (blends into the screen edge),
/// rounded bottom corners. Sized by its frame.
struct YumiShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 14
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        p.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                 radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                 radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}
