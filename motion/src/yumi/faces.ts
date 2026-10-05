// Port of Character/YumiFace.swift: `BASE`, `MOODS`, `POSE_FACES` and `RIMS` of the mock-up.

export type Face = {
  esl: number; // eye scale, left and right
  esr: number;
  ps: number; // pupil scale
  tl: number; // upper lid: 0 open, 1.1 shut
  tr: number;
  al: number; // upper lid angle, degrees
  ar: number;
  bl: number; // lower lid
  br: number;
  cl: number; // opacity of the closed-eye stroke
  cr: number;
  tilt: number; // head tilt, degrees
  /** A face with a look pins the gaze there (-1…1, y down). */
  look?: readonly [number, number];
};

const BASE: Face = {
  esl: 1, esr: 1, ps: 1, tl: 0, tr: 0, al: 0, ar: 0, bl: 0, br: 0, cl: 0, cr: 0, tilt: 0,
};

const face = (f: Partial<Face>): Face => ({ ...BASE, ...f });

export const MOODS = {
  neutral: BASE,
  happy: face({ bl: 0.42, br: 0.42 }),
  curious: face({ esl: 0.92, esr: 1.14, tilt: 7 }),
  focused: face({ tl: 0.38, tr: 0.38, look: [0, 0.5] }),
  thinking: face({ tl: 0.16, tr: 0.16, look: [0.8, -0.8] }),
  surprised: face({ esl: 1.16, esr: 1.16, ps: 0.72 }),
  worried: face({ tl: 0.3, tr: 0.3, al: -16, ar: 16 }),
  annoyed: face({ tl: 0.4, tr: 0.4, al: 16, ar: -16 }),
  wink: face({ tr: 1.1, cr: 1 }),
  asleep: face({ tl: 1.1, tr: 1.1, cl: 1, cr: 1 }),
} as const satisfies Record<string, Face>;

export type Mood = keyof typeof MOODS;

/** Taken only while a pose or a habit plays. */
export const POSE_FACES = {
  weary: face({ tl: 0.46, tr: 0.46, look: [0.5, 0.55] }),
  blank: face({ tl: 0.5, tr: 0.5, look: [0, -0.8] }),
  elsewhere: face({ esl: 0.96, esr: 0.96, look: [0.95, -0.6] }),
  squeezed: face({ ps: 0.85, tl: 0.3, tr: 0.3, al: 10, ar: -10, bl: 0.3, br: 0.3 }),
  skyward: face({ esl: 1.14, esr: 1.14, ps: 0.8, look: [0, -1] }),
  shut: face({ tl: 1.1, tr: 1.1, cl: 1, cr: 1 }),
} as const satisfies Record<string, Face>;

export type RGB = readonly [number, number, number];

const hex = (h: number): RGB => [(h >> 16) & 0xff, (h >> 8) & 0xff, h & 0xff];

/** `RIMS` of the mock-up: the three stops of the rim gradient, left to right. */
export const RIMS = {
  calm: [hex(0x5b8cff), hex(0x8b6cff), hex(0xf58ad9)],
  work: [hex(0x3f7bff), hex(0x4fa0ff), hex(0x7fd0ff)],
  think: [hex(0x7b5cff), hex(0x9b7bff), hex(0xc9a8ff)],
  warn: [hex(0xff9a3d), hex(0xffb547), hex(0xffd37a)],
  error: [hex(0xff4d5e), hex(0xff5d6c), hex(0xff9aa4)],
  done: [hex(0x22c98a), hex(0x3ddc97), hex(0x9bf0c8)],
  joy: [hex(0xb07bff), hex(0xf58ad9), hex(0xffb3e6)],
  // Light skins: other colours for the rim, chosen rather than given by a state
  mint: [hex(0x2fd4b0), hex(0x5ff0c8), hex(0xb6ffe6)],
  lava: [hex(0xff5a36), hex(0xff8a3d), hex(0xffd06a)],
  ice: [hex(0x8fd3ff), hex(0xc9ecff), hex(0xf2fbff)],
  gold: [hex(0xc99a2e), hex(0xffd37a), hex(0xfff1c2)],
} as const satisfies Record<string, readonly RGB[]>;

export type RimTone = keyof typeof RIMS;
