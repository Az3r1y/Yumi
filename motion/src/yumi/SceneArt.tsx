import React from "react";
import type { RGB } from "./faces";
import { CURVES, curve } from "./motion";
import { seg, strandLine, twinPath, twinTransform, type SceneMoment, type Twin } from "./scenes";

// The drawing half of Character/YumiScenes.swift: the other slimes, and what a scene draws
// around Yumi (stars, a branch, a drop thrown up, a commit line, an issue mark, confetti).

const GOLD = "rgb(255,211,122)";
const rgb = ([r, g, b]: RGB) => `rgb(${r.toFixed(1)},${g.toFixed(1)},${b.toFixed(1)})`;

const star = (r: number, points: number, inner: number) =>
  Array.from({ length: points * 2 }, (_, i) => {
    const a = (i * Math.PI) / points - Math.PI / 2;
    const k = i % 2 === 0 ? r : r * inner;
    return `${i === 0 ? "M" : "L"}${(Math.cos(a) * k).toFixed(2)} ${(Math.sin(a) * k).toFixed(2)}`;
  }).join("") + "Z";

/** A slime that stands on its own: arm, black body, rim, two plain eyes. Attached, only the eyes. */
export const TwinArt: React.FC<{ readonly w: Twin; readonly rim: string; readonly rimWidth: number }> = ({ w, rim, rimWidth }) => {
  if (w.scale <= 0.05 || w.alpha <= 0.01) return null;
  const top = 76 - 68 * w.h;
  const side = w.lookX < 0 ? -1 : 1;
  return (
    <g opacity={w.alpha}>
      {!w.attached ? (
        <>
          {w.wave !== null ? (
            // its arm, on the side it waves to
            <g transform={`${twinTransform(w)} translate(${50 + side * 33} 52) rotate(${side * w.wave})`}>
              <path d={`M0 0L${side * 14} -17`} stroke={rim} strokeWidth={12} strokeLinecap="round" />
              <path d={`M0 0L${side * 14} -17`} stroke="#000" strokeWidth={7.6} strokeLinecap="round" />
            </g>
          ) : null}
          <path d={twinPath(w)} transform={twinTransform(w)} fill="#000" stroke={rim} strokeWidth={rimWidth / w.scale} />
        </>
      ) : null}
      {/* eyes: they are what makes it a slime, even at a few points */}
      <g transform={twinTransform(w)}>
        {([-1, 1] as const).map((sd) => {
          const cx = 50 + sd * 14 + w.lean * 0.5;
          const cy = top + 37 * w.h;
          return (
            <React.Fragment key={sd}>
              <ellipse cx={cx} cy={cy} rx={9.5} ry={11.5} fill="#fff" />
              <circle cx={cx + w.lookX * 2.6} cy={cy + 1} r={5.4} fill="#000" />
            </React.Fragment>
          );
        })}
      </g>
    </g>
  );
};

/** The shapes of the attached twins, for the outline Yumi shares with them. */
export const JoinedShapes: React.FC<{
  readonly joined: readonly Twin[];
  readonly paint: (kind: "body" | "strand", w: Twin) => React.SVGProps<SVGPathElement>;
}> = ({ joined, paint }) => (
  <>
    {joined.map((w, i) => (
      <React.Fragment key={i}>
        <path d={twinPath(w)} transform={twinTransform(w)} {...paint("body", w)} />
        {w.strand > 0.5 ? <path d={strandLine(w)} strokeLinecap="round" fill="none" {...paint("strand", w)} /> : null}
      </React.Fragment>
    ))}
  </>
);

/** Everything a scene draws around Yumi, except the slimes. `top` is the top of his head. */
export const SceneExtras: React.FC<{
  readonly m: SceneMoment;
  readonly rim: readonly RGB[];
  readonly top: number;
  readonly faceShift: { readonly x: number; readonly y: number };
}> = ({ m, rim, top, faceShift }) => {
  const { t, amount: n } = m;
  const mid = rgb(rim[1]);
  const spring = (p: number) => curve(CURVES.spring, p);
  switch (m.name) {
    case "star": {
      // one star falls for each, a little apart; then his eyes sparkle
      const glow = Math.sin(Math.PI * seg(t, 0.62, 1.6));
      return (
        <g>
          {Array.from({ length: n }, (_, i) => {
            const p = seg(t - i * 0.09, 0, 0.6);
            if (p <= 0 || p >= 1) return null;
            const side = i === 0 ? 0 : (i % 2 === 0 ? 1 : -1) * Math.floor((i + 1) / 2) * 13;
            return (
              <path
                key={i}
                d={star(i === 0 ? 9 : 6.5, 5, 0.45)}
                fill={GOLD}
                transform={`translate(${50 + side * (1 - p)} ${-48 + (top + 4 + 48) * p * p}) rotate(${300 * p})`}
              />
            );
          })}
          {glow > 0.02
            ? [37, 63].map((cx) => (
                <path
                  key={cx}
                  d={star((5.5 + n - 1) * glow, 4, 0.32)}
                  fill={GOLD}
                  transform={`translate(${cx + faceShift.x + 2} ${45 + faceShift.y - 2}) rotate(${t * 120})`}
                />
              ))
            : null}
        </g>
      );
    }
    case "pullRequest": {
      // a small branch held up at the end of his arm
      const k = spring(seg(t, 0.2, 0.6)) * (1 - seg(t, 1.45, 1.75));
      if (k <= 0.02) return null;
      const nodes: [number, number][] = [[0, 10], [0, -10], [9, -6]];
      if (n > 1) nodes.push([-8, -9]);
      return (
        <g transform={`translate(103 22) scale(${1.8 * k})`} opacity={Math.min(1, k)}>
          <path d={`M0 10L0 -10M0 4Q9 4 9 -6${n > 1 ? "M0 0Q-8 0 -8 -9" : ""}`} stroke={mid} strokeWidth={2.4} strokeLinecap="round" fill="none" />
          {nodes.map(([x, y]) => (
            <circle key={`${x},${y}`} cx={x} cy={y} r={3} fill="#000" stroke={mid} strokeWidth={2.2} />
          ))}
        </g>
      );
    }
    case "push":
      // a drop thrown straight up, stretched by its speed
      return (
        <g>
          {Array.from({ length: n }, (_, i) => {
            const p = seg(t - 0.28 - i * 0.09, 0, 0.65);
            if (p <= 0 || p >= 1) return null;
            const x = 50 + (i === 0 ? 0 : (i % 2 === 0 ? 1 : -1) * Math.floor((i + 1) / 2) * 8);
            const y = top - 4 - 78 * curve(CURVES.easeOut, p);
            const r = (i === 0 ? 5 : 3.6) * (1 - 0.35 * p);
            return (
              <g key={i} opacity={1 - seg(p, 0.7, 1)} fill={mid}>
                <ellipse cx={x} cy={y} rx={r * 0.8} ry={r * 1.5} />
                <circle cx={x} cy={y + r * 2.6} r={r * 0.4} />
              </g>
            );
          })}
        </g>
      );
    case "commit": {
      // a little line beside him, and a dot that adds itself to it
      const k = seg(t, 0, 0.2) * (1 - seg(t, 1.3, 1.6));
      if (k <= 0.02) return null;
      return (
        <g opacity={k}>
          <path d={`M113 68L113 ${24 - (n - 1) * 5}`} stroke={mid} strokeWidth={2.2} strokeLinecap="round" />
          {[62, 50].map((y) => (
            <circle key={y} cx={113} cy={y} r={3.4} fill="#000" stroke={mid} strokeWidth={2} />
          ))}
          {Array.from({ length: Math.min(n, 3) }, (_, i) => {
            const s = spring(seg(t, 0.45 + i * 0.16, 0.75 + i * 0.16));
            return s > 0.02 ? <circle key={i} cx={113} cy={38 - i * 11} r={4.6 * s} fill={mid} /> : null;
          })}
        </g>
      );
    }
    case "issue": {
      // a mark pops above his head
      const k = spring(seg(t, 0.1, 0.45)) * (1 - seg(t, 1.35, 1.7));
      if (k <= 0.02) return null;
      return (
        <g
          transform={`translate(50 ${top - 18}) rotate(${6 * Math.sin(t * 9) * (1 - seg(t, 0.4, 1.2))}) scale(${(1 + 0.14 * (n - 1)) * k})`}
          opacity={Math.min(1, k)}
        >
          <circle r={10} fill="#000" stroke={mid} strokeWidth={2.4} />
          <path d="M0 -5.5L0 1.5" stroke="#fff" strokeWidth={2.8} strokeLinecap="round" />
          <circle cy={5.6} r={1.6} fill="#fff" />
        </g>
      );
    }
    case "release": {
      // confetti thrown from above his head; the positions only depend on the index
      const u = t - 0.1;
      if (u <= 0) return null;
      const colours = [rgb(rim[0]), rgb(rim[1]), rgb(rim[2]), GOLD, "rgb(61,220,151)"];
      return (
        <g opacity={1 - seg(t, 1.5, 1.95)}>
          {Array.from({ length: 14 + 6 * (n - 1) }, (_, i) => {
            const angle = -Math.PI / 2 + (((i * 0.618) % 1) - 0.5) * 2.4;
            const speed = 70 + 55 * ((i * 0.377) % 1);
            const x = 50 + Math.cos(angle) * speed * u * (1 - 0.25 * u);
            const y = top + Math.sin(angle) * speed * u + 95 * u * u;
            const turn = ((i + u * (4 + (i % 3))) * 180) / Math.PI;
            return <rect key={i} x={-2.4} y={-1.3} width={4.8} height={2.6} fill={colours[i % colours.length]} transform={`translate(${x} ${y}) rotate(${turn})`} />;
          })}
        </g>
      );
    }
    default:
      return null;
  }
};
