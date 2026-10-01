import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Easing functions (same as prototype: E.out, E.inOut, E.back, E.lin)

enum Ease {
    static func out(_ t: CGFloat) -> CGFloat   { 1 - pow(1 - t, 3) }
    static func inOut(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2 }
    static func back(_ t: CGFloat) -> CGFloat  { let c1: CGFloat = 1.7; let c3 = c1+1; return 1+c3*pow(t-1,3)+c1*pow(t-1,2) }
    static func lin(_ t: CGFloat) -> CGFloat   { t }
}

// MARK: - Tween key: [target, duration_ms, easing]

struct TweenKey {
    let target: CGFloat
    let duration: CGFloat    // milliseconds
    let ease: (CGFloat) -> CGFloat
}

struct Tween {
    let property: String
    var keys: [TweenKey]
    var keyIndex: Int = 0
    var from: CGFloat
    var startTime: Double    // CACurrentMediaTime() * 1000
    var onComplete: (() -> Void)? = nil
}

// MARK: - Particle

struct Particle {
    enum ParticleType { case heart, star, spark, sweat, z }
    var type: ParticleType
    var x, y, vx, vy: CGFloat
    var age: Double        // seconds
    var life: Double
    var rot: CGFloat
    var size: CGFloat
}

// MARK: - Bot state config (mirrors STATES in prototype)

struct BotStateCfg {
    let color: CGColor
    let tint: CGFloat
    let eye: EyeShape
    let badge: BadgeType?
    let badgeColor: CGColor
    let glow: CGColor
    let glowOpacity: CGFloat
    let bounces: Bool
    let scans: Bool
    let breathes: Bool
    let zz: Bool
    let sweat: Bool
    let look: CGPoint?     // fixed look direction
    let tilt: CGFloat
    let sound: String?
}

enum EyeShape: String {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink, cup
    case focused, thoughtful, curious, panicked, content
}

enum BadgeType {
    case dots(CGColor)
    case bang(CGColor)
    case question(CGColor)
    case dot(CGColor)
}

// MARK: - Character track constants

enum MochiConst {
    static let lookYaw: CGFloat   = 0.62   // yaw reached when the pointer is far to the side
    static let lookPitch: CGFloat = 0.5
    static let eyeShiftX: CGFloat = 0.16   // how far the eyes slide with the look (fraction of R per unit of yaw)
    static let eyeShiftY: CGFloat = 0.10
    static let armLength: CGFloat = 0.52   // fraction of R
    static let armThick: CGFloat  = 0.30
}

// MARK: - Yumi skin

// >>> YumiSkin
// Yumi's look (concept 4), shared by the three renderers: BotEngine, GreetingCanvasView
// and UploadCanvasView. CoreGraphics only, y pointing down, origin at the body centre.
// design/yumi/outils/icones.sh compiles this block on its own to render the icons,
// so keep it free of SwiftUI, AppState and anything outside the markers.

struct YumiRGB: Equatable, Sendable {
    var r: CGFloat, g: CGFloat, b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        self.init(CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255)
    }

    func mix(_ o: YumiRGB, _ t: CGFloat) -> YumiRGB {
        YumiRGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t)
    }

    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
}

/// The rim light: three stops running from the left edge to the right edge of the body.
struct YumiRim: Equatable, Sendable {
    var left: YumiRGB, mid: YumiRGB, right: YumiRGB

    /// Resting gradient of the concept sheet: blue, violet, pink.
    static let idle = YumiRim(left: YumiSkin.blue, mid: YumiSkin.violet, right: YumiSkin.rose)

    /// One state (or brand) colour, with a little shading so the rim keeps some depth.
    static func solid(_ c: YumiRGB) -> YumiRim {
        YumiRim(left: c.mix(YumiSkin.white, 0.34), mid: c, right: c.mix(YumiSkin.white, 0.10))
    }

    func mix(_ o: YumiRim, _ t: CGFloat) -> YumiRim {
        YumiRim(left: left.mix(o.left, t), mid: mid.mix(o.mid, t), right: right.mix(o.right, t))
    }
}

/// One eye. Everything is a number so two expressions can be blended.
struct YumiEye: Equatable, Sendable {
    var scale: CGFloat = 1
    var lidTop: CGFloat = 0      // 0…1 of the eye height covered by the upper lid
    var lidBottom: CGFloat = 0   // 0…1 covered by the lower lid (arched, the cheek pushes up)
    var slant: CGFloat = 0       // upper lid slope: > 0 inner side lower, < 0 outer side lower
    var arc: CGFloat = 0         // closed eye: +1 bent upwards (smile), -1 bent downwards (sleep)
    var pupil: CGFloat = 1       // pupil scale
    var px: CGFloat = 0          // pupil offset added to the gaze, -1…1
    var py: CGFloat = 0
    var heart: CGFloat = 0       // 0…1 pupil replaced by a heart
    var sparkle: CGFloat = 0     // 0…1 second reflection

    func mix(_ o: YumiEye, _ t: CGFloat) -> YumiEye {
        func l(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * t }
        return YumiEye(scale: l(scale, o.scale), lidTop: l(lidTop, o.lidTop), lidBottom: l(lidBottom, o.lidBottom),
                       slant: l(slant, o.slant), arc: l(arc, o.arc), pupil: l(pupil, o.pupil),
                       px: l(px, o.px), py: l(py, o.py), heart: l(heart, o.heart), sparkle: l(sparkle, o.sparkle))
    }
}

struct YumiEyes: Equatable, Sendable {
    var left = YumiEye()
    var right = YumiEye()
    var gaze: CGFloat = 1        // how much of the look direction reaches the pupils

    func mix(_ o: YumiEyes, _ t: CGFloat) -> YumiEyes {
        YumiEyes(left: left.mix(o.left, t), right: right.mix(o.right, t), gaze: gaze + (o.gaze - gaze) * t)
    }
}

/// The expressions of the concept sheet, plus the few the app needs on top.
enum YumiExpression: Sendable {
    case neutral, happy, curious, focused, thoughtful, asleep, drowsy
    case worried, confused, annoyed, surprised, panicked, wink
    case love, proud, eager, content

    /// `t` (seconds) only matters for the expressions that move on their own.
    func eyes(at t: CGFloat = 0) -> YumiEyes {
        var e = YumiEyes()
        func both(_ edit: (inout YumiEye) -> Void) { edit(&e.left); edit(&e.right) }
        switch self {
        case .neutral:
            break
        case .happy:
            both { $0.lidBottom = 0.30; $0.pupil = 1.06; $0.py = -0.30 }
        case .curious:
            e.left.scale = 0.90; e.left.lidTop = 0.10
            e.right.scale = 1.14
            both { $0.py = -0.22 }
        case .focused:
            both { $0.lidTop = 0.40; $0.lidBottom = 0.14; $0.pupil = 0.92; $0.py = 0.22 }
        case .thoughtful:
            e.left.lidTop = 0.24; e.right.lidTop = 0.08
            both { $0.pupil = 0.94 }
        case .asleep:
            both { $0.arc = -1 }
        case .drowsy:
            both { $0.lidTop = 0.56; $0.py = 0.35; $0.pupil = 0.92 }
            e.gaze = 0.3
        case .worried:
            both { $0.lidTop = 0.20; $0.slant = -0.75; $0.pupil = 0.80; $0.py = 0.20 }
            e.gaze = 0.6
        case .confused:
            e.left.scale = 1.10; e.right.scale = 0.88
            e.left.px = cos(t * 9) * 0.85;  e.left.py = sin(t * 9) * 0.85
            e.right.px = cos(-t * 7 + 2) * 0.85; e.right.py = sin(-t * 7 + 2) * 0.85
            both { $0.pupil = 0.82 }
            e.gaze = 0
        case .annoyed:
            both { $0.lidTop = 0.36; $0.slant = 0.85; $0.lidBottom = 0.12; $0.pupil = 0.90 }
        case .surprised:
            both { $0.scale = 1.16; $0.pupil = 0.66 }
        case .panicked:
            both { $0.scale = 1.20; $0.pupil = 0.50 }
            e.left.px = sin(t * 47) * 0.30;  e.left.py = cos(t * 39) * 0.24
            e.right.px = sin(t * 43 + 1) * 0.30; e.right.py = cos(t * 51 + 2) * 0.24
            e.gaze = 0.35
        case .wink:
            e.right.arc = 1
            e.left.lidBottom = 0.18
        case .love:
            both { $0.scale = 1.08; $0.heart = 1 }
            e.gaze = 0.5
        case .proud:
            both { $0.lidBottom = 0.26; $0.pupil = 1.12; $0.sparkle = 1; $0.py = -0.25 }
        case .eager:
            both { $0.scale = 1.12; $0.pupil = 1.10 }
        case .content:
            both { $0.arc = 1 }
        }
        return e
    }
}

enum YumiSkin {
    // Palette of the concept sheet
    static let ink    = YumiRGB(hex: 0x0B0F1A)
    static let indigo = YumiRGB(hex: 0x2A2A8C)
    static let blue   = YumiRGB(hex: 0x5B8CFF)
    static let violet = YumiRGB(hex: 0xC77DFF)
    static let rose   = YumiRGB(hex: 0xFF8AD0)
    static let white  = YumiRGB(hex: 0xFFFFFF)
    static let heart  = YumiRGB(hex: 0xFF5C9A)

    // Body half-size in units of R (R is half of the "diameter" used by the layouts)
    static let bodyHW: CGFloat = 1.14
    static let bodyHH: CGFloat = 0.88
    // The box the body morphs into while it waits for a file
    static let boxHW: CGFloat = 1.0
    static let boxHH: CGFloat = 0.94
    static let boxCorner: CGFloat = 0.42

    // MARK: Silhouette

    /// Point of the dome outline for angle `a`, in a -1…1 box (y down): round on top,
    /// wider and almost flat at the base.
    static func domePoint(_ a: CGFloat) -> CGPoint {
        let ca = cos(a), sa = sin(a)
        let n: CGFloat = sa < 0 ? domeTop : domeBase
        var x = (ca < 0 ? -1 : 1) * pow(abs(ca), 2 / n)
        let y = (sa < 0 ? -1 : 1) * pow(abs(sa), 2 / n)
        x *= domeTaper(y) / domeWidest
        return CGPoint(x: x, y: y)
    }

    private static let domeTop: CGFloat = 2.1     // superellipse exponent above the centre
    private static let domeBase: CGFloat = 3.1    // and below: squarer, so the base reads flat
    private static func domeTaper(_ y: CGFloat) -> CGFloat { 1 - 0.25 * pow((1 - y) / 2, 1.25) }

    /// Widest half-width of the tapered outline before normalisation.
    private static let domeWidest: CGFloat = {
        var m: CGFloat = 0
        for i in 0...200 {
            let y = CGFloat(i) / 200
            let x = pow(1 - pow(y, domeBase), 1 / domeBase) * domeTaper(y)
            m = max(m, x)
        }
        return m
    }()

    /// Body outline. `morph` 0 is the dome, 1 the rounded box of half-size `boxHW` × `boxHH`.
    static func bodyPath(hw: CGFloat, hh: CGFloat, morph: CGFloat = 0,
                         boxHW: CGFloat = 0, boxHH: CGFloat = 0, boxCorner: CGFloat = 0) -> CGPath {
        let n = 96
        let m = max(0, min(1, morph))
        let path = CGMutablePath()
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let d = domePoint(a)
            var p = CGPoint(x: d.x * hw, y: d.y * hh)
            if m > 0.005 {
                let b = boxPoint(ca: cos(a), sa: sin(a), W: boxHW, H: boxHH, cr: boxCorner)
                p = CGPoint(x: p.x + (b.x - p.x) * m, y: p.y + (b.y - p.y) * m)
            }
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Where the ray of direction (ca, sa) leaves a rounded rectangle of half-size W × H.
    static func boxPoint(ca: CGFloat, sa: CGFloat, W: CGFloat, H: CGFloat, cr: CGFloat) -> CGPoint {
        let eps: CGFloat = 1e-6
        let kx: CGFloat = ca >= 0 ? 1 : -1
        let ky: CGFloat = sa >= 0 ? 1 : -1
        let cx = kx * (W - cr)
        let cy = ky * (H - cr)

        let dot  = ca * cx + sa * cy
        let disc = dot * dot - (cx * cx + cy * cy - cr * cr)
        if disc >= 0 {
            let t = dot + sqrt(disc)
            if t > eps {
                let px = ca * t, py = sa * t
                if abs(px) >= W - cr - eps && abs(py) >= H - cr - eps { return CGPoint(x: px, y: py) }
            }
        }
        if abs(sa) > eps {
            let t = (ky * H) / sa
            if t > eps {
                let x = ca * t
                if abs(x) <= W - cr + eps { return CGPoint(x: x, y: ky * H) }
            }
        }
        if abs(ca) > eps {
            let t = (kx * W) / ca
            if t > eps {
                let y = sa * t
                if abs(y) <= H - cr + eps { return CGPoint(x: kx * W, y: y) }
            }
        }
        return CGPoint(x: kx * W, y: ky * H)
    }

    // MARK: Body

    private static func gradient(_ stops: [(YumiRGB, CGFloat, CGFloat)]) -> CGGradient? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var comps: [CGFloat] = []
        var locs: [CGFloat] = []
        for (c, alpha, loc) in stops {
            comps += [c.r, c.g, c.b, alpha]
            locs.append(loc)
        }
        return CGGradient(colorSpace: cs, colorComponents: comps, locations: locs, count: stops.count)
    }

    /// Rim thickness for a body of unit R. Never under a point, so the outline survives at 12 pt.
    static func rimWidth(_ R: CGFloat) -> CGFloat { max(R * 0.085, 1.0) }

    /// Black body carried by its rim light. The island is black too: without the rim the
    /// silhouette disappears, so the rim is drawn crisp, with a soft bloom behind it.
    /// `glow` (0…1) adds a halo outside the body; `shine` the soft reflection of the sheet.
    static func drawBody(_ ctx: CGContext, path: CGPath, hw: CGFloat, hh: CGFloat, R: CGFloat,
                         rim: YumiRim, glow: CGFloat = 0, shine: Bool = true, alpha: CGFloat = 1) {
        if glow > 0.01 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: R * 0.5, color: rim.mid.cg(0.60 * glow * alpha))
            ctx.addPath(path)
            ctx.setFillColor(ink.cg(alpha))
            ctx.fillPath()
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if alpha < 1 { ctx.setAlpha(alpha) }

        if let g = gradient([(ink.mix(indigo, 0.16), 1, 0), (ink, 1, 0.55), (ink.mix(YumiRGB(0, 0, 0), 0.35), 1, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: -hh), end: CGPoint(x: 0, y: hh),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        // Rim: the body minus a copy of itself pushed up and squeezed, which leaves a
        // crescent that is thicker at the base and on the sides than at the top.
        let t = rimWidth(R)
        let rimGradient = gradient([(rim.left, 1, 0), (rim.mid, 1, 0.52), (rim.right, 1, 1)])
        // A stack of wider, fainter crescents stands in for a blur behind the crisp one.
        // More of them on a large body, where the steps would show.
        let bloom = R > 9 ? min(32, max(9, Int(R / 5))) : 2
        var layers: [(CGFloat, CGFloat)] = (0..<bloom).map { i in
            let k = CGFloat(i) / CGFloat(bloom - 1)   // 0 widest, 1 narrowest
            return (1.5 + (1 - k) * (R > 9 ? 3.4 : 0.6), R > 9 ? (0.015 + 0.06 * k) * 9 / CGFloat(bloom) : 0.16)
        }
        layers.append((1, 1))
        for (k, a) in layers {
            let side = t * k, bottom = t * k * 1.15, top = t * (0.30 + (k - 1) * 0.25)
            var tr = CGAffineTransform(translationX: 0, y: (top - bottom) / 2)
                .scaledBy(x: max(0.05, 1 - side / hw), y: max(0.05, 1 - (top + bottom) / (2 * hh)))
            guard let inner = path.copy(using: &tr), let g = rimGradient else { continue }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.addPath(inner)
            ctx.clip(using: .evenOdd)
            ctx.setAlpha(a * alpha)
            ctx.drawLinearGradient(g, start: CGPoint(x: -hw, y: -hh * 0.35), end: CGPoint(x: hw, y: hh * 0.55),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }

        if shine && R > 9, let g = gradient([(blue.mix(white, 0.35), 0.20, 0), (blue, 0, 1)]) {
            let c = CGPoint(x: -hw * 0.40, y: -hh * 0.52)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: R * 0.62, options: [])
        }
        ctx.restoreGState()
    }

    // MARK: Eyes

    /// Eyes grow relative to the body when it gets small (compact island, mini characters).
    static func eyeBoost(_ R: CGFloat) -> CGFloat {
        let k = max(0, min(1, (R - 7) / 6))
        return 1.35 - 0.35 * (k * k * (3 - 2 * k))
    }

    /// Two white ovals with a round black pupil and a small reflection. `gaze` is the look
    /// direction (-1…1, y down), `open` the blink (1 open), `scale` the tweened eye scale.
    static func drawEyes(_ ctx: CGContext, R: CGFloat, eyes: YumiEyes, gaze: CGPoint = .zero,
                         open: CGFloat = 1, scale: CGFloat = 1, offset: CGPoint = .zero) {
        let boost = eyeBoost(R)
        let spacing = R * 0.34 * (1 + (boost - 1) * 0.6)
        for side: CGFloat in [-1, 1] {
            let e = side < 0 ? eyes.left : eyes.right
            let w = R * 0.50 * boost * scale * e.scale
            let h = R * 0.64 * boost * scale * e.scale
            ctx.saveGState()
            ctx.translateBy(x: offset.x + side * spacing, y: offset.y - R * 0.10)
            drawEye(ctx, e, side: side, w: w, h: h, R: R,
                    gaze: CGPoint(x: gaze.x * eyes.gaze, y: gaze.y * eyes.gaze), open: open)
            ctx.restoreGState()
        }
    }

    private static func drawEye(_ ctx: CGContext, _ e: YumiEye, side: CGFloat, w: CGFloat, h: CGFloat,
                                R: CGFloat, gaze: CGPoint, open: CGFloat) {
        let o = max(0, min(1, open)) * (1 - min(1, abs(e.arc)))

        // Closed: a white stroke, bent like a smile or like a sleeping eye.
        if o < 0.14 {
            let lw = max(w * 0.22, 0.9)
            let bend = e.arc * h * 0.28
            let x = max(w / 2 - lw / 2, lw * 0.3)
            ctx.setStrokeColor(white.cg())
            ctx.setLineWidth(lw)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -x, y: bend / 2))
            ctx.addQuadCurve(to: CGPoint(x: x, y: bend / 2), control: CGPoint(x: 0, y: -bend * 1.5))
            ctx.strokePath()
            return
        }

        let eh = h * o
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: -w / 2, y: -eh / 2, width: w, height: eh))
        ctx.clip()

        if e.lidTop > 0.001 || e.lidBottom > 0.001 || abs(e.slant) > 0.001 {
            let top = -eh / 2 + e.lidTop * eh
            func lid(_ x: CGFloat) -> CGFloat { top + e.slant * (-side) * (x / (w / 2)) * eh * 0.30 }
            let apex = eh / 2 - e.lidBottom * eh
            let edge = apex + e.lidBottom * eh * 0.9
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -w, y: lid(-w)))
            ctx.addLine(to: CGPoint(x: w, y: lid(w)))
            ctx.addLine(to: CGPoint(x: w, y: edge))
            ctx.addLine(to: CGPoint(x: w * 0.56, y: edge))
            ctx.addQuadCurve(to: CGPoint(x: -w * 0.56, y: edge), control: CGPoint(x: 0, y: 2 * apex - edge))
            ctx.addLine(to: CGPoint(x: -w, y: edge))
            ctx.closePath()
            ctx.clip()
        }

        ctx.setFillColor(white.cg())
        ctx.fill(CGRect(x: -w, y: -h, width: w * 2, height: h * 2))

        // Pupil
        let pr = w * 0.33 * e.pupil
        var gx = gaze.x + e.px, gy = gaze.y + e.py
        let len = hypot(gx, gy)
        if len > 1 { gx /= len; gy /= len }
        let cx = gx * max(0, w / 2 - pr) * 0.92
        let cy = gy * max(0, h / 2 - pr) * 0.82
        if e.heart < 0.99 {
            ctx.setFillColor(ink.cg(1 - e.heart))
            ctx.fillEllipse(in: CGRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2))
        }
        if e.heart > 0.01 {
            let s = pr * 1.55
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: cy + s * 0.62))
            ctx.addCurve(to: CGPoint(x: cx, y: cy - s * 0.30),
                         control1: CGPoint(x: cx - s * 1.25, y: cy - s * 0.10),
                         control2: CGPoint(x: cx - s * 0.55, y: cy - s * 0.95))
            ctx.addCurve(to: CGPoint(x: cx, y: cy + s * 0.62),
                         control1: CGPoint(x: cx + s * 0.55, y: cy - s * 0.95),
                         control2: CGPoint(x: cx + s * 1.25, y: cy - s * 0.10))
            ctx.closePath()
            ctx.setFillColor(heart.cg(e.heart))
            ctx.fillPath()
        }
        // Reflections, dropped when they would be under half a point
        if R >= 8 {
            let rr = pr * 0.34
            ctx.setFillColor(white.cg())
            ctx.fillEllipse(in: CGRect(x: cx + pr * 0.36 - rr, y: cy - pr * 0.38 - rr, width: rr * 2, height: rr * 2))
            if e.sparkle > 0.01 {
                let r2 = pr * 0.22 * e.sparkle
                ctx.fillEllipse(in: CGRect(x: cx - pr * 0.42 - r2, y: cy + pr * 0.36 - r2, width: r2 * 2, height: r2 * 2))
            }
        }
        ctx.restoreGState()
    }

    /// Soft pink cheeks under the eyes.
    static func drawBlush(_ ctx: CGContext, R: CGFloat, amount: CGFloat, offset: CGPoint = .zero) {
        guard amount > 0.01, let g = gradient([(heart, 0.60 * min(1, amount), 0), (heart, 0, 1)]) else { return }
        for side: CGFloat in [-1, 1] {
            ctx.saveGState()
            ctx.translateBy(x: offset.x + side * R * 0.66, y: offset.y + R * 0.30)
            ctx.scaleBy(x: 1, y: 0.6)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: R * 0.26, options: [])
            ctx.restoreGState()
        }
    }

    // MARK: Arms and mouth

    /// A small arm: a capsule of the same material as the body, centred on the current origin.
    static func drawArm(_ ctx: CGContext, length: CGFloat, thickness: CGFloat, R: CGFloat, rim: YumiRim) {
        guard length > 0.3, thickness > 0.3 else { return }
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        let r = min(length, thickness) / 2
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        drawBody(ctx, path: path, hw: length / 2, hh: thickness / 2, R: R * 0.7, rim: rim, shine: false)
    }

    /// The mouth that opens on top of the box: lit from the inside by the rim colour.
    static func drawMouth(_ ctx: CGContext, body: CGPath, rect: CGRect, rim: YumiRim, alpha: CGFloat = 1) {
        guard rect.height > 0.3, rect.width > 0.3 else { return }
        let r = min(rect.width / 2, rect.height / 2)
        let hole = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.setAlpha(alpha)
        ctx.saveGState()
        ctx.addPath(hole)
        ctx.clip()
        if let g = gradient([(YumiRGB(0, 0, 0), 1, 0), (indigo.mix(rim.mid, 0.35), 1, 1)]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.restoreGState()
        if rect.height > 2 {
            ctx.addPath(hole)
            ctx.setStrokeColor(rim.mid.mix(white, 0.25).cg(0.9))
            ctx.setLineWidth(1)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: Whole character

    /// Yumi at rest, centred on the origin: used for the mini characters of the greeting
    /// and by the icon generator.
    static func drawFigure(_ ctx: CGContext, R: CGFloat, rim: YumiRim = .idle, eyes: YumiEyes = YumiEyes(),
                           gaze: CGPoint = .zero, glow: CGFloat = 0) {
        let hw = R * bodyHW, hh = R * bodyHH
        let path = bodyPath(hw: hw, hh: hh)
        drawBody(ctx, path: path, hw: hw, hh: hh, R: R, rim: rim, glow: glow)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        drawEyes(ctx, R: R, eyes: eyes, gaze: gaze)
        ctx.restoreGState()
    }
}
// <<< YumiSkin

// MARK: - Bot state configs

let BotStates: [BotState: BotStateCfg] = [
    .idle: BotStateCfg(
        color: CGColor(red:0.902,green:0.914,blue:0.933,alpha:1), tint:0,
        eye:.pill, badge:nil,
        badgeColor: .white, glow: CGColor(red:1,green:1,blue:1,alpha:0.35), glowOpacity:0.25,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:nil),
    .working: BotStateCfg(
        color: CGColor(red:0.231,green:0.620,blue:1,alpha:1), tint:0.72,
        eye:.focused, badge:.dots(CGColor(red:0.231,green:0.620,blue:1,alpha:1)),
        badgeColor: CGColor(red:0.231,green:0.620,blue:1,alpha:1),
        glow: CGColor(red:0.231,green:0.620,blue:1,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"work"),
    .thinking: BotStateCfg(
        color: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1), tint:0.72,
        eye:.thoughtful, badge:.dots(CGColor(red:0.545,green:0.361,blue:0.965,alpha:1)),
        badgeColor: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1),
        glow: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1), glowOpacity:0.5,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look: CGPoint(x:0.55, y:0.55), tilt:0, sound:"think"),
    .searching: BotStateCfg(
        color: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1), tint:0.72,
        eye:.curious, badge:.dots(CGColor(red:0.388,green:0.396,blue:0.949,alpha:1)),
        badgeColor: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1),
        glow: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1), glowOpacity:0.55,
        bounces:false, scans:true, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"search"),
    .approval: BotStateCfg(
        color: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1), tint:0.78,
        eye:.wide, badge:.bang(CGColor(red:0.961,green:0.647,blue:0.141,alpha:1)),
        badgeColor: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1),
        glow: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1), glowOpacity:0.6,
        bounces:true, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"approval"),
    .question: BotStateCfg(
        color: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1), tint:0.75,
        eye:.curious, badge:.question(CGColor(red:0.133,green:0.827,blue:0.933,alpha:1)),
        badgeColor: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1),
        glow: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0.17, sound:"question"),
    .error: BotStateCfg(
        color: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1), tint:0.78,
        eye:.flat, badge:.dot(CGColor(red:0.957,green:0.314,blue:0.369,alpha:1)),
        badgeColor: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1),
        glow: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"error"),
    .finished: BotStateCfg(
        color: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1), tint:0.72,
        eye:.happy, badge:.dot(CGColor(red:0.204,green:0.831,blue:0.600,alpha:1)),
        badgeColor: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1),
        glow: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1), glowOpacity:0.5,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"finish"),
    .ratelimit: BotStateCfg(
        color: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1), tint:0.72,
        eye:.panicked, badge:.dot(CGColor(red:0.984,green:0.573,blue:0.235,alpha:1)),
        badgeColor: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1),
        glow: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1), glowOpacity:0.45,
        bounces:false, scans:false, breathes:false, zz:false, sweat:true,
        look:nil, tilt:0, sound:"rate"),
    .sleeping: BotStateCfg(
        color: CGColor(red:0.580,green:0.635,blue:0.722,alpha:1), tint:0.32,
        eye:.closed, badge:nil,
        badgeColor: .white,
        glow: CGColor(red:0.580,green:0.635,blue:0.722,alpha:1), glowOpacity:0.2,
        bounces:false, scans:false, breathes:true, zz:true, sweat:false,
        look:nil, tilt:0, sound:"sleep"),
    .dizzy: BotStateCfg(
        color: CGColor(red:0.957,green:0.447,blue:0.714,alpha:1), tint:0.7,
        eye:.spiral, badge:nil,
        badgeColor: .white,
        glow: CGColor(red:0.957,green:0.447,blue:0.714,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"dizzy"),
]

// MARK: - Bot engine

@MainActor
final class BotEngine: ObservableObject {
    var isMini: Bool = false
    var bodyColor: CGColor? = nil    // rim colour override for mini bots

    // Animation state (mirrors prototype 's' object)
    var yaw:    CGFloat = 0
    var pitch:  CGFloat = 0
    var roll:   CGFloat = 0
    var tilt:   CGFloat = 0
    var open:   CGFloat = 1          // eye open amount
    var sx:     CGFloat = 1          // scale X
    var sy:     CGFloat = 1          // scale Y
    var oy:     CGFloat = 0          // offset Y (bounce)
    var ox:     CGFloat = 0          // offset X (shake)
    var tint:   CGFloat = 0
    var morph:  CGFloat = 0          // morph to rect (for upload bucket)
    var hands:  CGFloat = 0
    var blush:  CGFloat = 0
    var es:     CGFloat = 1          // eye scale
    var badgeS: CGFloat = 0          // badge scale
    var eyes = YumiEyes()            // current expression, eased towards the target one
    var rimMix: CGFloat = 0          // 0 = resting gradient, 1 = rim fully in the state colour
    var flat:   CGFloat = 0          // sleeping pose (flattened)

    // Targets
    var tgYaw:    CGFloat = 0
    var tgPitch:  CGFloat = 0
    var tgTilt:   CGFloat = 0
    var tgSy:     CGFloat = 1
    var tgSx:     CGFloat = 1
    var tgEs:     CGFloat = 1   // eye-scale target (hover love: 1.08, normal: 1)

    // Particle canvas overhang (extra canvas height at top for hearts to fly into)
    var particleOverhang: CGFloat = 0

    // Mouth spring (fraction of R: 0=closed, 0.20=hover, 0.42=open, 0.50=overopen)
    var slotH: CGFloat = 0           // current height (fraction of R)
    var slotHTarget: CGFloat = 0     // spring target
    var slotHVel: CGFloat = 0        // spring velocity (fraction of R / s)
    var isChewing: Bool = false       // true for ~800ms after gulp swallow

    // Color (animated)
    var col:  (CGFloat, CGFloat, CGFloat) = (0.902, 0.914, 0.933)  // idle
    var colT: (CGFloat, CGFloat, CGFloat) = (0.902, 0.914, 0.933)

    // State
    var state: BotState = .idle
    var cfg: BotStateCfg = BotStates[.idle]!

    // Eye override (emote)
    var eyeOverride: EyeShape? = nil
    var eyeOverrideUntil: Double = 0   // CACurrentMediaTime()
    var permanentEye: EyeShape? = nil   // restored after temporary emote/blink expires
    var permanentEmote: BotEmote? = nil // stored so doMiniBehaviorLoop can switch on it
    var miniNextBehavior: Double = 0    // CACurrentMediaTime() of next periodic mini action

    // Badge animation
    var badge: BadgeType? = nil
    var badgeKey: String = "none"
    var badgeToken: Int = 0

    // Tweens (keyed by property name)
    var tweens: [String: Tween] = [:]
    var locks:  Set<String> = []

    // Particles
    var particles: [Particle] = []

    // Look target
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0

    // Timing
    var lastTime: Double = CACurrentMediaTime()
    var t0: Double = CACurrentMediaTime() - Double.random(in: 0...5)
    var nextBlink: Double = CACurrentMediaTime() + 1.5 + Double.random(in: 0...2)
    var waveUntil: Double = 0
    var waveStart: Double = 0     // CACurrentMediaTime() when wave animation began
    var greetToken: Int = 0       // incremented to invalidate stale greet closures
    var lastAmbient: Double = 0

    // Slap tracking (for dizzy on 3 slaps)
    var slapTimes: [Double] = []

    // Mini wandering look (random, ignores mouse)
    var miniLookTarget: CGPoint = .zero
    var miniLookNextTime: Double = 0

    // MARK: - Public API

    func setState(_ newState: BotState, force: Bool = false) {
        guard state != newState || force else { return }
        let prev = state
        state = newState
        cfg = BotStates[newState]!
        colT = cgColorToTuple(cfg.color)
        setTarget(key: "tint", value: cfg.tint)
        setTarget(key: "tilt", value: cfg.tilt)
        setBadge(cfg.badge)

        switch newState {
        case .finished:
            doRoll(duration: 950, turns: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.emit(.spark, count: 5)
            }
        case .error:
            anim("ox", keys: [
                TweenKey(target: 0.08,  duration: 50,  ease: Ease.out),
                TweenKey(target: -0.08, duration: 70,  ease: Ease.inOut),
                TweenKey(target: 0.05,  duration: 70,  ease: Ease.inOut),
                TweenKey(target: 0,     duration: 90,  ease: Ease.out),
            ])
        case .approval:
            anim("oy", keys: [
                TweenKey(target: -0.2, duration: 150, ease: Ease.out),
                TweenKey(target: 0,    duration: 300, ease: Ease.back),
            ])
        case .dizzy:
            doRoll(duration: 1300, turns: 2)
        case .question:
            blink()
        case .ratelimit:
            emit(.sweat, count: 1)
        default:
            if prev != .idle || newState != .idle { blink() }
        }
    }

    func setBadge(_ b: BadgeType?) {
        let key = badgeString(b)
        guard key != badgeKey else { return }
        badgeKey = key
        let tok = badgeToken + 1
        badgeToken = tok
        anim("badgeS", keys: [TweenKey(target: 0, duration: 90, ease: Ease.inOut)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, tok == self.badgeToken else { return }
            self.badge = b
            if b != nil {
                self.anim("badgeS", keys: [TweenKey(target: 1, duration: 280, ease: Ease.back)])
            }
        }
    }

    func blink() {
        guard !locks.contains("open") else { return }
        anim("open", keys: [
            TweenKey(target: 0.06, duration: 70,  ease: Ease.inOut),
            TweenKey(target: 1,    duration: 130, ease: Ease.out),
        ])
    }

    func squash() {
        anim("sy", keys: [
            TweenKey(target: 0.78, duration: 70,  ease: Ease.out),
            TweenKey(target: 1.1,  duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.16, duration: 70,  ease: Ease.out),
            TweenKey(target: 0.95, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
    }

    // MARK: - Gulp (mailbox swallow)

    func gulp() {
        // Open mouth wide for the swallow, then close during chewing
        slotHTarget = 0.42
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) { [weak self] in
            self?.slotHTarget = 0
            self?.isChewing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) { [weak self] in
                self?.isChewing = false
            }
        }
        anim("sy", keys: [
            TweenKey(target: 0.78, duration: 80,  ease: Ease.out),
            TweenKey(target: 1.18, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.28, duration: 80,  ease: Ease.out),
            TweenKey(target: 0.92, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        blink()
    }

    // MARK: - Slap (dizzy mechanic)

    func slap() {
        interruptGreet()
        guard state != .dizzy else { return }
        let now = CACurrentMediaTime()
        slapTimes = slapTimes.filter { now - $0 < 1.7 }
        slapTimes.append(now)
        SoundEngine.shared.play("slap")
        squash()
        if slapTimes.count >= 3 {
            slapTimes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        } else {
            // Annoyed: line eyes for 800ms, annoyed sound after 60ms delay
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                SoundEngine.shared.play("annoyed")
            }
        }
    }

    // MARK: - Mini periodic behavior loop

    func doMiniBehaviorLoop() {
        switch permanentEmote {

        case .happy:
            // Little jump + squash
            guard !locks.contains("oy") else {
                miniNextBehavior = CACurrentMediaTime() + 0.4
                return
            }
            anim("oy", keys: [
                TweenKey(target: -0.30, duration: 120, ease: Ease.out),
                TweenKey(target:  0.03, duration: 200, ease: Ease.inOut),
                TweenKey(target:  0,    duration: 160, ease: Ease.back),
            ])
            anim("sy", keys: [
                TweenKey(target: 0.82, duration: 80,  ease: Ease.out),
                TweenKey(target: 1.18, duration: 130, ease: Ease.out),
                TweenKey(target: 0.88, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 1.15, duration: 80,  ease: Ease.out),
                TweenKey(target: 0.88, duration: 130, ease: Ease.out),
                TweenKey(target: 1.06, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...1.2)

        case .annoyed:
            // Rapid head shake
            guard !locks.contains("yaw") else {
                miniNextBehavior = CACurrentMediaTime() + 0.5
                return
            }
            anim("yaw", keys: [
                TweenKey(target: -0.65, duration: 50,  ease: Ease.out),
                TweenKey(target:  0.65, duration: 90,  ease: Ease.inOut),
                TweenKey(target: -0.5,  duration: 80,  ease: Ease.inOut),
                TweenKey(target:  0.4,  duration: 75,  ease: Ease.inOut),
                TweenKey(target: -0.2,  duration: 70,  ease: Ease.inOut),
                TweenKey(target:  0,    duration: 140, ease: Ease.out),
            ])
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.5)

        case .wink:
            // Brief wink: eye closes, head tilts slightly
            let now2 = CACurrentMediaTime()
            eyeOverride = .wink
            eyeOverrideUntil = now2 + 0.55
            anim("tilt", keys: [
                TweenKey(target:  0.13, duration: 100, ease: Ease.out),
                TweenKey(target:  0.13, duration: 320, ease: Ease.lin),
                TweenKey(target:  0,    duration: 200, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...2.0)

        case .love:
            // Emit hearts + gentle sway
            emit(.heart, count: 2)
            anim("tilt", keys: [
                TweenKey(target: -0.1, duration: 180, ease: Ease.out),
                TweenKey(target:  0.1, duration: 340, ease: Ease.inOut),
                TweenKey(target:  0,   duration: 220, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.6 + Double.random(in: 0...1.5)

        default:
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.0)
        }
    }

    func doRoll(duration: CGFloat, turns: CGFloat) {
        roll = 0
        anim("roll", keys: [TweenKey(target: .pi * 2 * turns, duration: duration, ease: Ease.inOut)]) { [weak self] in
            self?.roll = 0
        }
    }

    func greet() {
        let now = CACurrentMediaTime()
        greetToken += 1
        let tok = greetToken
        waveStart = now + 0.45   // wave begins at 0.45s
        waveUntil = now + 1.55   // wave ends at 1.55s

        // 0s: happy eyes for full greeting (2s — no gap, no flicker)
        eyeOverride = .happy
        eyeOverrideUntil = now + 2.0
        anim("oy", keys: [
            TweenKey(target: -0.06, duration: 220, ease: Ease.out),
            TweenKey(target:  0.0,  duration: 220, ease: Ease.back),
        ])

        // 0.25s: hands out + body squash + sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.anim("hands", keys: [TweenKey(target: 1, duration: 280, ease: Ease.out)])
            self.anim("sy", keys: [
                TweenKey(target: 0.95, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            self.anim("sx", keys: [
                TweenKey(target: 1.04, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            SoundEngine.shared.play("greet")
        }

        // 0.55s: first blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.blink()
        }

        // 1.50s: second blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.50) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.blink()
        }

        // 1.55s: retract hands
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.waveUntil = 0
            self.anim("hands", keys: [TweenKey(target: 0, duration: 200, ease: Ease.inOut)])
        }

        // 1.75s: brief happy eyes then back to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.eyeOverride = .happy
            self.eyeOverrideUntil = CACurrentMediaTime() + 0.30
        }
    }

    /// Immediately interrupts an in-progress greeting (hands retract in 150 ms).
    func interruptGreet() {
        guard hands > 0.01 || CACurrentMediaTime() < waveUntil else { return }
        greetToken += 1   // invalidate any pending closures
        waveUntil = 0
        waveStart = 0
        anim("hands", keys: [TweenKey(target: 0, duration: 150, ease: Ease.inOut)])
    }

    /// Sets a permanent eye expression that survives blinks and transient emotes.
    func setPermanentEmote(_ emote: BotEmote?) {
        permanentEmote = emote
        // .wink fires periodically — don't freeze the eye (normal between winks)
        if emote == .wink {
            miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
            return
        }
        permanentEye = emote.map { emoteEyeShape($0) }
        if let eye = permanentEye {
            eyeOverride = eye
            eyeOverrideUntil = .greatestFiniteMagnitude
        } else {
            if eyeOverrideUntil == .greatestFiniteMagnitude {
                eyeOverride = nil
                eyeOverrideUntil = 0
            }
        }
        // Stagger first periodic behavior so bots don't all fire at once
        miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
    }

    func triggerEmote(_ emote: BotEmote, duration: Double = 1.8, silent: Bool = false) {
        let now = CACurrentMediaTime()
        eyeOverride = emoteEyeShape(emote)
        eyeOverrideUntil = now + duration

        switch emote {
        case .love:
            anim("blush", keys: [
                TweenKey(target: 1, duration: 300, ease: Ease.out),
                TweenKey(target: 1, duration: CGFloat((duration - 0.6) * 1000), ease: Ease.lin),
                TweenKey(target: 0, duration: 300, ease: Ease.inOut),
            ])
            emit(.heart, count: 4)
            anim("oy", keys: [
                TweenKey(target: -0.1, duration: 160, ease: Ease.out),
                TweenKey(target: 0,    duration: 300, ease: Ease.back),
            ])
        case .surprised:
            anim("oy", keys: [
                TweenKey(target: -0.3, duration: 140, ease: Ease.out),
                TweenKey(target: 0,    duration: 380, ease: Ease.back),
            ])
            anim("es", keys: [
                TweenKey(target: 1.25, duration: 120, ease: Ease.out),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
        case .proud:
            emit(.star, count: 5)
            anim("tilt", keys: [
                TweenKey(target: -0.14, duration: 220, ease: Ease.out),
                TweenKey(target: -0.14, duration: CGFloat((duration - 0.5) * 1000), ease: Ease.lin),
                TweenKey(target: 0,     duration: 280, ease: Ease.inOut),
            ])
            anim("blush", keys: [
                TweenKey(target: 0.7, duration: 250, ease: Ease.out),
                TweenKey(target: 0.7, duration: CGFloat((duration - 0.5) * 1000), ease: Ease.lin),
                TweenKey(target: 0,   duration: 300, ease: Ease.inOut),
            ])
        case .wink:
            anim("tilt", keys: [
                TweenKey(target: 0.12, duration: 160, ease: Ease.out),
                TweenKey(target: 0.12, duration: CGFloat((duration - 0.4) * 1000), ease: Ease.lin),
                TweenKey(target: 0,    duration: 240, ease: Ease.inOut),
            ])
        case .yawn:
            anim("sy", keys: [
                TweenKey(target: 1.12, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
            anim("sx", keys: [
                TweenKey(target: 0.94, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.eyeOverride = .closed
                self?.emit(.z, count: 2)
            }
        case .happy:
            anim("blush", keys: [
                TweenKey(target: 0.6, duration: 200, ease: Ease.out),
                TweenKey(target: 0,   duration: 600, ease: Ease.inOut),
            ])
        case .annoyed:
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                SoundEngine.shared.play("annoyed")
            }
        }
    }

    func emit(_ type: Particle.ParticleType, count: Int) {
        for i in 0..<count {
            let isZ = type == .z
            let p = Particle(
                type: type,
                x: (CGFloat.random(in: -0.5...0.5)) * 0.9 + (isZ ? 0.55 : 0),
                y: -0.7 - CGFloat.random(in: 0...0.2),
                vx: CGFloat.random(in: -0.5...0.5) * 0.35 + (isZ ? 0.18 : 0),
                vy: -(0.45 + CGFloat.random(in: 0...0.35)),
                age: -Double(i) * 0.14,
                life: 1.3 + Double.random(in: 0...0.5),
                rot: CGFloat.random(in: 0...(.pi * 2)),
                size: 0.15 + CGFloat.random(in: 0...0.08)
            )
            particles.append(p)
        }
    }

    // MARK: - Update (called every frame from TimelineView)

    func update(dt: Double) {
        let now = CACurrentMediaTime()
        let dtCG = CGFloat(dt)

        // Process tweens
        for key in tweens.keys {
            guard var tw = tweens[key] else { continue }
            let k = tw.keys[tw.keyIndex]
            let elapsed = now * 1000 - tw.startTime
            let p = min(1, max(0, CGFloat(elapsed) / k.duration))
            let val = tw.from + (k.target - tw.from) * k.ease(p)
            setProperty(key, value: val)

            if p >= 1 {
                tw.from = k.target
                tw.keyIndex += 1
                tw.startTime = now * 1000
                if tw.keyIndex >= tw.keys.count {
                    tweens.removeValue(forKey: key)
                    locks.remove(key)
                    tw.onComplete?()
                } else {
                    tweens[key] = tw
                }
            } else {
                tweens[key] = tw
            }
        }

        // Compute look targets
        let t = CGFloat(now - t0)
        var ty: CGFloat = lookX * 0.62
        var tp: CGFloat = lookY * 0.5

        if let fixedLook = cfg.look {
            ty = ty * 0.35 + fixedLook.x * 0.55
            tp = tp * 0.3  + fixedLook.y * 0.5
        }
        if cfg.scans {
            ty = sin(t * 2.6) * 0.6
            tp = -0.06
        }
        if state == .sleeping { ty = 0; tp = -0.14 }
        if state == .dizzy    { ty = sin(t * 9) * 0.25 }

        // Mini bots: override look with random wandering (never follows mouse)
        if isMini && cfg.look == nil && !cfg.scans && state != .sleeping && state != .dizzy {
            if now > miniLookNextTime {
                miniLookTarget = CGPoint(
                    x: CGFloat.random(in: -0.88...0.88),
                    y: CGFloat.random(in: -0.55...0.45)
                )
                miniLookNextTime = now + Double.random(in: 0.5...2.0)
            }
            ty = miniLookTarget.x * 0.62
            tp = miniLookTarget.y * 0.5
        }

        tgYaw   = ty
        tgPitch = tp
        tgTilt  = cfg.tilt

        // Body sway during greeting wave
        if now > waveStart && now < waveUntil {
            let wt = CGFloat(now - waveStart)
            tgTilt = -0.06 + sin(2 * .pi * 1.2 * wt) * 0.07
        }

        let bounce = cfg.bounces ? -abs(sin(t * 5.2)) * 0.07 : CGFloat(0)
        // oy tween can override if not locked
        if !locks.contains("oy") { oy += (bounce - oy) * CGFloat(1 - pow(0.0008, dt)) }

        if cfg.breathes {
            let amp: CGFloat = isMini ? 0.07 : 0.035
            tgSy = 1 + sin(t * 1.8) * amp
            tgSx = 1 - sin(t * 1.8) * amp * 0.57
        } else if isMini {
            // Subtle idle pulse (unique phase per engine via t0)
            tgSy = 1 + sin(t * 2.2) * 0.04
            tgSx = 1 - sin(t * 2.2) * 0.02
        } else {
            tgSy = 1; tgSx = 1
        }

        // Mini bots: periodic dramatic behaviors
        if isMini && now > miniNextBehavior {
            doMiniBehaviorLoop()
        }

        // Smooth look
        let kLook = CGFloat(1 - pow(0.0025, dt))
        let kGen  = CGFloat(1 - pow(0.0008, dt))

        if !locks.contains("yaw")   { yaw   += (tgYaw   - yaw)   * kLook }
        if !locks.contains("pitch") { pitch += (tgPitch  - pitch) * kLook }
        if !locks.contains("tilt")  { tilt  += (tgTilt   - tilt)  * kGen  }
        if !locks.contains("sy")    { sy    += (tgSy     - sy)    * kGen  }
        if !locks.contains("sx")    { sx    += (tgSx     - sx)    * kGen  }
        if !locks.contains("es")    { es    += (tgEs     - es)    * kGen  }

        // Animate color
        col = mixColor(col, colT, 1 - pow(0.002, dt))
        rimMix += (min(1, tint / 0.7) - rimMix) * kGen
        flat   += ((state == .sleeping ? 1 : 0) - flat) * kGen

        // Ease the eyes towards the current expression
        eyes = eyes.mix(yumiExpression(eyeShape).eyes(at: t), CGFloat(1 - pow(0.00001, dt)))

        // Blink
        if now > nextBlink {
            if state != .sleeping && state != .dizzy {
                blink()
                if Double.random(in: 0...1) < 0.22 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self] in self?.blink() }
                }
            }
            nextBlink = now + 2.2 + Double.random(in: 0...3.2)
        }

        // Clear expired eye override (restore permanent if set)
        if eyeOverride != nil && now > eyeOverrideUntil {
            eyeOverride = permanentEye
            if permanentEye != nil { eyeOverrideUntil = .greatestFiniteMagnitude }
        }

        // Ambient particles
        if now - lastAmbient > 1.3 {
            lastAmbient = now
            if cfg.zz { emit(.z, count: 1) }   // ZZZ works for mini too
            if !isMini && cfg.sweat && Double.random(in: 0...1) < 0.5 { emit(.sweat, count: 1) }
        }

        // Age particles
        for i in particles.indices { particles[i].age += dt }
        particles.removeAll { $0.age >= $0.life }

        // Mouth slot spring — ω₀ ≈ 25 rad/s (T=0.25s), ζ=0.6 (underdamped, slight clack)
        let slotOmega: CGFloat = 2 * .pi / 0.25
        let slotZeta: CGFloat = 0.6
        let slotAcc = slotOmega * slotOmega * (slotHTarget - slotH)
                    - 2 * slotZeta * slotOmega * slotHVel
        slotHVel += slotAcc * dtCG
        slotH = max(0, slotH + slotHVel * dtCG)

        lastTime = now
    }

    // MARK: - Draw

    /// Where the body sits in the canvas this frame, with the roll and the sleeping pose applied.
    private struct BodyPose {
        var R, hw, hh, cx, cy, tilt, sx, sy, celebrate: CGFloat
    }

    private func bodyPose(_ size: CGSize) -> BodyPose {
        let R = size.width * 0.3
        let hh = R * YumiSkin.bodyHH
        var p = BodyPose(
            R: R, hw: R * YumiSkin.bodyHW, hh: hh,
            cx: size.width / 2 + ox * R,
            // particleOverhang shifts the bot body down in canvas coords so hearts can fly into
            // the extended canvas above without clipping (BotPlacement compensates with position offset)
            cy: size.height / 2 + particleOverhang / 2 + oy * R + R * 0.06,
            tilt: tilt, sx: sx, sy: sy, celebrate: 0)

        // The "roll" tween runs from 0 to a number of full turns. Yumi is a slime, not a ball:
        // each turn is one hop with the arms up, or one wobble when dizzy.
        if roll != 0 {
            if state == .dizzy {
                p.tilt += sin(roll) * 0.22
            } else {
                let hop = pow(sin(roll / 2), 2)
                p.cy -= hop * R * 0.30
                p.sy *= 1 + 0.10 * sin(roll)
                p.sx *= 1 - 0.06 * sin(roll)
                p.celebrate = hop
            }
        }
        // Sleeping pose: flattened, base planted
        if flat > 0.001 {
            p.sy *= 1 - 0.20 * flat
            p.sx *= 1 + 0.08 * flat
            p.cy += hh * 0.20 * flat
        }
        return p
    }

    /// The body stays black: the state colours the rim light (the brand, for mini characters).
    private var rim: YumiRim {
        if isMini, let bc = bodyColor {
            let c = cgColorToTuple(bc)
            return .solid(YumiRGB(c.0, c.1, c.2))
        }
        return YumiRim.idle.mix(.solid(YumiRGB(col.0, col.1, col.2)), rimMix)
    }

    private var eyeShape: EyeShape {
        // In box mode: eager eyes when file over box (slotHTarget set), closed smile while chewing
        if morph > 0.5 {
            if isChewing { return .content }
            if slotHTarget > 0.05 || slotH > 0.10 { return .cup }
        }
        return eyeOverride ?? cfg.eye
    }

    func draw(context: GraphicsContext, size: CGSize) {
        let p = bodyPose(size)
        let rim = self.rim

        // Body path (dome for Yumi, morph to rect for upload)
        let bodyPath = mochiPath(rx: p.hw, ry: p.hh, morph: morph, R: p.R)
        let glow: CGFloat = isMini ? 0 : 0.45 + 0.55 * cfg.glowOpacity

        context.withCGContext { cg in
            cg.saveGState()
            cg.translateBy(x: p.cx, y: p.cy)
            if p.tilt != 0 { cg.rotate(by: p.tilt) }
            cg.scaleBy(x: p.sx, y: p.sy)

            YumiSkin.drawBody(cg, path: bodyPath, hw: p.hw, hh: p.hh, R: p.R, rim: rim, glow: glow, shine: !isMini)

            // Face: the pupils carry the look, the eyes themselves only slide a little
            cg.saveGState()
            cg.addPath(bodyPath)
            cg.clip()
            let faceOffset = CGPoint(x: yaw * p.R * MochiConst.eyeShiftX,
                                     y: -pitch * p.R * MochiConst.eyeShiftY + p.R * 0.20 * morph)
            let gaze = CGPoint(x: clamp(yaw / MochiConst.lookYaw, -1, 1),
                               y: clamp(-pitch / MochiConst.lookPitch, -1, 1))
            YumiSkin.drawBlush(cg, R: p.R, amount: blush * (1 - morph), offset: faceOffset)
            YumiSkin.drawEyes(cg, R: p.R, eyes: eyes, gaze: gaze, open: open, scale: es, offset: faceOffset)
            cg.restoreGState()

            // Mouth hole inside the box face
            // Spec: left/right margins 0.10R, top margin 0.08R from box top (-0.94R)
            if morph > 0.05 {
                let hW = p.R * 1.80 * morph   // hole width = box width (2×1.0R) − 2×0.10R margin
                let hH = slotH * p.R * morph  // hole height (spring-animated, scaled by morph)
                // Hole Y: box top is -R*0.94 at morph=1, lerped from -R*0.88 at morph=0
                let boxTop = -p.R * (0.88 + 0.06 * morph)
                let hY = boxTop + p.R * 0.08 * morph  // top margin scales with morph
                // Only draw if visibly open
                if hH > 0.8 {
                    YumiSkin.drawMouth(cg, body: bodyPath, rect: CGRect(x: -hW / 2, y: hY, width: hW, height: hH),
                                       rim: rim, alpha: min(1, morph))
                }
            }
            cg.restoreGState()
        }
    }

    // MARK: - Draw arms behind body (called before draw() so they appear under Yumi)

    func drawHandsBehind(context: GraphicsContext, size: CGSize) {
        guard !isMini else { return }
        let p = bodyPose(size)
        let amount = max(hands, p.celebrate)
        // Only draw the arms when Yumi is large enough for them to read (not compact/peek)
        guard amount > 0.01, p.R > 14 else { return }

        let now = CACurrentMediaTime()
        let isWaving = now >= waveStart && waveStart > 0 && now < waveUntil
        let wt = CGFloat(now - waveStart)
        let length = p.R * MochiConst.armLength * amount
        let thick  = p.R * MochiConst.armThick * amount
        let rim = self.rim

        // Body half-dims with current squash scale
        let hwB = p.hw * p.sx
        let hhB = p.hh * p.sy

        context.withCGContext { cg in
            cg.saveGState()
            cg.translateBy(x: p.cx, y: p.cy)
            if p.tilt != 0 { cg.rotate(by: p.tilt) }

            for sd: CGFloat in [-1, 1] {
                var raise = p.celebrate   // 0 = hanging at the side, 1 = raised
                var swing: CGFloat = 0
                if isWaving {
                    if sd > 0 {
                        // Right arm: rise to wave position over first 180ms, then oscillate
                        let rise = min(1.0, wt / 0.18)
                        raise = max(raise, 1 - pow(1 - rise, 3))   // easeOut cubic
                        swing = sin(13 * wt) * 0.35 * raise
                    } else {
                        // Left arm: gentle sway at rest position
                        swing = sin(6 * wt) * 0.10
                    }
                }
                cg.saveGState()
                // Shoulder sits just inside the outline so the arm grows out of the body
                cg.translateBy(x: sd * hwB * (0.90 - 0.10 * raise), y: hhB * (0.42 - 0.62 * raise))
                cg.scaleBy(x: sd, y: 1)
                cg.rotate(by: 0.55 - 1.45 * raise + swing)
                cg.translateBy(x: length * 0.42, y: 0)
                YumiSkin.drawArm(cg, length: length, thickness: thick, R: p.R, rim: rim)
                cg.restoreGState()
            }
            cg.restoreGState()
        }
    }

    func drawHandsAndExtras(context: GraphicsContext, size: CGSize) {
        let p = bodyPose(size)

        // Badge — hidden while morphing to mailbox
        if let badge = badge, badgeS > 0.01, morph < 0.25 {
            drawBadge(context: context, size: size, badge: badge, R: p.R, rx: p.hw, ry: p.hh, cx: p.cx, cy: p.cy)
        }

        // Particles
        drawParticles(context: context, size: size, R: p.R, cx: p.cx, cy: p.cy)
    }

    // MARK: - Private draw helpers

    private func mochiPath(rx: CGFloat, ry: CGFloat, morph: CGFloat, R: CGFloat) -> CGPath {
        // Target mailbox dims (spec: 1.0R wide, 0.94R tall, 0.42R corner radius)
        YumiSkin.bodyPath(hw: rx, hh: ry, morph: morph,
                          boxHW: R * YumiSkin.boxHW, boxHH: R * YumiSkin.boxHH, boxCorner: R * YumiSkin.boxCorner)
    }

    private func drawBadge(context: GraphicsContext, size: CGSize, badge: BadgeType, R: CGFloat, rx: CGFloat, ry: CGFloat, cx: CGFloat, cy: CGFloat) {
        let bs = badgeS * (isMini ? 1.25 : 1)
        let bx = cx - R * 0.72 * sx
        let by = cy - R * 0.72 * sy
        var ctx = context
        ctx.translateBy(x: bx, y: by)
        ctx.scaleBy(x: bs, y: bs)
        let now = CGFloat(CACurrentMediaTime())

        switch badge {
        case .dots(let col):
            if isMini {
                // Mini: animated pulsing dot
                let phase = (now * 2.4).truncatingRemainder(dividingBy: 1)
                let dotR = R * 0.22 * (1 + 0.25 * sin(phase * .pi * 2))
                var outer = Path()
                outer.addEllipse(in: CGRect(x: -R*0.2, y: -R*0.2, width: R*0.4, height: R*0.4))
                ctx.fill(outer, with: .color(.black))
                var dot = Path()
                dot.addEllipse(in: CGRect(x: -dotR, y: -dotR, width: dotR*2, height: dotR*2))
                ctx.fill(dot, with: .color(Color(cgColor: col)))
            } else {
                // Pill badge with animated dots (prototype style)
                let pw: CGFloat = R * 0.72
                let ph: CGFloat = R * 0.36
                var pill = Path()
                pill.addRoundedRect(in: CGRect(x: -pw/2, y: -ph/2, width: pw, height: ph),
                                    cornerSize: CGSize(width: ph/2, height: ph/2))
                ctx.fill(pill, with: .color(Color(cgColor: col)))
                for i in 0..<3 {
                    let phase = ((now * 2.4 - CGFloat(i) * 0.22).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                    let dotR = R * 0.055 * (1 + 0.4 * max(0, sin(phase * .pi * 2)))
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: (CGFloat(i)-1)*R*0.18 - dotR, y: -dotR, width: dotR*2, height: dotR*2))
                    ctx.fill(dot, with: .color(.white))
                }
            }

        case .bang(let col), .question(let col):
            var ring = Path()
            ring.addEllipse(in: CGRect(x: -R*0.3, y: -R*0.3, width: R*0.6, height: R*0.6))
            ctx.fill(ring, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R*0.23, y: -R*0.23, width: R*0.46, height: R*0.46))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
            if !isMini {
                let text = badge == .bang(col) ? "!" : "?"
                ctx.draw(Text(text).font(.system(size: R*0.32, weight: .black)).foregroundColor(.white),
                         at: CGPoint(x: 0, y: R*0.02))
            }

        case .dot(let col):
            var outer = Path()
            outer.addEllipse(in: CGRect(x: -R*0.2, y: -R*0.2, width: R*0.4, height: R*0.4))
            ctx.fill(outer, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R*0.135, y: -R*0.135, width: R*0.27, height: R*0.27))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
        }
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, R: CGFloat, cx: CGFloat, cy: CGFloat) {
        for p in particles {
            guard p.age > 0 else { continue }
            let k = CGFloat(p.age / p.life)
            let a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
            let px = cx + (p.x + p.vx * CGFloat(p.age)) * R * 1.3
            let py = cy + (p.y + p.vy * CGFloat(p.age)) * R * 1.3
            let sz = R * p.size * (1 + k * 0.4)

            var pctx = context
            pctx.translateBy(x: px, y: py)
            pctx.opacity = Double(min(max(a, 0), 1))

            switch p.type {
            case .heart:
                pctx.rotate(by: .radians(sin(CGFloat(p.age) * 6) * 0.3))
                pctx.fill(heartShape(size: sz), with: .color(Color(hex: "#FF4D6D")))
            case .star:
                pctx.rotate(by: .radians(p.rot + CGFloat(p.age) * 2))
                pctx.fill(starShape(outer: sz, inner: sz*0.45), with: .color(Color(hex: "#F7B32B")))
            case .spark:
                pctx.rotate(by: .radians(p.rot))
                pctx.fill(starShape(outer: sz*0.8, inner: sz*0.18), with: .color(.white))
            case .sweat:
                var drop = Path()
                drop.move(to: CGPoint(x: 0, y: -sz))
                drop.addQuadCurve(to: CGPoint(x: 0, y: sz*0.6), control: CGPoint(x: sz*0.8, y: sz*0.2))
                drop.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz*0.8, y: sz*0.2))
                pctx.fill(drop, with: .color(Color(hex: "#7CC7FF")))
            case .z:
                pctx.draw(Text("z").font(.system(size: sz*1.9, weight: .bold)).foregroundColor(Color(red: 0.357, green: 0.549, blue: 1)),
                          at: .zero)
            }
        }
    }

    // MARK: - Tween helpers

    func anim(_ key: String, keys: [TweenKey], onComplete: (() -> Void)? = nil) {
        let current = getProperty(key)
        tweens[key] = Tween(property: key, keys: keys, keyIndex: 0,
                            from: current, startTime: CACurrentMediaTime() * 1000,
                            onComplete: onComplete)
        locks.insert(key)
    }

    private func setTarget(key: String, value: CGFloat) {
        guard !locks.contains(key) else { return }
        switch key {
        case "tint":  tint  += (value - tint)  // immediate target, smoothed in update
        case "tilt":  tgTilt = value
        default: break
        }
    }

    private func setProperty(_ key: String, value: CGFloat) {
        switch key {
        case "yaw":    yaw    = value
        case "pitch":  pitch  = value
        case "roll":   roll   = value
        case "tilt":   tilt   = value
        case "open":   open   = value
        case "sx":     sx     = value
        case "sy":     sy     = value
        case "oy":     oy     = value
        case "ox":     ox     = value
        case "tint":   tint   = value
        case "morph":  morph  = value
        case "hands":  hands  = value
        case "blush":  blush  = value
        case "es":     es     = value
        case "badgeS": badgeS = value
        default: break
        }
    }

    private func getProperty(_ key: String) -> CGFloat {
        switch key {
        case "yaw":    return yaw
        case "pitch":  return pitch
        case "roll":   return roll
        case "tilt":   return tilt
        case "open":   return open
        case "sx":     return sx
        case "sy":     return sy
        case "oy":     return oy
        case "ox":     return ox
        case "tint":   return tint
        case "morph":  return morph
        case "hands":  return hands
        case "blush":  return blush
        case "es":     return es
        case "badgeS": return badgeS
        default:       return 0
        }
    }
}

// MARK: - Math helpers

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a) * t }
private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }

private func cgColorToTuple(_ c: CGColor) -> (CGFloat, CGFloat, CGFloat) {
    guard let comps = c.components, comps.count >= 3 else { return (1,1,1) }
    return (comps[0], comps[1], comps[2])
}

private func mix3(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    (lerp(a.0,b.0,t), lerp(a.1,b.1,t), lerp(a.2,b.2,t))
}

private func mixColor(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    mix3(a, b, t)
}

private func badgeString(_ b: BadgeType?) -> String {
    guard let b else { return "none" }
    func hex(_ c: CGColor) -> String {
        guard let k = c.components, k.count >= 3 else { return "?" }
        return "\(Int(k[0]*255)).\(Int(k[1]*255)).\(Int(k[2]*255))"
    }
    switch b {
    case .dots(let c):     return "dots-\(hex(c))"
    case .bang(let c):     return "bang-\(hex(c))"
    case .question(let c): return "q-\(hex(c))"
    case .dot(let c):      return "dot-\(hex(c))"
    }
}

private func emoteEyeShape(_ e: BotEmote) -> EyeShape {
    switch e {
    case .love:      return .heart
    case .surprised: return .dot
    case .proud:     return .star
    case .wink:      return .wink
    case .yawn:      return .tired
    case .happy:     return .happy
    case .annoyed:   return .line
    }
}

/// Which expression of the concept sheet each eye shape stands for.
private func yumiExpression(_ shape: EyeShape) -> YumiExpression {
    switch shape {
    case .pill:       return .neutral
    case .wide, .dot: return .surprised
    case .line:       return .annoyed
    case .flat:       return .worried
    case .happy:      return .happy
    case .closed:     return .asleep
    case .spiral:     return .confused
    case .heart:      return .love
    case .star:       return .proud
    case .tired:      return .drowsy
    case .wink:       return .wink
    case .cup:        return .eager
    case .focused:    return .focused
    case .thoughtful: return .thoughtful
    case .curious:    return .curious
    case .panicked:   return .panicked
    case .content:    return .content
    }
}

// MARK: - Shape helpers

private func heartShape(size s: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: s * 0.38))
    p.addCurve(to: CGPoint(x: 0, y: -s * 0.38),
               control1: CGPoint(x: -s * 1.05, y: -s * 0.15),
               control2: CGPoint(x: -s * 0.5,  y: -s * 0.95))
    p.addCurve(to: CGPoint(x: 0, y: s * 0.38),
               control1: CGPoint(x: s * 0.5,   y: -s * 0.95),
               control2: CGPoint(x: s * 1.05,  y: -s * 0.15))
    p.closeSubpath()
    return p
}

private func starShape(outer ro: CGFloat, inner ri: CGFloat) -> Path {
    var p = Path()
    for i in 0..<10 {
        let r = i.isMultiple(of: 2) ? ro : ri
        let a = -.pi/2 + CGFloat(i) * .pi/5
        let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// Equatable for BadgeType (needed for comparing)
extension BadgeType: Equatable {
    static func == (lhs: BadgeType, rhs: BadgeType) -> Bool {
        switch (lhs, rhs) {
        case (.dots, .dots): return true
        case (.bang, .bang): return true
        case (.question, .question): return true
        case (.dot, .dot): return true
        default: return false
        }
    }
}
