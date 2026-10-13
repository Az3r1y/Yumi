import SwiftUI

/// What Yumi wears (`SKINS` of the island demo), in the 100 × 84 box of the mock-up. The head
/// ones are drawn in the space of `drawTops`, so they ride the top of the body; the face ones
/// in the space of `drawProps`, so they follow the face. They sit with his habits and scenes.
enum YumiCostumes {

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    private static let white = rgb(0xF4F5F8)

    private static func polygon(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        return p
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    /// On the head. `accent` is the left stop of his rim: the island's colour at rest.
    static func drawHead(_ costume: YumiCostume, accent: Color, in c: GraphicsContext) {
        switch costume {
        case .beanie:
            var dome = Path()
            dome.move(to: CGPoint(x: 17, y: 24))
            dome.addQuadCurve(to: CGPoint(x: 83, y: 24), control: CGPoint(x: 50, y: -16))
            dome.closeSubpath()
            c.fill(dome, with: .color(accent))
            c.fill(Path(roundedRect: CGRect(x: 14, y: 17, width: 72, height: 10), cornerRadius: 5), with: .color(white))
            c.fill(circle(50, -6, 6.5), with: .color(white))

        case .crown:
            let crown = polygon([CGPoint(x: 27, y: 14), CGPoint(x: 31, y: -7), CGPoint(x: 41, y: 5), CGPoint(x: 50, y: -11),
                                 CGPoint(x: 59, y: 5), CGPoint(x: 69, y: -7), CGPoint(x: 73, y: 14)])
            c.fill(crown, with: .color(rgb(0xFFD24A)))
            c.stroke(crown, with: .color(rgb(0xE0A800)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            c.fill(circle(50, 6, 2.6), with: .color(rgb(0xFF5D8F)))
            c.fill(circle(36, 9, 1.8), with: .color(rgb(0x5B8CFF)))
            c.fill(circle(64, 9, 1.8), with: .color(rgb(0x5B8CFF)))

        case .cat:
            for ear in [[CGPoint(x: 16, y: 26), CGPoint(x: 20, y: -4), CGPoint(x: 40, y: 12)],
                        [CGPoint(x: 84, y: 26), CGPoint(x: 80, y: -4), CGPoint(x: 60, y: 12)]] {
                let path = polygon(ear)
                c.fill(path, with: .color(.black))
                c.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
            c.fill(polygon([CGPoint(x: 22, y: 18), CGPoint(x: 23, y: 4), CGPoint(x: 33, y: 12)]), with: .color(rgb(0xFF8FC8)))
            c.fill(polygon([CGPoint(x: 78, y: 18), CGPoint(x: 77, y: 4), CGPoint(x: 67, y: 12)]), with: .color(rgb(0xFF8FC8)))

        case .witch:
            c.fill(Path(ellipseIn: CGRect(x: 14, y: 8, width: 72, height: 12)), with: .color(rgb(0x2B2140)))
            c.fill(polygon([CGPoint(x: 31, y: 14), CGPoint(x: 60, y: -30), CGPoint(x: 69, y: 14)]), with: .color(rgb(0x3A2B5C)))
            var band = Path()
            band.move(to: CGPoint(x: 33, y: 9))
            band.addLine(to: CGPoint(x: 67, y: 9))
            c.stroke(band, with: .color(accent), lineWidth: 4)
            var tip = Path()
            tip.move(to: CGPoint(x: 60, y: -30))
            tip.addQuadCurve(to: CGPoint(x: 69, y: -20), control: CGPoint(x: 68, y: -28))
            c.stroke(tip, with: .color(rgb(0x3A2B5C)), style: StrokeStyle(lineWidth: 4, lineCap: .round))

        case .halo:
            let ring = Path(ellipseIn: CGRect(x: 28, y: -13.5, width: 44, height: 11))
            var glow = c
            glow.opacity = 0.25
            glow.stroke(ring, with: .color(rgb(0xFFE27A)), lineWidth: 7)
            c.stroke(ring, with: .color(rgb(0xFFE27A)), lineWidth: 3.2)

        case .flower:
            var flower = c
            flower.translateBy(x: 70, y: 8)
            for angle in stride(from: 0.0, to: 360.0, by: 72.0) {
                var petal = flower
                petal.rotate(by: .degrees(angle))
                petal.fill(Path(ellipseIn: CGRect(x: -4.2, y: -12, width: 8.4, height: 12)), with: .color(rgb(0xFF9AC8)))
            }
            flower.fill(circle(0, 0, 3.6), with: .color(rgb(0xFFD24A)))

        case .none, .glasses, .mustache:
            break
        }
    }

    /// On the face.
    static func drawFace(_ costume: YumiCostume, in c: GraphicsContext) {
        switch costume {
        case .cat:
            var whiskers = Path()
            for (a, b) in [((22, 58), (10, 58)), ((23, 62), (12, 65)), ((78, 58), (90, 58)), ((77, 62), (88, 65))] {
                whiskers.move(to: CGPoint(x: a.0, y: a.1))
                whiskers.addLine(to: CGPoint(x: b.0, y: b.1))
            }
            var w = c
            w.opacity = 0.7
            w.stroke(whiskers, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        case .glasses:
            let style = StrokeStyle(lineWidth: 2.2)
            c.stroke(circle(37, 45, 12), with: .color(white), style: style)
            c.stroke(circle(63, 45, 12), with: .color(white), style: style)
            var bridge = Path()
            bridge.move(to: CGPoint(x: 49, y: 44))
            bridge.addQuadCurve(to: CGPoint(x: 51, y: 44), control: CGPoint(x: 50, y: 42))
            c.stroke(bridge, with: .color(white), style: style)

        case .mustache:
            var m = Path()
            m.move(to: CGPoint(x: 50, y: 60))
            m.addCurve(to: CGPoint(x: 33, y: 59), control1: CGPoint(x: 46, y: 56), control2: CGPoint(x: 38, y: 55))
            m.addCurve(to: CGPoint(x: 42, y: 63), control1: CGPoint(x: 37, y: 59), control2: CGPoint(x: 40, y: 62))
            m.addCurve(to: CGPoint(x: 50, y: 60), control1: CGPoint(x: 45, y: 64), control2: CGPoint(x: 48, y: 63))
            m.addCurve(to: CGPoint(x: 58, y: 63), control1: CGPoint(x: 52, y: 63), control2: CGPoint(x: 55, y: 64))
            m.addCurve(to: CGPoint(x: 67, y: 59), control1: CGPoint(x: 60, y: 62), control2: CGPoint(x: 63, y: 59))
            m.addCurve(to: CGPoint(x: 50, y: 60), control1: CGPoint(x: 62, y: 55), control2: CGPoint(x: 54, y: 56))
            m.closeSubpath()
            c.fill(m, with: .color(white))

        default:
            break
        }
    }
}
