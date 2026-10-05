import React from "react";
import { Video } from "@remotion/media";
import { AbsoluteFill, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { EASE, THEME } from "../../theme";

// The pieces the masterclass is built from. Every scene is drawn for both frames, 16:9 and
// 9:16: `useCadre` says which one, and where things go in it.

export const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const MONO = '"SF Mono", ui-monospace, Menlo, monospace';

export const useT = () => {
  const { fps } = useVideoConfig();
  return useCurrentFrame() / fps;
};

export const ease = (t: number, a: number, b: number, easing = EASE.camera) =>
  interpolate(t, [a, b], [0, 1], { ...CLAMP, easing });

/** The frame: its size, whether it is vertical, and the main areas of a scene. */
export const useCadre = () => {
  const { width: W, height: H } = useVideoConfig();
  const vertical = H > W;
  return {
    W,
    H,
    vertical,
    /** Where a take or a window goes. */
    stage: vertical ? { x: 40, y: 430, w: 1000, h: 700 } : { x: 200, y: 120, w: 1520, h: 700 },
    /** Where the subtitles sit. */
    captionY: vertical ? 1330 : 880,
    captionW: vertical ? 960 : 1560,
    captionSize: vertical ? 52 : 46,
    /** A small label at the top: which part of the film this is. */
    labelY: vertical ? 300 : 52,
  };
};

/** Subtitles: one line at a time, burned in, readable without sound. Times in seconds of the scene. */
export const SousTitres: React.FC<{ readonly lines: readonly { readonly at: number; readonly end: number; readonly text: string }[] }> = ({ lines }) => {
  const t = useT();
  const c = useCadre();
  return (
    <>
      {lines.map((l) => {
        if (t < l.at - 0.05 || t > l.end + 0.05) return null;
        const k = ease(t, l.at, l.at + 0.35, EASE.out) * (1 - ease(t, l.end - 0.25, l.end, EASE.in));
        return (
          <div
            key={l.at}
            style={{
              position: "absolute",
              left: (c.W - c.captionW) / 2,
              width: c.captionW,
              top: c.captionY,
              textAlign: "center",
              fontFamily: THEME.text,
              fontSize: c.captionSize,
              fontWeight: 600,
              lineHeight: 1.25,
              letterSpacing: "-0.01em",
              color: THEME.fg,
              opacity: k,
              translate: `0 ${(1 - k) * 14}px`,
              textShadow: "0 2px 18px rgba(0,0,0,0.9)",
            }}
          >
            {l.text}
          </div>
        );
      })}
    </>
  );
};

/** The small label at the top of a scene. */
export const Rubrique: React.FC<{ readonly children: string }> = ({ children }) => {
  const t = useT();
  const c = useCadre();
  return (
    <div
      style={{
        position: "absolute",
        top: c.labelY,
        left: 0,
        right: 0,
        textAlign: "center",
        fontFamily: THEME.text,
        fontSize: c.vertical ? 34 : 26,
        fontWeight: 600,
        letterSpacing: "0.14em",
        textTransform: "uppercase",
        color: THEME.muted,
        opacity: ease(t, 0.1, 0.5),
      }}
    >
      {children}
    </div>
  );
};

/**
 * A real take from the app (public/prises, the top of the screen around the notch, 1680 × 1040
 * pixels for 840 × 520 points), seen through a rounded screen that fills `box`.
 */
export const Ecran: React.FC<{
  readonly take: string;
  readonly source: number;
  readonly rate?: number;
  readonly box: { x: number; y: number; w: number; h: number };
  /** A point of the box the camera closes in on, and how close. */
  readonly focus?: readonly [number, number];
  readonly zoom?: number;
  readonly opacity?: number;
  readonly children?: React.ReactNode;
}> = ({ take, source, rate = 1, box, focus, zoom = 1, opacity = 1, children }) => {
  const { fps } = useVideoConfig();
  const c = useCadre();
  const scale = box.w / 1680;
  const f = focus ?? [box.w / 2, 0];
  // In 9:16 the screen is narrow: the camera stays closer on the island, so its text reads
  const base = c.vertical ? 1.12 : 1;
  return (
    <div
      style={{
        position: "absolute",
        left: box.x,
        top: box.y,
        width: box.w,
        height: box.h,
        borderRadius: 28,
        overflow: "hidden",
        backgroundColor: "#000",
        boxShadow: "0 0 0 1.5px rgba(255,255,255,0.09), 0 40px 120px rgba(0,0,0,0.55)",
        opacity,
      }}
    >
      <div style={{ position: "absolute", inset: 0, transformOrigin: `${box.w / 2}px 0px`, scale: base }}>
        <Video
          src={staticFile(`prises/${take}.mp4`)}
          muted
          trimBefore={Math.round(source * fps)}
          playbackRate={rate}
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: box.w,
            height: 1040 * scale,
            transformOrigin: `${f[0]}px ${f[1]}px`,
            scale: zoom,
          }}
        />
        {/* Drawn over the take, in its own coordinates */}
        {children}
      </div>
    </div>
  );
};

/** A plain pointer arrow. `x`, `y` is its tip. */
export const Pointeur: React.FC<{ readonly x: number; readonly y: number; readonly size?: number; readonly press?: number; readonly opacity?: number }> = ({
  x,
  y,
  size = 40,
  press = 0,
  opacity = 1,
}) => (
  <svg
    width={size}
    height={size * 1.45}
    viewBox="0 0 18 26"
    style={{ position: "absolute", left: x - size * 0.06, top: y - size * 0.06, overflow: "visible", transformOrigin: "1px 1px", scale: 1 - 0.15 * press, opacity }}
  >
    <path d="M1 1L1 21L6 16.5L9.4 24.6L12.6 23.2L9.3 15.4L16 15.4Z" fill="#fff" stroke="#0B0C11" strokeWidth={1.4} strokeLinejoin="round" />
  </svg>
);

/** A click, as a ring that opens where it lands. */
export const Clic: React.FC<{ readonly x: number; readonly y: number; readonly at: number; readonly colour?: string }> = ({ x, y, at, colour = "rgba(255,255,255,0.85)" }) => {
  const t = useT();
  if (t < at || t > at + 0.6) return null;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        width: interpolate(t, [at, at + 0.5], [24, 120], { ...CLAMP, easing: EASE.out }),
        aspectRatio: "1",
        translate: "-50% -50%",
        borderRadius: "50%",
        border: `3px solid ${colour}`,
        opacity: interpolate(t, [at, at + 0.05, at + 0.55], [0, 1, 0], CLAMP),
      }}
    />
  );
};

/**
 * A window of macOS, drawn plainly: a title bar with three grey dots and a title, and its
 * content. Not a copy of the system's look, and no logo.
 */
export const Fenetre: React.FC<{
  readonly title: string;
  readonly box: { x: number; y: number; w: number; h: number };
  readonly children: React.ReactNode;
  readonly style?: React.CSSProperties;
}> = ({ title, box, children, style }) => (
  <div
    style={{
      position: "absolute",
      left: box.x,
      top: box.y,
      width: box.w,
      height: box.h,
      borderRadius: 22,
      overflow: "hidden",
      backgroundColor: "#16181F",
      boxShadow: "0 0 0 1.5px rgba(255,255,255,0.10), 0 40px 120px rgba(0,0,0,0.6)",
      fontFamily: THEME.text,
      color: THEME.fg,
      ...style,
    }}
  >
    <div
      style={{
        height: 56,
        display: "flex",
        alignItems: "center",
        padding: "0 22px",
        gap: 10,
        backgroundColor: "#1C1F28",
        borderBottom: "1px solid rgba(255,255,255,0.06)",
      }}
    >
      {[0, 1, 2].map((i) => (
        <span key={i} style={{ width: 14, height: 14, borderRadius: 7, backgroundColor: "rgba(255,255,255,0.18)" }} />
      ))}
      <span style={{ flex: 1, textAlign: "center", fontSize: 22, fontWeight: 600, color: THEME.muted, marginRight: 66 }}>{title}</span>
    </div>
    <div style={{ position: "relative", height: box.h - 56 }}>{children}</div>
  </div>
);

/** A button in a drawn window. `pressed` 0…1 darkens it for a click. */
export const Bouton: React.FC<{ readonly children: string; readonly primary?: boolean; readonly pressed?: number; readonly style?: React.CSSProperties }> = ({
  children,
  primary,
  pressed = 0,
  style,
}) => (
  <span
    style={{
      display: "inline-block",
      padding: "12px 26px",
      borderRadius: 12,
      fontSize: 24,
      fontWeight: 600,
      color: primary ? "#06070C" : THEME.fg,
      backgroundColor: primary ? `rgba(244,245,248,${1 - 0.25 * pressed})` : `rgba(255,255,255,${0.1 + 0.08 * pressed})`,
      ...style,
    }}
  >
    {children}
  </span>
);

/** The number of an install step, drawn as an outline in Yumi's light. */
export const Chiffre: React.FC<{ readonly n: number; readonly x: number; readonly y: number; readonly size: number }> = ({ n, x, y, size }) => {
  const t = useT();
  return (
    <svg width={size} height={size * 1.15} style={{ position: "absolute", left: x, top: y, overflow: "visible" }}>
      <defs>
        <linearGradient id={`chiffre${n}`} x1="0" x2="1">
          <stop offset="0" stopColor="#5B8CFF" />
          <stop offset="0.5" stopColor="#8B6CFF" />
          <stop offset="1" stopColor="#F58AD9" />
        </linearGradient>
      </defs>
      <text
        x={size / 2}
        y={size}
        textAnchor="middle"
        fontFamily={THEME.text}
        fontSize={size * 1.15}
        fontWeight={700}
        fill={`url(#chiffre${n})`}
        fillOpacity={ease(t, 0.5, 1.1)}
        stroke={`url(#chiffre${n})`}
        strokeWidth={3}
        strokeDasharray={size * 6}
        strokeDashoffset={interpolate(t, [0, 0.9], [size * 6, 0], { ...CLAMP, easing: EASE.camera })}
      >
        {n}
      </text>
    </svg>
  );
};

/** A scene that fades in and out over its own length. */
export const Plan: React.FC<{ readonly length: number; readonly children: React.ReactNode }> = ({ length, children }) => {
  const t = useT();
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black, opacity: ease(t, 0, 0.3) * (1 - ease(t, length - 0.3, length)) }}>{children}</AbsoluteFill>
  );
};
