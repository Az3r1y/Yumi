import {
  Blob, HABITS, HABIT_FACE, HABIT_RIM, POSE_DURATION,
  type Drop, type Habit, type Pose, type Puff,
} from "./blob";
import { MOODS, RIMS, type Face, type Mood, type RGB, type RimTone } from "./faces";
import { CURVES, Transition, keyframes, mulberry32 } from "./motion";
import { SCENE_DURATION, sceneSteps, type SceneMoment, type SceneName } from "./scenes";
import type { SkinName } from "./skins";

// Port of BotEngine.swift, without the island: the character is driven by a script of cues
// (the commands of Contracts/CharacterCommands.swift, each with its time) instead of
// notifications. The springs are stateful, so a frame is reached by stepping from the start;
// the steps are fixed and the randomness seeded, which makes every frame reproducible.

/** One command sent to Yumi `at` seconds after the start of his script. */
export type Cue = {
  readonly at: number;
  /** null clears the habit. */
  readonly habit?: Habit | null;
  /** false = unlit: only the eyes show. Coming back, the rim draws itself round him. */
  readonly lit?: boolean;
  /** A new mood frees the gaze: put `gaze` in the same cue or a later one. */
  readonly mood?: Mood;
  readonly rim?: RimTone;
  /** -1…1 on both axes, y down. null looks straight ahead again. */
  readonly gaze?: readonly [number, number] | null;
  readonly pose?: Pose;
  /** Something that happened outside (Contracts/EventAnimations.swift), played once. */
  readonly scene?: SceneName;
  /** How many events the scene stands for, 1 to 4: a larger count amplifies it a little. */
  readonly amount?: number;
  readonly blink?: boolean;
  /** Something he wears (src/yumi/skins.tsx). null takes it off. */
  readonly skin?: SkinName | null;
};

export type YumiScript = {
  readonly seed?: number;
  /** Now and then he glances somewhere on his own (every 6.5 s, when nothing else holds his gaze). */
  readonly glances?: boolean;
  /** Seconds already lived when the shot starts, to cut into a habit at the right moment of its routine. */
  readonly lead?: number;
  /** Where his breathing starts, in seconds of its cycle. Random when omitted; set it to join two shots. */
  readonly breath?: number;
  readonly cues: readonly Cue[];
};

/** Everything the renderer needs for one image. */
export type YumiFrame = {
  h: number;
  w: number;
  lean: number;
  y: number;
  air: boolean;
  faceShift: { x: number; y: number };
  faceScale: { x: number; y: number };
  yaw: number;
  pitch: number;
  face: Face;
  pupil: { x: number; y: number };
  blink: number;
  rim: readonly RGB[];
  /** How much of the rim is drawn, 0…1. */
  drawn: number;
  /** Opacity of everything that is light: glow, inner light, floor, shine, glint. */
  light: number;
  props: Record<Habit, number>;
  habitTime: number;
  sip: number;
  /** Seconds since the arms or the sparks started, null when they are not out. */
  armTime: number | null;
  sparkTime: number | null;
  /** The scene being played, if any. */
  scene: SceneMoment | null;
  /** What he wears, and since when (seconds), for it to pop on. */
  skin: SkinName | null;
  skinTime: number;
  /** Seconds since the start, for what moves on its own. */
  time: number;
  drops: readonly Drop[];
  puffs: readonly Puff[];
};

const FACE_KEYS = ["esl", "esr", "tl", "tr", "al", "ar", "bl", "br"] as const;

class Engine {
  private readonly random: () => number;
  private readonly blob: Blob;
  private readonly cues: Cue[];
  private clock = 0;

  private habitCommand: Habit | null = null;
  private mood: Mood = "neutral";
  private rimTone: RimTone = "calm";
  private gazeCommand: readonly [number, number] | null = null;
  private lit = true;
  private skin: SkinName | null = null;
  private skinStart = -10;

  private pose: Pose | null = null;
  private scene: { name: SceneName; start: number; amount: number } | null = null;
  private poseStart = 0;
  private habitStart = 0;

  private glance: readonly [number, number] | null = null;
  private glanceUntil = 0;
  private nextGlance = 6.5;
  private blinkAt: number | null = null;

  // Eased values: the CSS transitions of the mock-up
  private lids = Object.fromEntries(
    FACE_KEYS.map((k) => [k, new Transition(MOODS.neutral[k])]),
  ) as Record<(typeof FACE_KEYS)[number], Transition>;
  private ps = new Transition(1);
  private cl = new Transition(0);
  private cr = new Transition(0);
  private tilt = new Transition(0);
  private lx = new Transition(0);
  private ly = new Transition(0);
  private rimStops = RIMS.calm.map((stop) => stop.map((v) => new Transition(v)));
  private drawn = new Transition(1);
  private light = new Transition(1);
  private props = Object.fromEntries(HABITS.map((h) => [h, new Transition(0)])) as Record<Habit, Transition>;
  private sip = new Transition(0);

  readonly frames: YumiFrame[] = [];

  constructor(private readonly script: YumiScript, private readonly fps: number) {
    this.random = mulberry32(script.seed ?? 1);
    this.blob = new Blob(this.random);
    if (script.breath !== undefined) this.blob.t = script.breath;
    this.cues = [...script.cues].sort((a, b) => a.at - b.at);
    this.prime();
    this.frames.push(this.snapshot());
  }

  apply(cue: Cue) {
    if (cue.habit !== undefined) this.habitCommand = cue.habit;
    if (cue.lit !== undefined && cue.lit !== this.lit) {
      this.lit = cue.lit;
      if (cue.lit) {
        this.drawn.set(1, this.clock, 0.8, CURVES.draw);
        this.light.set(1, this.clock, 0.7, CURVES.ease);
      } else {
        this.drawn.jump(0);
        this.light.jump(0);
      }
    }
    if (cue.mood !== undefined) {
      // A new mood replaces whatever face a pose had put on, and frees the gaze
      this.mood = cue.mood;
      this.gazeCommand = null;
      this.blob.tempFace = null;
    }
    if (cue.rim !== undefined) this.rimTone = cue.rim;
    if (cue.gaze !== undefined) this.gazeCommand = cue.gaze;
    if (cue.pose !== undefined) {
      this.blob.play(cue.pose, this.clock * 1000);
      this.pose = cue.pose;
      this.poseStart = this.clock;
    }
    if (cue.scene !== undefined) {
      const amount = Math.max(1, Math.min(4, cue.amount ?? 1));
      this.blob.run(sceneSteps(cue.scene, amount), this.clock * 1000);
      this.pose = null;
      this.scene = { name: cue.scene, start: this.clock, amount };
    }
    if (cue.blink) this.blinkAt = this.clock;
    if (cue.skin !== undefined) {
      this.skin = cue.skin;
      // Worn from the first image: already in place, not popping on
      this.skinStart = this.clock === 0 ? -10 : this.clock;
    }
  }

  private applyDue() {
    while (this.cues.length > 0 && this.cues[0].at <= this.clock + 1e-6) {
      this.apply(this.cues.shift()!);
    }
  }

  /** The first image shows the state asked at 0 already in place, not on its way there. */
  private prime() {
    this.applyDue();
    const habit = this.habitCommand;
    this.blob.setHabit(habit);
    const face = (habit && HABIT_FACE[habit]) ?? MOODS[this.mood];
    const tone = RIMS[(habit && HABIT_RIM[habit]) ?? this.rimTone];
    for (const k of FACE_KEYS) this.lids[k].jump(face[k]);
    this.ps.jump(face.ps);
    this.cl.jump(face.cl);
    this.cr.jump(face.cr);
    this.tilt.jump(face.tilt);
    const look = face.look ?? this.gazeCommand ?? [0, 0];
    this.lx.jump(look[0]);
    this.ly.jump(look[1]);
    this.blob.yaw = look[0] * 0.5;
    this.blob.pitch = look[1] * 0.32;
    tone.forEach((stop, i) => stop.forEach((v, j) => this.rimStops[i][j].jump(v)));
    if (habit) this.props[habit].jump(1);
    if (this.blob.sleep) this.blob.h = 0.56;
    this.blob.derive();
  }

  step(dt: number) {
    this.applyDue();
    this.clock += dt;
    const now = this.clock;
    const blob = this.blob;

    const habit = this.habitCommand;
    if (habit !== blob.habit) {
      blob.setHabit(habit);
      this.habitStart = now;
    }
    const mood = (habit && HABIT_FACE[habit]) ?? MOODS[this.mood];
    const tone = RIMS[(habit && HABIT_RIM[habit]) ?? this.rimTone];

    if (this.pose && now - this.poseStart >= POSE_DURATION[this.pose]) this.pose = null;
    if (this.scene && now - this.scene.start >= SCENE_DURATION[this.scene.name]) this.scene = null;
    const face = blob.tempFace ?? mood;

    if (now >= this.nextGlance) {
      this.nextGlance = now + 6.5;
      const free = !habit && !this.pose && !face.look && !this.gazeCommand && this.lit;
      // The draws are made either way, so a glance does not shift the rest of the film
      const g = [this.random() * 2 - 1, this.random() * 1.2 - 0.6] as const;
      if (free && this.script.glances) {
        this.glance = g;
        this.glanceUntil = now + 0.9;
      }
    }
    if (this.glance && now >= this.glanceUntil) this.glance = null;

    // Where he looks: a face can pin the gaze, then a command, then a glance
    const fixed = face.look ?? this.gazeCommand ?? this.glance;
    const look = fixed ?? [0, 0];
    blob.lookX = look[0];
    blob.lookY = look[1];

    blob.step(dt, now * 1000);

    // Durations and curves below are the CSS transitions of the mock-up
    for (const k of FACE_KEYS) this.lids[k].set(face[k], now, 0.26, CURVES.lid);
    this.ps.set(face.ps, now, 0.26, CURVES.spring);
    this.cl.set(face.cl, now, 0.12, CURVES.ease);
    this.cr.set(face.cr, now, 0.12, CURVES.ease);
    this.tilt.set(face.tilt, now, 0.4, CURVES.spring);
    this.lx.set(look[0], now, fixed ? 0.3 : 0.14, fixed ? CURVES.spring : CURVES.easeOut);
    this.ly.set(look[1], now, fixed ? 0.3 : 0.14, fixed ? CURVES.spring : CURVES.easeOut);
    tone.forEach((stop, i) =>
      stop.forEach((v, j) => this.rimStops[i][j].set(v, now, 0.5, CURVES.ease)),
    );
    for (const h of HABITS) this.props[h].set(h === habit ? 1 : 0, now, 0.25, CURVES.ease);
    this.sip.set(blob.sip ? 1 : 0, now, 0.35, CURVES.spring);
  }

  /** The 0.243 s blink of the mock-up, when asked. */
  private blinkValue(): number {
    if (this.blinkAt === null) return 1;
    const q = (this.clock - this.blinkAt) / 0.243;
    return q < 1 ? keyframes(q, [[0, 1], [0.444, 0.08], [1, 1]], CURVES.ease) : 1;
  }

  snapshot(): YumiFrame {
    const now = this.clock;
    const blob = this.blob;
    const poseTime = this.pose ? now - this.poseStart : null;
    const lid = (k: (typeof FACE_KEYS)[number]) => this.lids[k].value(now);
    return {
      h: blob.shapeH,
      w: blob.shapeW,
      lean: blob.lean,
      y: blob.y,
      air: blob.air,
      faceShift: { x: blob.fx.dx, y: blob.fx.dy },
      faceScale: { x: blob.fx.sx, y: blob.fx.sy },
      yaw: blob.yaw,
      pitch: blob.pitch,
      face: {
        esl: lid("esl"), esr: lid("esr"), tl: lid("tl"), tr: lid("tr"),
        al: lid("al"), ar: lid("ar"), bl: lid("bl"), br: lid("br"),
        ps: this.ps.value(now), cl: this.cl.value(now), cr: this.cr.value(now),
        tilt: this.tilt.value(now),
      },
      pupil: { x: this.lx.value(now), y: this.ly.value(now) },
      blink: this.blinkValue(),
      rim: this.rimStops.map((stop) => stop.map((v) => v.value(now)) as unknown as RGB),
      drawn: this.drawn.value(now),
      light: this.light.value(now),
      props: Object.fromEntries(HABITS.map((h) => [h, this.props[h].value(now)])) as Record<Habit, number>,
      habitTime: now - this.habitStart,
      sip: this.sip.value(now),
      armTime: this.pose === "celebrate" || this.pose === "wave" ? poseTime : null,
      sparkTime: this.pose === "celebrate" ? poseTime : null,
      scene: this.scene ? { name: this.scene.name, t: now - this.scene.start, amount: this.scene.amount } : null,
      skin: this.skin,
      skinTime: now - this.skinStart,
      time: now,
      drops: blob.drops.map((d) => ({ ...d })),
      puffs: blob.puffs.map((p) => ({ ...p })),
    };
  }

  /** Steps of 1/60 s or less, the cadence of the mock-up: the springs behave the same at any fps. */
  frame(index: number): YumiFrame {
    const substeps = Math.max(1, Math.round(60 / this.fps));
    const dt = 1 / (this.fps * substeps);
    while (this.frames.length <= index) {
      for (let i = 0; i < substeps; i++) this.step(dt);
      this.frames.push(this.snapshot());
    }
    return this.frames[index];
  }
}

/**
 * Yumi driven live instead of by a script: the website, where he follows the pointer.
 * Commands apply at once; the caller lets time pass, in steps of 1/60 s like a film.
 */
export class LiveYumi {
  private readonly engine: Engine;

  constructor(seed = 1) {
    this.engine = new Engine({ seed, cues: [] }, 60);
  }

  /** A command, now (the same fields as a cue of a script). */
  command(cue: Omit<Cue, "at">) {
    this.engine.apply({ ...cue, at: 0 });
  }

  /** Lets `seconds` pass. After a long pause (a hidden tab), only a quarter of a second does. */
  advance(seconds: number) {
    let left = Math.min(seconds, 0.25);
    while (left > 1e-6) {
      const dt = Math.min(1 / 60, left);
      this.engine.step(dt);
      left -= dt;
    }
  }

  /** What to draw now. */
  frame(): YumiFrame {
    return this.engine.snapshot();
  }
}

const engines = new WeakMap<YumiScript, Map<number, Engine>>();

/** Yumi at `frame` of his script. Frames already computed are kept, so scrubbing stays cheap. */
export const yumiFrameAt = (script: YumiScript, frame: number, fps: number): YumiFrame => {
  let byFps = engines.get(script);
  if (!byFps) {
    byFps = new Map();
    engines.set(script, byFps);
  }
  let engine = byFps.get(fps);
  if (!engine) {
    engine = new Engine(script, fps);
    byFps.set(fps, engine);
  }
  return engine.frame(Math.max(0, Math.floor(frame)) + Math.round((script.lead ?? 0) * fps));
};
