import SwiftUI

// Colours, type and motion of design/yumi/maquette/reference.html (`:root`).
// The island is one fixed object: same values in the light and dark themes.

enum IslandTheme {
    static let surface  = Color(hex: "#14161F")   // --isl-surface
    static let raise    = Color(hex: "#1F2231")   // --isl-raise
    static let line     = Color.white.opacity(0.09)   // --isl-line
    static let fg       = Color(hex: "#F4F5F8")   // --isl-fg
    static let muted    = Color(hex: "#8D92A8")   // --isl-muted
    static let faint    = Color(hex: "#5A5F74")   // --isl-faint
    /// Text on a main button
    static let ink      = Color(hex: "#06070C")
    static let code     = Color(hex: "#D6DAEA")
    static let bubbleMe = Color(hex: "#23263A")

    static let blue   = Color(hex: "#5B8CFF")
    static let violet = Color(hex: "#8B6CFF")
    static let pink   = Color(hex: "#F58AD9")
    static let amber  = Color(hex: "#FFB547")
    static let red    = Color(hex: "#FF5D6C")
    static let green  = Color(hex: "#3DDC97")

    /// `--round`: SF Pro Rounded
    static func round(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// `--text`: SF Pro Text
    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// `--mono`: SF Mono
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Animation {
    /// `--spring: cubic-bezier(.32, 1.22, .42, 1)`: it overshoots, then settles.
    static func islandSpring(_ duration: Double = 0.55) -> Animation {
        .timingCurve(0.32, 1.22, 0.42, 1, duration: duration)
    }

    /// The CSS keyword `ease`.
    static func islandEase(_ duration: Double) -> Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
    }
}

// MARK: - Nothing moves off screen

private struct IslandLayerShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// false inside a layer of the island that is not the one on screen: its continuous
    /// animations (wave, shimmer, spinner) stop instead of turning for nobody.
    var islandLayerShown: Bool {
        get { self[IslandLayerShownKey.self] }
        set { self[IslandLayerShownKey.self] = newValue }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Glyphs of the mock-up (18 × 18 box, stroked)

enum IslandGlyph {
    case home, chat, plus, add

    /// The `d` attribute of the mock-up, drawn in an 18 × 18 box.
    fileprivate func path() -> Path {
        var p = Path()
        switch self {
        case .home:   // M3 8.2 9 3l6 5.2V15H3z
            p.move(to: CGPoint(x: 3, y: 8.2))
            p.addLine(to: CGPoint(x: 9, y: 3))
            p.addLine(to: CGPoint(x: 15, y: 8.2))
            p.addLine(to: CGPoint(x: 15, y: 15))
            p.addLine(to: CGPoint(x: 3, y: 15))
            p.closeSubpath()
        case .chat:   // M3 4h12v8H8l-3 3v-3H3z
            p.move(to: CGPoint(x: 3, y: 4))
            p.addLine(to: CGPoint(x: 15, y: 4))
            p.addLine(to: CGPoint(x: 15, y: 12))
            p.addLine(to: CGPoint(x: 8, y: 12))
            p.addLine(to: CGPoint(x: 5, y: 15))
            p.addLine(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 3, y: 12))
            p.closeSubpath()
        case .plus:   // M9 3v12M3 9h12
            p.move(to: CGPoint(x: 9, y: 3));  p.addLine(to: CGPoint(x: 9, y: 15))
            p.move(to: CGPoint(x: 3, y: 9));  p.addLine(to: CGPoint(x: 15, y: 9))
        case .add:    // M9 4v10M4 9h10
            p.move(to: CGPoint(x: 9, y: 4));  p.addLine(to: CGPoint(x: 9, y: 14))
            p.move(to: CGPoint(x: 4, y: 9));  p.addLine(to: CGPoint(x: 14, y: 9))
        }
        return p
    }
}

struct IslandGlyphView: View {
    let glyph: IslandGlyph
    var size: CGFloat = 14

    var body: some View {
        let k = size / 18
        glyph.path()
            .applying(CGAffineTransform(scaleX: k, y: k))
            .stroke(style: StrokeStyle(lineWidth: 1.7 * k, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

// MARK: - `rise`: how a block of content comes in

/// `@keyframes rise { from { opacity: 0; transform: translateY(8px) scale(.98); filter: blur(5px) } }`,
/// played once when the view appears, each child a little after the previous one.
struct RiseIn: ViewModifier {
    let index: Int
    var duration: Double = 0.42
    var stagger: Double = 0.045

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.98)
            .offset(y: shown ? 0 : 8)
            .blur(radius: shown ? 0 : 5)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.islandSpring(duration).delay(Double(index) * stagger)) { shown = true }
                }
            }
    }
}

extension View {
    func riseIn(_ index: Int, duration: Double = 0.42, stagger: Double = 0.045) -> some View {
        modifier(RiseIn(index: index, duration: duration, stagger: stagger))
    }
}

// MARK: - Wrapping row (`flex-wrap: wrap`)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > width {
                rows.append(row)
                row = Row()
                row.items = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.items.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
