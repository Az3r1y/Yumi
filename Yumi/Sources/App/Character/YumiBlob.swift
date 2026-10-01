import CoreGraphics

/// The soft body: a port of `Blob` in design/yumi/maquette/reference.html, with the same
/// constants. Height and lean are springs, and the outline is rebuilt from them every frame,
/// so Yumi wobbles instead of being scaled. All lengths are in the 100 × 84 box of the mock-up.
final class YumiBlob {

    /// A droplet thrown by a landing or a shake.
    struct Drop { var x, y, vx, vy, r, life: CGFloat }
    /// A puff of smoke, steam or sigh.
    struct Puff { var x, y, vx, vy, r, life, max, ph: CGFloat }
    /// One beat of a pose: `run` fires `at` milliseconds after the pose started.
    struct Step {
        let at: Double
        let run: (YumiBlob) -> Void
    }

    // Height spring (1 = at rest) and its target
    var h: CGFloat = 1
    var vh: CGFloat = 0
    var th: CGFloat = 1
    // Lean spring: how far the top is pushed sideways, and its target (`tl` in the mock-up)
    var lean: CGFloat = 0
    var vl: CGFloat = 0
    var leanTarget: CGFloat = 0
    /// Lean added by the pointer: Yumi bends a little towards what he looks at.
    var gaze: CGFloat = 0
    /// The face follows the lean with a short delay.
    var eye: CGFloat = 0
    // Jump
    var y: CGFloat = 0
    var vy: CGFloat = 0
    var air = false

    var sleep = false
    var t = CGFloat.random(in: 0..<10)

    // Spring constants, set by soft() and hard()
    var k: CGFloat = 170
    var c: CGFloat = 9
    var kl: CGFloat = 150
    var cl: CGFloat = 8

    // The head turns towards the look target (`--lx`, `--ly`)
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0
    var yaw: CGFloat = 0
    var pitch: CGFloat = 0

    var drops: [Drop] = []
    var puffs: [Puff] = []

    // Habit (`scene` in the mock-up) and its counters
    private(set) var habit: YumiHabit?
    var st: CGFloat = 0
    var sa: CGFloat = 0
    var ex = false
    /// Cigarette: the ember glows while he takes a drag. Coffee: the cup is tilted for a sip.
    var drag = false
    var sip = false

    /// Face taken while a pose or a habit beat plays. nil = the current mood.
    var tempFace: YumiFace?

    private var steps: [Step] = []
    private var t0: Double = 0

    // What draw() derives from the springs; world() uses the values of the previous frame
    private(set) var shapeH: CGFloat = 1
    private(set) var shapeW: CGFloat = 1
    /// Face transform: shift (x, y) and scale (x, y).
    private(set) var fx: (dx: CGFloat, dy: CGFloat, sx: CGFloat, sy: CGFloat) = (0, 0, 1, 1)

    var isPosing: Bool { !steps.isEmpty }

    func soft() { k = 170; c = 9; kl = 150; cl = 8 }
    func hard() { k = 420; c = 34 }

    func setHabit(_ newHabit: YumiHabit?) {
        habit = newHabit
        st = 0; sa = 0; ex = false
        leanTarget = 0; th = 1
        sleep = newHabit == .sleep
        drag = false; sip = false
        tempFace = nil
    }

    /// Where a point of the face ends up once the body has moved.
    func world(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 50 + (x - 50) * fx.sx + fx.dx - lean * 0.12,
                y: 45 + (y - 45) * fx.sy + fx.dy + self.y)
    }

    func puff(_ x: CGFloat, _ y: CGFloat, _ vx: CGFloat, _ vy: CGFloat, _ r: CGFloat, _ life: CGFloat) {
        puffs.append(Puff(x: x, y: y, vx: vx, vy: vy, r: r, life: life, max: life, ph: .random(in: 0..<6)))
    }

    func play(_ pose: YumiPose, now: Double) {
        soft()
        leanTarget = 0; th = 1
        steps = YumiBlob.steps(for: pose)
        t0 = now
    }

    /// Droplets on both sides of the base, when he lands or slams flat.
    func splat(_ n: Int, _ pow: CGFloat) {
        for s: CGFloat in [-1, 1] {
            for _ in 0..<n {
                drops.append(Drop(x: 50 + s * 44, y: 71,
                                  vx: s * (50 + .random(in: 0..<80)) * pow,
                                  vy: -(40 + .random(in: 0..<80)) * pow,
                                  r: 1.5 + .random(in: 0..<1.5), life: 0.55 + .random(in: 0..<0.3)))
            }
        }
    }

    /// Droplets thrown off one side while he shakes.
    func fling(_ s: CGFloat) {
        for _ in 0..<2 {
            drops.append(Drop(x: 50 + s * 34 + lean * 0.5, y: 36 + .random(in: 0..<22),
                              vx: s * (90 + .random(in: 0..<90)), vy: -(20 + .random(in: 0..<70)),
                              r: 1.3 + .random(in: 0..<1.3), life: 0.45 + .random(in: 0..<0.3)))
        }
    }

    /// One frame. `dt` in seconds (the mock-up caps it at 0.033), `now` in milliseconds.
    func step(dt: CGFloat, now: Double) {
        while let first = steps.first, now - t0 >= first.at {
            steps.removeFirst()
            first.run(self)
        }
        t += dt; st += dt
        if let habit, steps.isEmpty, !air { habit.tick(self, dt: dt) }

        let target = sleep ? 0.56 : th
        vh += (-(h - target) * k - vh * c) * dt
        h = max(0.3, min(1.9, h + vh * dt))
        vl += (-(lean - leanTarget - gaze) * kl - vl * cl) * dt
        lean += vl * dt
        eye += (lean - eye) * min(1, dt * 9)

        let follow = min(1, dt * 9)
        yaw += (lookX * 0.5 - yaw) * follow
        pitch += (lookY * 0.32 - pitch) * follow

        if air {
            vy += 900 * dt
            y += vy * dt
            if y >= 0 { y = 0; air = false; th = 1; soft(); vh = -7; splat(2, 0.7) }
        }

        for i in drops.indices {
            drops[i].vy += 420 * dt
            drops[i].x += drops[i].vx * dt
            drops[i].y += drops[i].vy * dt
            drops[i].life -= dt
        }
        drops.removeAll { $0.life <= 0 || $0.y >= 82 }

        for i in puffs.indices {
            puffs[i].vy -= 10 * dt
            puffs[i].vx *= 1 - 1.4 * dt
            puffs[i].x += (puffs[i].vx + sin(t * 3 + puffs[i].ph) * 5) * dt
            puffs[i].y += puffs[i].vy * dt
            puffs[i].life -= dt
        }
        puffs.removeAll { $0.life <= 0 }
        if puffs.count > 16 { puffs.removeFirst(puffs.count - 16) }

        // What draw() computes in the mock-up: breathing, width from height, face transform
        let amp: CGFloat = sleep ? 0.03 : 0.013
        let speed: CGFloat = sleep ? 0.9 : 1.5
        shapeH = h + amp * sin(t * speed)
        shapeW = max(0.68, min(1.55, 1 / pow(shapeH, 0.62)))
        let ey = 76 - 68 * shapeH + 37 * pow(shapeH, 0.85)
        fx = (eye * 0.6, ey - 45, pow(shapeW, 0.45), pow(shapeH, 0.5))
    }
}
