import React, { useId } from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";
import { yumiFrameAt, type YumiFrame, type YumiScript } from "./engine";
import type { RGB } from "./faces";
import { CURVES, curve, keyframes } from "./motion";

// Port of Character/YumiRenderer.swift: Yumi drawn element for element as the mock-up does,
// in its 100 × 84 box (the body spans x 8…92 and y 8…76 at rest).

const BLUR = 3.2;
const INK = "#000";

/** `bodyPath(h, w, L)` of the mock-up: h is the height, w the width, L the lean of the top. */
export const bodyPath = (h: number, w: number, L: number): string => {
  const by = 76;
  const ty = by - 68 * h;
  const tx = 50 + L;
  const sy = by - 14 * Math.pow(h, 0.7);
  const wb = 1 + (w - 1) * 0.55;
  const lx = 50 - 42 * w + L * 0.12;
  const rx = 50 + 42 * w + L * 0.12;
  const cy = sy - 31 * h;
  const my = sy + (by - sy) * 0.71;
  return [
    `M${lx} ${sy}`,
    `C${lx} ${cy} ${tx - 23 * w} ${ty} ${tx} ${ty}`,
    `C${tx + 23 * w} ${ty} ${rx} ${cy} ${rx} ${sy}`,
    `C${rx} ${my} ${50 + 32 * wb} ${by} 50 ${by}`,
    `C${50 - 32 * wb} ${by} ${lx} ${my} ${lx} ${sy}`,
    "Z",
  ].join("");
};

const rgb = ([r, g, b]: RGB) => `rgb(${r.toFixed(1)},${g.toFixed(1)},${b.toFixed(1)})`;
const loop = (t: number, period: number) => (t < 0 ? 0 : (t / period) % 1);

// Keyframes that the mock-up runs in CSS while a pose plays (`p-arml`, `p-armr`, `p-spark`)
const EXTRAS = 1.5;
const SPARKS = [
  { x: 8, y: 14, scale: 1, delay: 0 },
  { x: 92, y: 10, scale: 1.3, delay: 0.15 },
  { x: 50, y: -4, scale: 0.9, delay: 0.3 },
] as const;
const STAR = "M0 -5L1.3 -1.3L5 0L1.3 1.3L0 5L-1.3 1.3L-5 0L-1.3 -1.3Z";

/** `p-zz` of the mock-up: fades in, drifts up and to the right, fades out. */
const Drift: React.FC<{
  readonly children: string;
  readonly size: number;
  readonly x: number;
  readonly y: number;
  readonly fill: string;
  readonly time: number;
  readonly period: number;
  readonly opacity: number;
}> = ({ children, size, x, y, fill, time, period, opacity }) => {
  if (time < 0) return null;
  const p = loop(time, period);
  const alpha = keyframes(p, [[0, 0], [0.3, 1], [1, 0]], CURVES.easeInOut) * opacity;
  if (alpha <= 0.01) return null;
  const e = curve(CURVES.easeInOut, p);
  const cx = x + size * 0.3;
  const cy = y - size * 0.35;
  const s = 0.6 + 0.5 * e;
  return (
    <text
      x={x}
      y={y}
      fontSize={size}
      fontWeight={800}
      fontFamily='ui-rounded, "SF Pro Rounded", system-ui, sans-serif'
      fill={fill}
      opacity={alpha}
      transform={`translate(${8 * e} ${4 - 18 * e}) translate(${cx} ${cy}) scale(${s}) translate(${-cx} ${-cy})`}
    >
      {children}
    </text>
  );
};

const Eye: React.FC<{ readonly f: YumiFrame; readonly sd: -1 | 1; readonly white: string }> = ({ f, sd, white }) => {
  const left = sd < 0;
  const cx = 50 + sd * 13;
  const es = left ? f.face.esl : f.face.esr;
  const lidTop = left ? f.face.tl : f.face.tr;
  const lidAngle = left ? f.face.al : f.face.ar;
  const lidBottom = left ? f.face.bl : f.face.br;
  const shut = left ? f.face.cl : f.face.cr;

  // The eyes sit on a sphere: turning the head slides them sideways and narrows
  // the one going round the edge
  const ya = sd * 0.33 + f.yaw;
  const pi = f.pitch;
  const ex = Math.sin(ya) * Math.cos(pi) * 40.1;
  const ey = Math.sin(pi) * 30;
  const about = (x: number, y: number, inner: string) => `translate(${x} ${y}) ${inner} translate(${-x} ${-y})`;

  return (
    <g
      transform={`translate(${ex - sd * 13} ${ey}) ${about(cx, 45, `scale(${Math.max(0.35, Math.cos(ya))} ${Math.max(0.6, Math.cos(pi))})`)}`}
    >
      {/* White of the eye, with the blink */}
      <g transform={about(cx, 45, `scale(${es} ${es * f.blink})`)}>
        <ellipse cx={cx} cy={45} rx={9} ry={11} fill={`url(#${white})`} />
        {/* Pupil and its two reflections */}
        <g transform={`translate(${f.pupil.x * 2.2} ${f.pupil.y * 2}) ${about(cx, 46, `scale(${f.face.ps})`)}`}>
          <circle cx={cx} cy={46} r={5.4} fill={INK} />
          <circle cx={cx + 1.9} cy={43.6} r={1.7} fill="#fff" />
          <circle cx={cx - 1.6} cy={48.2} r={0.8} fill="#fff" opacity={0.7} />
        </g>
      </g>
      {/* Upper lid: a black block that comes down, and tilts for the eyebrows */}
      <rect
        x={cx - 17}
        y={8}
        width={34}
        height={26}
        fill={INK}
        transform={`${about(cx, 45, `rotate(${lidAngle})`)} translate(0 ${lidTop * 25 - 3})`}
      />
      {/* Lower lid: the cheek pushing up */}
      <ellipse cx={cx} cy={68 - lidBottom * 22} rx={16} ry={12} fill={INK} />
      {shut > 0.01 ? (
        <path
          d={`M${cx - 8} 45Q${cx} 51 ${cx + 8} 45`}
          fill="none"
          stroke="#fff"
          strokeWidth={2.6}
          strokeLinecap="round"
          opacity={shut}
        />
      ) : null}
    </g>
  );
};

/** One image of Yumi. The svg is the 100 × 84 box; what he does around it overflows. */
export const YumiFigure: React.FC<{
  readonly frame: YumiFrame;
  /** Width of the 100-unit box, in pixels. */
  readonly size: number;
  /** Rim width in units: 2.6 at full size, thicker when he is small (see `SEATS` in the mock-up). */
  readonly rimWidth?: number;
  readonly style?: React.CSSProperties;
}> = ({ frame: f, size, rimWidth = 2.6, style }) => {
  const id = useId().replace(/:/g, "");
  const ids = {
    rim: `${id}rim`, fade: `${id}fade`, fadeG: `${id}fadeG`, lower: `${id}lower`, lowerG: `${id}lowerG`,
    blur: `${id}blur`, body: `${id}body`, white: `${id}white`, shine: `${id}shine`,
  };
  const rim = `url(#${ids.rim})`;
  const body = bodyPath(f.h, f.w, f.lean);
  const top = 76 - 68 * f.h;
  const lit = f.light > 0.01;

  const tilt = f.face.tilt !== 0 ? `rotate(${f.face.tilt} 50 76)` : undefined;
  const pose = `translate(${-f.lean * 0.12} ${f.y})`;
  const faceBox = `translate(${f.faceShift.x} ${f.faceShift.y}) translate(50 45) scale(${f.faceScale.x} ${f.faceScale.y}) translate(-50 -45)`;

  const arm = f.armTime !== null && f.armTime <= EXTRAS
    ? {
        opacity: keyframes(f.armTime / EXTRAS, [[0, 0], [0.1, 1], [0.88, 1], [1, 0]], CURVES.easeInOut),
        angle: keyframes(
          f.armTime / EXTRAS,
          [[0, 45], [0.22, -14], [0.37, 16], [0.52, -14], [0.66, 16], [0.8, -14], [1, 45]],
          CURVES.easeInOut,
        ),
      }
    : null;

  const arms = arm && arm.opacity > 0.01 ? (
    <g transform={`translate(${f.lean * 0.35} ${(1 - f.h) * 24})`} opacity={arm.opacity}>
      {([-1, 1] as const).map((sd) => {
        const d = `M${50 + sd * 33} 52L${50 + sd * 45} 37`;
        return (
          <g key={sd} transform={`rotate(${-sd * arm.angle} ${50 + sd * 33} 52)`}>
            <path d={d} stroke={rim} strokeWidth={12} strokeLinecap="round" />
            <path d={d} stroke={INK} strokeWidth={8.4} strokeLinecap="round" />
          </g>
        );
      })}
    </g>
  ) : null;

  const glasses = curve(CURVES.spring, f.habitTime / 0.55);
  const bubble = loop(f.habitTime, 3.2);
  const notes = Math.max(f.props.headphones, f.props.whistle);

  return (
    <svg
      viewBox="0 0 100 84"
      width={size}
      height={size * 0.84}
      style={{ overflow: "visible", display: "block", ...style }}
    >
      <defs>
        <linearGradient id={ids.rim} x1="0" x2="1" y1="0" y2="0">
          <stop offset="0" stopColor={rgb(f.rim[0])} />
          <stop offset="0.5" stopColor={rgb(f.rim[1])} />
          <stop offset="1" stopColor={rgb(f.rim[2])} />
        </linearGradient>
        {/* Fades the top of the rim and of the glow: the light is stronger at the base and on the sides */}
        <linearGradient id={ids.fadeG} gradientUnits="userSpaceOnUse" x1="0" y1="-10" x2="0" y2="100">
          <stop offset="0" stopColor="#fff" stopOpacity={0.28} />
          <stop offset="0.55" stopColor="#fff" />
        </linearGradient>
        <mask id={ids.fade} maskUnits="userSpaceOnUse" x={-120} y={-120} width={340} height={320}>
          <rect x={-120} y={-120} width={340} height={320} fill={`url(#${ids.fadeG})`} />
        </mask>
        {/* Keeps the inner light to the lower part of the body */}
        <linearGradient id={ids.lowerG} gradientUnits="userSpaceOnUse" x1="0" y1="20" x2="0" y2="80">
          <stop offset="0" stopColor="#fff" stopOpacity={0} />
          <stop offset="1" stopColor="#fff" />
        </linearGradient>
        <mask id={ids.lower} maskUnits="userSpaceOnUse" x={-120} y={-120} width={340} height={320}>
          <rect x={-120} y={-120} width={340} height={320} fill={`url(#${ids.lowerG})`} />
        </mask>
        {/* Only as large as the light can reach: a blur costs by the area it covers */}
        <filter id={ids.blur} filterUnits="userSpaceOnUse" x={-40} y={Math.min(top, 74) - 12} width={180} height={96 - (Math.min(top, 74) - 12)}>
          <feGaussianBlur stdDeviation={BLUR} />
        </filter>
        <clipPath id={ids.body}>
          <path d={body} />
        </clipPath>
        <radialGradient id={ids.white} cx="0.42" cy="0.36" r="0.75">
          <stop offset="0.45" stopColor="#fff" />
          <stop offset="1" stopColor="rgb(180,191,230)" />
        </radialGradient>
        <radialGradient id={ids.shine}>
          <stop offset="0" stopColor="#fff" stopOpacity={0.2} />
          <stop offset="1" stopColor="#fff" stopOpacity={0} />
        </radialGradient>
      </defs>

      {/* The head tilt turns everything around the base */}
      <g transform={tilt} fill="none">
        {/* Light pooled on the floor */}
        {lit ? (
          <ellipse
            cx={50}
            cy={78}
            rx={34 * f.w * (f.air ? 0.7 : 1)}
            ry={4}
            fill={rim}
            opacity={0.35 * f.light}
            filter={`url(#${ids.blur})`}
          />
        ) : null}

        {/* The body follows the lean a little, and jumps */}
        <g transform={pose}>
          {arms}
          {/* Halo */}
          {lit ? (
            <g opacity={0.85 * f.light} mask={`url(#${ids.fade})`}>
              <path d={body} stroke={rim} strokeWidth={rimWidth * 2.2} filter={`url(#${ids.blur})`} />
            </g>
          ) : null}

          {/* The body is pure black: unlit on a black frame, only the eyes show */}
          <path d={body} fill={INK} />

          <g clipPath={`url(#${ids.body})`}>
            <g transform={faceBox}>
              <Eye f={f} sd={-1} white={ids.white} />
              <Eye f={f} sd={1} white={ids.white} />
            </g>
            {lit ? (
              <>
                {/* Light spilling inside the outline */}
                <g opacity={0.5 * f.light} mask={`url(#${ids.lower})`}>
                  <path d={body} stroke={rim} strokeWidth={11} filter={`url(#${ids.blur})`} />
                </g>
                {/* Soft reflection and its small glint: they slide when the head turns */}
                <circle
                  r={1}
                  fill={`url(#${ids.shine})`}
                  opacity={f.light}
                  transform={`translate(${35 + f.lean * 0.8 - f.yaw * 12} ${top + 16 * f.h - f.pitch * 6}) rotate(-28) scale(${19 * f.w} ${11 * Math.pow(f.h, 0.7)})`}
                />
                <ellipse
                  rx={4.2}
                  ry={1.9}
                  fill="#fff"
                  opacity={0.5 * f.light}
                  transform={`translate(${31 + f.lean * 0.8 - f.yaw * 12} ${top + 11 * f.h - f.pitch * 6}) rotate(-32)`}
                />
              </>
            ) : null}
          </g>

          {/* The rim, crisp. It is drawn from the left side, over the top, and round the base. */}
          {f.drawn > 0.001 ? (
            <g mask={`url(#${ids.fade})`}>
              <path
                d={body}
                stroke={rim}
                strokeWidth={rimWidth}
                pathLength={1}
                strokeDasharray={f.drawn >= 0.999 ? undefined : `${f.drawn} 1`}
              />
            </g>
          ) : null}

          {/* Props above the head */}
          <g transform={`translate(${f.lean} ${68 - 68 * f.h})`}>
            {f.props.headphones > 0.01 ? (
              <g opacity={f.props.headphones}>
                <path d="M9 47C9 16 28 1 50 1C72 1 91 16 91 47" stroke="rgb(43,46,63)" strokeWidth={4.2} strokeLinecap="round" />
                <rect x={2} y={38} width={11} height={20} rx={5} fill="rgb(31,34,49)" stroke={rim} strokeWidth={1.4} />
                <rect x={87} y={38} width={11} height={20} rx={5} fill="rgb(31,34,49)" stroke={rim} strokeWidth={1.4} />
              </g>
            ) : null}
            {f.props.cloud > 0.01 ? (
              <g opacity={f.props.cloud}>
                <g fill="rgb(90,96,120)">
                  <ellipse cx={50} cy={-9} rx={17} ry={6.5} />
                  <circle cx={40} cy={-12} r={7} />
                  <circle cx={53} cy={-15.5} r={8.5} />
                  <circle cx={62} cy={-10.5} r={6} />
                </g>
                {/* Rain: four drops falling in a 0.7 s loop, each with its own delay */}
                {([[40, 0], [48, 0.2], [56, 0.45], [63, 0.1]] as const).map(([x, delay]) => {
                  const p = loop(f.habitTime - delay, 0.7);
                  return (
                    <path
                      key={x}
                      d={`M${x} ${-1 + 9 * p}V${3 + 9 * p}`}
                      stroke="rgb(127,180,255)"
                      strokeWidth={1.5}
                      strokeLinecap="round"
                      opacity={1 - p}
                    />
                  );
                })}
              </g>
            ) : null}
          </g>

          {/* Props on the face */}
          <g transform={faceBox}>
            {f.props.coffee > 0.01 ? (
              // The cup tips towards the mouth for a sip
              <g
                opacity={f.props.coffee}
                transform={`translate(8 8) translate(66 60) rotate(${-30 * f.sip}) translate(${-3 * f.sip} ${-3 * f.sip}) translate(-66 -60)`}
              >
                <path d="M65 54H78V60A6.5 6.5 0 0 1 65 60Z" fill="rgb(244,245,248)" />
                <path d="M78 56Q83.5 56 83.5 59.6Q83.5 63.2 78 63" stroke="rgb(244,245,248)" strokeWidth={1.9} />
                <path d="M66.6 55.4H76.4" stroke="rgb(107,66,38)" strokeWidth={1.7} strokeLinecap="round" />
              </g>
            ) : null}
            {f.props.sunglasses > 0.01 ? (
              // They drop onto his nose in 0.55 s
              <g
                opacity={f.props.sunglasses * Math.max(0, Math.min(1, glasses))}
                transform={`translate(50 ${44.5 - 34 * (1 - glasses)}) rotate(${-14 * (1 - glasses)}) translate(-50 -44.5)`}
              >
                <rect x={24} y={37} width={24} height={15} rx={6} fill="rgb(10,11,16)" stroke={rim} strokeWidth={1.6} />
                <rect x={52} y={37} width={24} height={15} rx={6} fill="rgb(10,11,16)" stroke={rim} strokeWidth={1.6} />
                <path d="M48 42Q50 40.4 52 42" stroke={rgb(f.rim[1])} strokeWidth={1.6} />
                <path d="M29 47L35 41M57 47L63 41" stroke="#fff" strokeWidth={1.5} strokeLinecap="round" opacity={0.75} />
              </g>
            ) : null}
            {f.props.whistle > 0.01 ? (
              <circle cx={52} cy={61} r={2.7} stroke="#fff" strokeWidth={1.7} opacity={f.props.whistle} />
            ) : null}
            {f.props.sleep > 0.01 ? (
              // A bubble swells at his nose and bursts, every 3.2 s
              <circle
                cx={58}
                cy={57}
                r={6.5}
                fill="rgba(155,184,255,0.22)"
                stroke="rgb(155,184,255)"
                strokeWidth={1}
                opacity={f.props.sleep * keyframes(bubble, [[0, 1], [0.8, 1], [0.84, 0], [1, 0]], CURVES.easeInOut)}
                transform={`translate(53.45 61.55) scale(${keyframes(bubble, [[0, 0.15], [0.7, 1], [0.8, 1.25], [0.84, 1.5], [1, 1.5]], CURVES.easeInOut)}) translate(-53.45 -61.55)`}
              />
            ) : null}
          </g>
        </g>

        {/* Droplets and steam live in the tilted space, outside the pose */}
        {f.drops.slice(0, 12).map((d, i) => {
          const r = d.r * Math.min(1, d.life * 3);
          return r > 0.05 ? <circle key={i} cx={d.x} cy={d.y} r={r} fill={rim} /> : null;
        })}
        {f.puffs.map((p, i) => {
          const k = p.life / p.max;
          return <circle key={i} cx={p.x} cy={p.y} r={p.r * (1 + (1 - k) * 2.2)} fill="rgb(217,220,232)" opacity={0.5 * k} />;
        })}
      </g>

      {notes > 0.01 ? (
        <>
          <Drift size={11} x={84} y={22} fill={rim} time={f.habitTime} period={2.2} opacity={notes}>♪</Drift>
          <Drift size={14} x={93} y={10} fill={rim} time={f.habitTime - 0.7} period={2.2} opacity={notes}>♫</Drift>
          <Drift size={10} x={100} y={26} fill={rim} time={f.habitTime - 1.4} period={2.2} opacity={notes}>♪</Drift>
        </>
      ) : null}

      {f.sparkTime !== null
        ? SPARKS.map((s) => {
            const t = f.sparkTime! - s.delay;
            if (t < 0 || t > EXTRAS) return null;
            const p = t / EXTRAS;
            const k = (a: number, b: number, c: number) => keyframes(p, [[0, a], [0.3, b], [1, c]], CURVES.easeOut);
            return (
              <path
                key={s.delay}
                d={STAR}
                fill={rim}
                opacity={k(0, 1, 0)}
                transform={`translate(${s.x} ${s.y}) scale(${s.scale}) translate(0 ${k(0, 0, -6)}) rotate(${k(0, 20, 60)}) scale(${k(0.2, 1.1, 0.6)})`}
              />
            );
          })
        : null}

      {f.props.sleep > 0.01 ? (
        <>
          <Drift size={9} x={78} y={26} fill="rgb(155,184,255)" time={f.habitTime} period={2.6} opacity={f.props.sleep}>z</Drift>
          <Drift size={12} x={86} y={16} fill="rgb(155,184,255)" time={f.habitTime - 0.8} period={2.6} opacity={f.props.sleep}>z</Drift>
          <Drift size={15} x={94} y={6} fill="rgb(155,184,255)" time={f.habitTime - 1.6} period={2.6} opacity={f.props.sleep}>Z</Drift>
        </>
      ) : null}
    </svg>
  );
};

/** Yumi playing his script on the timeline he is placed in. */
export const Yumi: React.FC<{
  readonly script: YumiScript;
  readonly size: number;
  readonly rimWidth?: number;
  readonly style?: React.CSSProperties;
}> = ({ script, size, rimWidth, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return <YumiFigure frame={yumiFrameAt(script, frame, fps)} size={size} rimWidth={rimWidth} style={style} />;
};
