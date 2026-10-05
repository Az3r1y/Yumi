import { bodyPathFor } from "./shape";
import type { Blob, Step } from "./blob";
import { MOODS, POSE_FACES, type Face } from "./faces";
import { CURVES, curve } from "./motion";

// Port of Character/YumiScenes.swift: something happened outside (a star, a fork, a merge)
// and Yumi plays it once, in two seconds at most, then goes back to what he was doing.
// Each scene is a few beats on the soft body (like a pose) plus what is drawn around him.

export type SceneName = "star" | "fork" | "pullRequest" | "merge" | "push" | "commit" | "issue" | "release" | "follower";

/** Two seconds at most. */
export const SCENE_DURATION: Record<SceneName, number> = {
  star: 1.8, fork: 2.0, pullRequest: 1.8, merge: 2.0, push: 1.5, commit: 1.6, issue: 1.7, release: 2.0, follower: 2.0,
};

/** What a scene needs to be drawn at one instant: seconds since it started, and how many events it stands for. */
export type SceneMoment = { readonly name: SceneName; readonly t: number; readonly amount: number };

export const seg = (t: number, a: number, b: number) => Math.max(0, Math.min(1, (t - a) / (b - a)));

const look = (x: number, y: number, base: Face = MOODS.neutral): Face => ({ ...base, look: [x, y] });
const back = (b: Blob) => { b.tempFace = null; };

/** The beats of a scene, in milliseconds, like the steps of a pose. */
export const sceneSteps = (scene: SceneName, n: number): Step[] => {
  const more = n - 1;
  switch (scene) {
    case "star":
      // he watches it fall, catches it with a bounce, and beams
      return [
        { at: 0, run: (b) => { b.tempFace = POSE_FACES.skyward; } },
        { at: 600, run: (b) => { b.h = 0.8 - 0.03 * more; b.vh = 0; b.c = 7; b.tempFace = MOODS.happy; } },
        { at: 1700, run: back },
      ];
    case "fork":
      // he gathers himself, a part of him pulls away to the right, the strand snaps
      return [
        { at: 0, run: (b) => { b.hard(); b.th = 0.8; b.tempFace = POSE_FACES.squeezed; } },
        { at: 250, run: (b) => { b.k = 120; b.c = 8; b.th = 0.92; b.leanTarget = -7; } },
        { at: 850, run: (b) => { b.soft(); b.leanTarget = 0; b.th = 1; b.vh -= 2.5; b.fling(1); b.tempFace = MOODS.surprised; } },
        { at: 1050, run: (b) => { b.tempFace = look(1, 0.1); } },
        { at: 1500, run: (b) => { b.tempFace = look(1, 0.1, MOODS.happy); } },
        { at: 1900, run: back },
      ];
    case "merge":
      // a drop hops in from the right, he leans to it, they become one and he swells
      return [
        { at: 0, run: (b) => { b.tempFace = look(1, 0.1, MOODS.curious); } },
        { at: 750, run: (b) => { b.leanTarget = 6; } },
        { at: 1000, run: (b) => { b.soft(); b.c = 6; b.leanTarget = 0; b.th = 1.14 + 0.04 * more; b.splat(2 + n, 0.8); b.tempFace = MOODS.happy; } },
        { at: 1300, run: (b) => { b.th = 1; } },
        { at: 1900, run: back },
      ];
    case "pullRequest":
      return [
        { at: 0, run: (b) => { b.th = 1.07; b.tempFace = look(0.7, -0.6, MOODS.happy); } },
        { at: 1450, run: (b) => { b.th = 1; } },
        { at: 1750, run: back },
      ];
    case "push":
      // crouch, then throw
      return [
        { at: 0, run: (b) => { b.hard(); b.th = 0.68; b.tempFace = POSE_FACES.skyward; } },
        { at: 280, run: (b) => { b.soft(); b.c = 7; b.th = 1.16; } },
        { at: 520, run: (b) => { b.th = 1; } },
        { at: 1400, run: back },
      ];
    case "commit":
      return [
        { at: 250, run: (b) => { b.tempFace = look(1, -0.1); } },
        { at: 450, run: (b) => { b.vh -= 2.4; } },
        { at: 1400, run: back },
      ];
    case "issue":
      return [
        { at: 0, run: (b) => { b.tempFace = POSE_FACES.skyward; } },
        { at: 100, run: (b) => { b.vh -= 2.4; } },
        { at: 1500, run: back },
      ];
    case "release":
      // confetti, and a bow
      return [
        { at: 0, run: (b) => { b.tempFace = MOODS.happy; b.vh -= 2.4; } },
        { at: 550, run: (b) => { b.hard(); b.th = 0.62; b.tempFace = POSE_FACES.shut; } },
        { at: 1150, run: (b) => { b.soft(); b.th = 1; b.tempFace = MOODS.happy; } },
        { at: 1900, run: back },
      ];
    case "follower":
      return [
        { at: 300, run: (b) => { b.tempFace = look(1, 0, MOODS.curious); } },
        { at: 750, run: (b) => { b.vh -= 2.4; b.tempFace = look(1, 0, MOODS.happy); } },
        { at: 1900, run: back },
      ];
  }
};

/** A second, smaller slime: the copy of a fork, the drop of a merge, the visitor of a follow. */
export type Twin = {
  dx: number; // offset of its base from Yumi's, in units
  dy: number;
  scale: number;
  h: number;
  lean: number;
  alpha: number;
  /** Still part of Yumi's body: the two outlines are one. */
  attached: boolean;
  /** Thickness of the strand of slime between the two, 0 when there is none. */
  strand: number;
  /** Angle of its waving arm in degrees, null when the arm is in. */
  wave: number | null;
  lookX: number;
};

const twin = (t: Partial<Twin> & { dx: number; scale: number }): Twin => ({
  dy: 0, h: 1, lean: 0, alpha: 1, attached: false, strand: 0, wave: null, lookX: 0, ...t,
});

/** SVG transform of a twin: its base sits at (50 + dx, 76 + dy), scaled around it. */
export const twinTransform = (w: Twin) => `translate(${50 + w.dx} ${76 + w.dy}) scale(${w.scale}) translate(-50 -76)`;

export const twinPath = (w: Twin) => bodyPathFor(w.h, w.lean);

/** The strand that still ties it to Yumi, as a line in the box (stroked with `strand`). */
export const strandLine = (w: Twin) =>
  `M${50 + (w.dx > 0 ? 18 : -18)} 60L${50 + w.dx} ${76 + w.dy - 30 * w.scale}`;

/** The second slime of a scene at this instant, and a third one when several followers came. */
export const twins = (m: SceneMoment): Twin[] => {
  const t = m.t;
  const more = m.amount - 1;
  // a wobble that dies out, for a body that has just been let go
  const wobble = (t0: number) => (t < t0 ? 1 : 1 + 0.14 * Math.sin((t - t0) * 16) * Math.exp(-(t - t0) * 4.5));
  const waving = (a: number, b: number) => (t > a && t < b ? -20 + 26 * Math.sin((t - a) * 14) : null);
  switch (m.name) {
    case "fork": {
      const out = curve(CURVES.easeInOut, seg(t, 0.25, 0.9));
      const attached = t < 0.85;
      const w = twin({
        dx: 60 * out + 46 * Math.pow(seg(t, 1.5, 1.95), 2),
        scale: 0.25 + (0.38 + 0.05 * more) * out,
        attached,
        strand: attached ? 30 * (1 - seg(t, 0.45, 0.85)) + 3 : 0,
        h: wobble(0.85),
        lean: 7 * Math.sin(Math.PI * seg(t, 0.25, 0.9)) + 8 * seg(t, 1.5, 1.95),
        wave: waving(1.0, 1.5),
        lookX: t < 1.5 ? -1 : 1,
        alpha: 1 - seg(t, 1.7, 1.95),
      });
      return t > 0.2 && t < 1.95 ? [w] : [];
    }
    case "merge": {
      const come = curve(CURVES.easeInOut, seg(t, 0.15, 0.95));
      const eaten = seg(t, 0.95, 1.2);
      const attached = t > 0.78;
      const w = twin({
        dx: 62 * (1 - come),
        scale: (0.58 + 0.05 * more) * (1 - eaten),
        dy: -9 * Math.abs(Math.sin(Math.PI * 3 * seg(t, 0.15, 0.8))) * (1 - come),
        h: 1 + 0.1 * Math.sin(Math.PI * 6 * seg(t, 0.15, 0.8)) * (1 - come),
        lean: -6 * Math.sin(Math.PI * seg(t, 0.15, 0.95)),
        attached,
        strand: attached ? 34 * seg(t, 0.78, 1.0) + 3 : 0,
        lookX: -1,
        alpha: seg(t, 0.15, 0.3),
      });
      return t > 0.15 && t < 1.2 ? [w] : [];
    }
    case "follower": {
      const visitor = (delay: number, dx: number, scale: number) => {
        const u = t - delay;
        return twin({
          dx: dx + 24 * (1 - curve(CURVES.easeOut, seg(u, 0.1, 0.5))) + 34 * Math.pow(seg(u, 1.45, 1.85), 2),
          scale,
          lean: -7 + 5 * seg(u, 1.45, 1.85) * 3,
          h: 1 + 0.06 * Math.sin(u * 9) * (1 - seg(u, 0.5, 1.2)),
          wave: u > 0.6 && u < 1.4 ? -20 + 26 * Math.sin((u - 0.6) * 14) : null,
          lookX: -1,
          alpha: seg(u, 0.1, 0.3) * (1 - seg(u, 1.6, 1.85)),
        });
      };
      const all = [visitor(0, 54, 0.42)];
      if (m.amount > 1) all.unshift(visitor(0.12, 72, 0.33));
      return all;
    }
    default:
      return [];
  }
};

/** The arm he raises to hold the branch up: opacity, 0 when it is in. */
export const raisedArm = (m: SceneMoment) =>
  m.name === "pullRequest" ? seg(m.t, 0.1, 0.3) * (1 - seg(m.t, 1.5, 1.75)) : 0;
