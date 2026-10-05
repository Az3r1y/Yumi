import CoreGraphics

// `SCENES` of design/yumi/maquette/reference.html: human habits on a slime. Each one has a
// face, a rim colour, a prop (drawn by YumiRenderer) and a small routine that runs every frame.

extension YumiHabit {

    var face: YumiFace {
        switch self {
        case .smoke:      return .weary
        case .exhausted:  return .blank
        case .coffee:     return .weary
        case .headphones: return .happy
        case .sunglasses: return .neutral
        case .cloud:      return .worried
        case .whistle:    return .elsewhere
        case .sleep:      return .asleep
        case .matcha:     return .serene
        }
    }

    var rim: YumiRimTone {
        switch self {
        case .smoke:      return .work
        case .exhausted:  return .calm
        case .coffee:     return .warn
        case .headphones: return .joy
        case .sunglasses: return .done
        case .cloud:      return .error
        case .whistle:    return .calm
        case .sleep:      return .calm
        case .matcha:     return .done
        }
    }

    func tick(_ b: YumiBlob, dt: CGFloat) {
        func R() -> CGFloat { .random(in: 0..<1) }
        switch self {

        case .smoke:
            // Every five seconds he takes a drag (the tip glows, he swells), then blows a cloud
            b.sa += dt
            let c = b.st.truncatingRemainder(dividingBy: 5.5)
            let tip = b.world(76, 64)
            if b.sa > 0.22 { b.sa = 0; b.puff(tip.x, tip.y, 2 + R() * 4, -13, 1, 1.5) }
            if c > 3.4 && c < 4.1 {
                b.th = 1.07; b.drag = true; b.ex = false
            } else if c >= 4.1 && c < 4.9 {
                b.drag = false; b.th = 0.9
                if !b.ex {
                    b.ex = true
                    let m = b.world(62, 59)
                    for _ in 0..<7 { b.puff(m.x + 4, m.y, 24 + R() * 34, -4 - R() * 16, 2.1, 1.7) }
                }
            } else {
                b.th = 0.94
            }

        case .exhausted:
            // Spread out like a puddle, with a long sigh now and then
            b.th = 0.46
            let c = b.st.truncatingRemainder(dividingBy: 4.2)
            if c < 0.1 && !b.ex {
                b.ex = true
                b.vh += 1.8
                let m = b.world(52, 58)
                for _ in 0..<4 { b.puff(m.x + R() * 8 - 4, m.y - 6, R() * 10 - 5, -16 - R() * 8, 2, 1.5) }
            }
            if c > 0.5 { b.ex = false }

        case .coffee:
            // A steaming cup. He takes a sip, and the caffeine kicks in: the eyes pop open
            b.sa += dt
            let c = b.st.truncatingRemainder(dividingBy: 6)
            if b.sa > 0.35 && !b.sip {
                b.sa = 0
                let p = b.world(79, 61)
                b.puff(p.x, p.y, R() * 4 - 2, -15, 0.9, 1.2)
            }
            if c > 3.4 && c < 4.4 {
                b.sip = true; b.leanTarget = -5; b.th = 1.03; b.ex = false
            } else {
                b.sip = false; b.leanTarget = 0; b.th = 1
                if c >= 4.4 && c < 5.4 {
                    if !b.ex { b.ex = true; b.vh -= 3.5; b.tempFace = .surprised }
                } else if b.ex {
                    b.ex = false; b.tempFace = nil
                }
            }

        case .matcha:
            // A bowl of matcha held in both hands. A thin steam, slower than the coffee's; every
            // seven seconds a long sip, then a sigh of content with the eyes closed
            b.sa += dt
            let c = b.st.truncatingRemainder(dividingBy: 7)
            if b.sa > 0.55 && !b.sip {
                b.sa = 0
                let p = b.world(70 + R() * 6, 61)
                b.puff(p.x, p.y, R() * 3 - 1.5, -9, 0.75, 1.6)
            }
            if c > 3.6 && c < 4.9 {
                b.sip = true; b.leanTarget = -3; b.th = 1.02; b.ex = false
                b.tempFace = nil
            } else {
                b.sip = false; b.leanTarget = 0; b.th = 1
                if c >= 4.9 && c < 6.1 {
                    if !b.ex { b.ex = true; b.vh -= 1.6; b.tempFace = .shut }
                    b.th = 0.97
                } else if b.ex {
                    b.ex = false; b.tempFace = nil
                }
            }

        case .headphones:
            // He keeps the beat with his whole body
            b.th = 1 + 0.055 * sin(b.st * 12.6)
            b.leanTarget = 5 * sin(b.st * 6.3)

        case .whistle:
            b.th = 1
            b.leanTarget = 4 * sin(b.st * 2.2)

        case .cloud:
            b.th = 0.9

        case .sunglasses, .sleep:
            b.th = 1
        }
    }
}
