import { MOODS, POSE_FACES, type Face, type RimTone } from "./faces";

// Port of Character/YumiBlob.swift, YumiPoses.swift and YumiHabits.swift: the soft body of
// the mock-up, with the same constants. Height and lean are springs, and the outline is
// rebuilt from them every frame, so Yumi wobbles instead of being scaled. All lengths are
// in the 100 × 84 box of the mock-up.

export type Pose =
  | "jump" | "stretch" | "squash" | "shake" | "celebrate"
  | "pop" | "boing" | "arrive" | "dip" | "wave";

// The cigarette of the app is left out on purpose: the video never shows it.
export type Habit =
  | "exhausted" | "coffee" | "matcha" | "headphones" | "sunglasses" | "cloud" | "whistle" | "sleep";

export const HABITS: readonly Habit[] = [
  "exhausted", "coffee", "matcha", "headphones", "sunglasses", "cloud", "whistle", "sleep",
];

/** A droplet thrown by a landing or a shake. */
export type Drop = { x: number; y: number; vx: number; vy: number; r: number; life: number };
/** A puff of steam or sigh. */
export type Puff = Drop & { max: number; ph: number };
/** One beat of a pose: `run` fires `at` milliseconds after the pose started. */
export type Step = { at: number; run: (b: Blob) => void };

export class Blob {
  // Height spring (1 = at rest) and its target
  h = 1;
  vh = 0;
  th = 1;
  // Lean spring: how far the top is pushed sideways, and its target
  lean = 0;
  vl = 0;
  leanTarget = 0;
  /** The face follows the lean with a short delay. */
  eye = 0;
  // Jump
  y = 0;
  vy = 0;
  air = false;

  sleep = false;
  t: number;

  // Spring constants, set by soft() and hard()
  k = 170;
  c = 9;
  kl = 150;
  cl = 8;

  // The head turns towards the look target
  lookX = 0;
  lookY = 0;
  yaw = 0;
  pitch = 0;

  drops: Drop[] = [];
  puffs: Puff[] = [];

  // Habit and its counters
  habit: Habit | null = null;
  st = 0;
  sa = 0;
  ex = false;
  /** Coffee: the cup is tilted for a sip. */
  sip = false;

  /** Face taken while a pose or a habit beat plays. null = the current mood. */
  tempFace: Face | null = null;

  private steps: Step[] = [];
  private t0 = 0;

  // What the renderer derives from the springs
  shapeH = 1;
  shapeW = 1;
  /** Face transform: shift (x, y) and scale (x, y). */
  fx = { dx: 0, dy: 0, sx: 1, sy: 1 };

  constructor(private readonly random: () => number) {
    this.t = random() * 10;
  }

  soft() { this.k = 170; this.c = 9; this.kl = 150; this.cl = 8; }
  hard() { this.k = 420; this.c = 34; }

  setHabit(habit: Habit | null) {
    this.habit = habit;
    this.st = 0; this.sa = 0; this.ex = false;
    this.leanTarget = 0; this.th = 1;
    this.sleep = habit === "sleep";
    this.sip = false;
    this.tempFace = null;
  }

  /** Where a point of the face ends up once the body has moved. */
  world(x: number, y: number) {
    return {
      x: 50 + (x - 50) * this.fx.sx + this.fx.dx - this.lean * 0.12,
      y: 45 + (y - 45) * this.fx.sy + this.fx.dy + this.y,
    };
  }

  puff(x: number, y: number, vx: number, vy: number, r: number, life: number) {
    this.puffs.push({ x, y, vx, vy, r, life, max: life, ph: this.random() * 6 });
  }

  /** Plays the beats of a scene the same way as a pose. */
  run(steps: readonly Step[], now: number) {
    this.soft();
    this.leanTarget = 0; this.th = 1;
    this.steps = [...steps];
    this.t0 = now;
  }

  play(pose: Pose, now: number) {
    this.soft();
    this.leanTarget = 0; this.th = 1;
    this.steps = [...POSE_STEPS[pose]];
    this.t0 = now;
  }

  /** Droplets on both sides of the base, when he lands or slams flat. */
  splat(n: number, pow: number) {
    const R = this.random;
    for (const s of [-1, 1]) {
      for (let i = 0; i < n; i++) {
        this.drops.push({
          x: 50 + s * 44, y: 71,
          vx: s * (50 + R() * 80) * pow, vy: -(40 + R() * 80) * pow,
          r: 1.5 + R() * 1.5, life: 0.55 + R() * 0.3,
        });
      }
    }
  }

  /** Droplets thrown off one side while he shakes. */
  fling(s: number) {
    const R = this.random;
    for (let i = 0; i < 2; i++) {
      this.drops.push({
        x: 50 + s * 34 + this.lean * 0.5, y: 36 + R() * 22,
        vx: s * (90 + R() * 90), vy: -(20 + R() * 70),
        r: 1.3 + R() * 1.3, life: 0.45 + R() * 0.3,
      });
    }
  }

  /** One step. `dt` in seconds (the mock-up caps it at 0.033), `now` in milliseconds. */
  step(dt: number, now: number) {
    while (this.steps.length > 0 && now - this.t0 >= this.steps[0].at) {
      this.steps.shift()!.run(this);
    }
    this.t += dt; this.st += dt;
    if (this.habit && this.steps.length === 0 && !this.air) this.tick(this.habit, dt);

    const target = this.sleep ? 0.56 : this.th;
    this.vh += (-(this.h - target) * this.k - this.vh * this.c) * dt;
    this.h = Math.max(0.3, Math.min(1.9, this.h + this.vh * dt));
    this.vl += (-(this.lean - this.leanTarget) * this.kl - this.vl * this.cl) * dt;
    this.lean += this.vl * dt;
    this.eye += (this.lean - this.eye) * Math.min(1, dt * 9);

    const follow = Math.min(1, dt * 9);
    this.yaw += (this.lookX * 0.5 - this.yaw) * follow;
    this.pitch += (this.lookY * 0.32 - this.pitch) * follow;

    if (this.air) {
      this.vy += 900 * dt;
      this.y += this.vy * dt;
      if (this.y >= 0) {
        this.y = 0; this.air = false; this.th = 1; this.soft(); this.vh = -7; this.splat(2, 0.7);
      }
    }

    for (const d of this.drops) {
      d.vy += 420 * dt;
      d.x += d.vx * dt;
      d.y += d.vy * dt;
      d.life -= dt;
    }
    this.drops = this.drops.filter((d) => d.life > 0 && d.y < 82);

    for (const p of this.puffs) {
      p.vy -= 10 * dt;
      p.vx *= 1 - 1.4 * dt;
      p.x += (p.vx + Math.sin(this.t * 3 + p.ph) * 5) * dt;
      p.y += p.vy * dt;
      p.life -= dt;
    }
    this.puffs = this.puffs.filter((p) => p.life > 0).slice(-16);

    this.derive();
  }

  /** Breathing, width from height, face transform. */
  derive() {
    const amp = this.sleep ? 0.03 : 0.013;
    const speed = this.sleep ? 0.9 : 1.5;
    this.shapeH = this.h + amp * Math.sin(this.t * speed);
    this.shapeW = Math.max(0.68, Math.min(1.55, 1 / Math.pow(this.shapeH, 0.62)));
    const ey = 76 - 68 * this.shapeH + 37 * Math.pow(this.shapeH, 0.85);
    this.fx = {
      dx: this.eye * 0.6, dy: ey - 45,
      sx: Math.pow(this.shapeW, 0.45), sy: Math.pow(this.shapeH, 0.5),
    };
  }

  /** `SCENES` of the mock-up: the small routine of a habit, run every step. */
  private tick(habit: Habit, dt: number) {
    const R = this.random;
    switch (habit) {
      case "exhausted": {
        // Spread out like a puddle, with a long sigh now and then
        this.th = 0.46;
        const c = this.st % 4.2;
        if (c < 0.1 && !this.ex) {
          this.ex = true;
          this.vh += 1.8;
          const m = this.world(52, 58);
          for (let i = 0; i < 4; i++) {
            this.puff(m.x + R() * 8 - 4, m.y - 6, R() * 10 - 5, -16 - R() * 8, 2, 1.5);
          }
        }
        if (c > 0.5) this.ex = false;
        break;
      }
      case "coffee": {
        // A steaming cup. He takes a sip, and the caffeine kicks in: the eyes pop open
        this.sa += dt;
        const c = this.st % 6;
        if (this.sa > 0.35 && !this.sip) {
          this.sa = 0;
          const p = this.world(79, 61);
          this.puff(p.x, p.y, R() * 4 - 2, -15, 0.9, 1.2);
        }
        if (c > 3.4 && c < 4.4) {
          this.sip = true; this.leanTarget = -5; this.th = 1.03; this.ex = false;
        } else {
          this.sip = false; this.leanTarget = 0; this.th = 1;
          if (c >= 4.4 && c < 5.4) {
            if (!this.ex) { this.ex = true; this.vh -= 3.5; this.tempFace = MOODS.surprised; }
          } else if (this.ex) {
            this.ex = false; this.tempFace = null;
          }
        }
        break;
      }
      case "matcha": {
        // A bowl of matcha held in both hands. A thin steam, slower than the coffee's; every
        // seven seconds a long sip, then a sigh of content with the eyes closed
        this.sa += dt;
        const c = this.st % 7;
        if (this.sa > 0.55 && !this.sip) {
          this.sa = 0;
          const p = this.world(70 + R() * 6, 61);
          this.puff(p.x, p.y, R() * 3 - 1.5, -9, 0.75, 1.6);
        }
        if (c > 3.6 && c < 4.9) {
          this.sip = true; this.leanTarget = -3; this.th = 1.02; this.ex = false;
          this.tempFace = null;
        } else {
          this.sip = false; this.leanTarget = 0; this.th = 1;
          if (c >= 4.9 && c < 6.1) {
            if (!this.ex) { this.ex = true; this.vh -= 1.6; this.tempFace = POSE_FACES.shut; }
            this.th = 0.97;
          } else if (this.ex) {
            this.ex = false; this.tempFace = null;
          }
        }
        break;
      }
      case "headphones":
        // He keeps the beat with his whole body
        this.th = 1 + 0.055 * Math.sin(this.st * 12.6);
        this.leanTarget = 5 * Math.sin(this.st * 6.3);
        break;
      case "whistle":
        this.th = 1;
        this.leanTarget = 4 * Math.sin(this.st * 2.2);
        break;
      case "cloud":
        this.th = 0.9;
        break;
      case "sunglasses":
      case "sleep":
        this.th = 1;
        break;
    }
  }
}

// `POSE_FX` of the mock-up: each pose is a short list of beats that change the targets and
// the stiffness of the springs. Times are in milliseconds.

const crouch = (b: Blob) => { b.hard(); b.th = 0.66; };
const leap = (b: Blob) => { b.soft(); b.th = 1.18; b.vy = -190; b.air = true; };
const back = (b: Blob) => { b.tempFace = null; };

const POSE_STEPS: Record<Pose, readonly Step[]> = {
  // rise a little, slam flat with the eyes squeezed, hold, then spring back up and wobble
  squash: [
    { at: 0, run: (b) => { b.k = 300; b.c = 22; b.th = 1.12; } },
    { at: 130, run: (b) => { b.hard(); b.th = 0.5; b.tempFace = POSE_FACES.squeezed; } },
    { at: 240, run: (b) => b.splat(3, 1) },
    { at: 780, run: (b) => { b.soft(); b.c = 7; b.th = 1; b.tempFace = MOODS.surprised; } },
    { at: 1250, run: back },
  ],
  // crouch, reach up thin while looking at the sky and swaying, then snap back
  stretch: [
    { at: 0, run: (b) => { b.hard(); b.th = 0.8; } },
    { at: 170, run: (b) => { b.k = 110; b.c = 10; b.th = 1.45; b.leanTarget = 5; b.tempFace = POSE_FACES.skyward; } },
    { at: 560, run: (b) => { b.leanTarget = -5; } },
    { at: 860, run: (b) => { b.leanTarget = 0; b.k = 210; b.c = 6.5; b.th = 1; } },
    { at: 1250, run: back },
  ],
  // eyes shut, the top whips left and right behind the base and throws droplets,
  // then he comes to, a bit dazed
  shake: [
    { at: 0, run: (b) => { b.tempFace = POSE_FACES.shut; b.kl = 300; b.cl = 10; b.th = 0.95; b.leanTarget = 16; b.fling(-1); } },
    { at: 90, run: (b) => { b.leanTarget = -16; b.fling(1); } },
    { at: 180, run: (b) => { b.leanTarget = 14; b.fling(-1); } },
    { at: 270, run: (b) => { b.leanTarget = -14; b.fling(1); } },
    { at: 360, run: (b) => { b.leanTarget = 10; b.fling(-1); } },
    { at: 450, run: (b) => { b.leanTarget = -8; } },
    { at: 540, run: (b) => { b.leanTarget = 0; b.th = 1; b.kl = 150; b.cl = 6; } },
    { at: 700, run: (b) => { b.tempFace = MOODS.surprised; } },
    { at: 1050, run: back },
  ],
  jump: [{ at: 0, run: crouch }, { at: 150, run: leap }],
  celebrate: [
    { at: 0, run: crouch }, { at: 130, run: leap },
    { at: 640, run: crouch }, { at: 770, run: leap },
  ],
  wave: [
    { at: 0, run: (b) => { b.kl = 55; b.cl = 7; b.th = 1.05; b.leanTarget = 7; } },
    { at: 280, run: (b) => { b.leanTarget = -7; } },
    { at: 560, run: (b) => { b.leanTarget = 7; } },
    { at: 840, run: (b) => { b.leanTarget = -7; } },
    { at: 1120, run: (b) => { b.leanTarget = 0; b.th = 1; } },
  ],
  dip: [
    { at: 0, run: (b) => { b.hard(); b.th = 0.76; } },
    { at: 250, run: (b) => { b.soft(); b.th = 1; } },
  ],
  arrive: [{ at: 0, run: (b) => { b.h = 1.45; b.vh = 0; b.c = 7; } }],
  boing: [{ at: 0, run: (b) => { b.h = 0.7; b.vh = 0; b.c = 7; } }],
  pop: [{ at: 0, run: (b) => { b.vh -= 2.4; } }],
};

/** `POSE_MS`: how long the pose is considered to be playing, in seconds. */
export const POSE_DURATION: Record<Pose, number> = {
  jump: 0.9, stretch: 1.3, squash: 1.4, shake: 1.1, celebrate: 1.6,
  wave: 1.52, dip: 0.4, arrive: 0.6, pop: 0.4, boing: 0.7,
};

export const HABIT_FACE: Record<Habit, Face> = {
  exhausted: POSE_FACES.blank,
  coffee: POSE_FACES.weary,
  matcha: POSE_FACES.serene,
  headphones: MOODS.happy,
  sunglasses: MOODS.neutral,
  cloud: MOODS.worried,
  whistle: POSE_FACES.elsewhere,
  sleep: MOODS.asleep,
};

export const HABIT_RIM: Record<Habit, RimTone> = {
  exhausted: "calm",
  coffee: "warn",
  matcha: "done",
  headphones: "joy",
  sunglasses: "done",
  cloud: "error",
  whistle: "calm",
  sleep: "calm",
};
