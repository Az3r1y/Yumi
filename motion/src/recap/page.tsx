import { Video } from "@remotion/media";
import React from "react";
import { Sequence, staticFile, useVideoConfig } from "remotion";
import { CLAMP, ease, useT } from "../linkedin/journee/prises";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";

// The magazine page the recap is set on, after JourneeEdito: paper, ink, large type, the real
// takes as dark slices of the screen laid on the page. Written for 16:9 and 4:5: `useMise`
// says where things go in each.

export { CLAMP, ease, useT };

export const P = {
  paper: "#ECE9E1",
  ink: "#0C0C10",
  soft: "#55545C",
  faint: "#9A978F",
  matcha: "#B4C98C",
  amber: "#C77A10",
  green: "#1F8F5A",
  light: "linear-gradient(90deg, #5B8CFF, #8B6CFF 50%, #F58AD9)",
  mono: '"SF Mono", ui-monospace, Menlo, monospace',
};

export type Rect = { readonly x: number; readonly y: number; readonly w: number; readonly h: number };

/** Where things go: 16:9 puts the type on the left and the takes on the right, 4:5 stacks them. */
export const useMise = () => {
  const { width, height } = useVideoConfig();
  const wide = width / height > 1.2;
  return wide
    ? {
        W: width,
        H: height,
        wide,
        margin: 120,
        kickerY: 96,
        titleY: 168,
        titleSize: 88,
        /** The right column: takes and anything that is not type. Takes bleed off the right edge. */
        stage: { x: 960, y: 230, w: 960, h: 520 },
        captionY: 850,
        captionW: 1400,
        footY: 985,
      }
    : {
        W: width,
        H: height,
        wide,
        margin: 80,
        kickerY: 86,
        titleY: 150,
        titleSize: 84,
        stage: { x: 80, y: 560, w: 1000, h: 380 },
        captionY: 990,
        captionW: 920,
        footY: 1250,
      };
};

/** The small line above the title: number and subject of the chapter. */
export const Kicker: React.FC<{ readonly at: number; readonly end: number; readonly children: string }> = ({ at, end, children }) => {
  const m = useMise();
  return (
    <div style={{ position: "absolute", left: m.margin, top: m.kickerY }}>
      <Words
        lines={[children]}
        enter={at}
        exit={end}
        size={28}
        stagger={0.05}
        style={{ textAlign: "left", fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", color: P.soft, whiteSpace: "nowrap" }}
      />
    </div>
  );
};

/** A small figure set on the right of the kicker line, "03 / 10". */
export const Folio: React.FC<{ readonly at: number; readonly end: number; readonly children: string }> = ({ at, end, children }) => {
  const m = useMise();
  return (
    <div style={{ position: "absolute", right: m.margin, top: m.kickerY }}>
      <Words lines={[children]} enter={at} exit={end} size={28} stagger={0.03} by="letter" style={{ textAlign: "right", fontFamily: P.mono, fontWeight: 500, color: P.soft }} />
    </div>
  );
};

/** The big type of a beat, with an optional line under it. */
export const Titre: React.FC<{
  readonly at: number;
  readonly end?: number;
  readonly lines: readonly string[];
  readonly sub?: string;
  readonly size?: number;
  readonly color?: string;
  readonly y?: number;
}> = ({ at, end, lines, sub, size, color = P.ink, y }) => {
  const m = useMise();
  const s = size ?? m.titleSize;
  const t = useT();
  const subIn = sub ? ease(t, at + 0.35, at + 0.8, EASE.out) * (end === undefined ? 1 : 1 - ease(t, end - 0.05, end + 0.25, EASE.in)) : 0;
  return (
    <div style={{ position: "absolute", left: m.margin - s * 0.05, top: y ?? m.titleY, width: m.wide ? 840 : 940 }}>
      <Words lines={lines} enter={at} exit={end} size={s} style={{ textAlign: "left", fontWeight: 800, lineHeight: 1.0, whiteSpace: "nowrap", color }} />
      {sub ? (
        <div
          style={{
            marginTop: 26,
            marginLeft: s * 0.05,
            fontFamily: THEME.text,
            fontSize: m.wide ? 34 : 32,
            fontWeight: 600,
            lineHeight: 1.3,
            color: P.soft,
            opacity: subIn,
            clipPath: `inset(0 ${(1 - subIn) * 100}% 0 0)`,
            textWrap: "balance",
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );
};

/** The sentence of the beat, at the bottom: the film reads without sound. */
export const Legende: React.FC<{ readonly at: number; readonly end: number; readonly children: string }> = ({ at, end, children }) => {
  const t = useT();
  const m = useMise();
  if (t < at - 0.05 || t > end + 0.05) return null;
  const k = ease(t, at, at + 0.35, EASE.out) * (1 - ease(t, end - 0.2, end, EASE.in));
  return (
    <div
      style={{
        position: "absolute",
        left: m.margin,
        top: m.captionY,
        width: m.captionW,
        fontFamily: THEME.text,
        fontSize: m.wide ? 42 : 40,
        fontWeight: 600,
        lineHeight: 1.2,
        letterSpacing: "-0.015em",
        color: P.ink,
        opacity: k,
        clipPath: `inset(0 ${(1 - k) * 100}% 0 0)`,
        textWrap: "balance",
      }}
    >
      {children}
    </div>
  );
};

/** One of the real takes in public/prises, its size in pixels. */
export const TAKES = {
  ile: { w: 1680, h: 1040 },
  apercu: { w: 1680, h: 1040 },
  lancement: { w: 1680, h: 1040 },
  github: { w: 1680, h: 1040 },
  "journee-temps-libre": { w: 1380, h: 500 },
  "journee-sessions": { w: 1380, h: 500 },
  "journee-matcha": { w: 1380, h: 500 },
} as const;

/**
 * A part of a real take, `crop` in pixels of the take, laid in the right column as wide as
 * it, centred in its height. It opens sideways from the edge it bleeds off, and closes the same
 * way, unless `stays`: then the next take covers it.
 */
export const Plan: React.FC<{
  readonly take: keyof typeof TAKES;
  readonly source: number;
  readonly crop: Rect;
  readonly from: number;
  readonly to: number;
  readonly stays?: boolean;
  /** In 4:5, which edge the take bleeds off. */
  readonly bleed?: "left" | "right";
}> = ({ take, source, crop, from, to, stays = false, bleed = "right" }) => {
  const t = useT();
  const { fps } = useVideoConfig();
  const m = useMise();
  const w = m.wide ? m.stage.w : m.W - m.margin;
  const x = m.wide ? m.stage.x : bleed === "right" ? m.margin : 0;
  const h = Math.round((w * crop.h) / crop.w);
  const y = Math.round(m.stage.y + m.stage.h / 2 - h / 2);
  const s = w / crop.w;
  const end = stays ? to + 0.6 : to;
  const open = ease(t, from, from + 0.55) * (stays ? 1 : 1 - ease(t, to - 0.35, to, EASE.in));
  const hidden = (1 - open) * 100;
  const fromRight = m.wide || bleed === "right";
  const size = TAKES[take];
  return (
    <Sequence from={Math.round(from * fps)} durationInFrames={Math.round((end - from) * fps)} layout="none">
      <div
        style={{
          position: "absolute",
          left: x,
          top: y,
          width: w,
          height: h,
          overflow: "hidden",
          backgroundColor: "#000",
          clipPath: fromRight ? `inset(0 0 0 ${hidden}%)` : `inset(0 ${hidden}% 0 0)`,
        }}
      >
        <Video
          src={staticFile(`prises/${take}.mp4`)}
          muted
          trimBefore={Math.round(source * fps)}
          style={{ position: "absolute", left: -crop.x * s, top: -crop.y * s, width: size.w * s, height: size.h * s }}
        />
      </div>
    </Sequence>
  );
};

/** The foot of the page: Yumi's light as a rule, and a quiet line under it. */
export const Pied: React.FC<{ readonly lines: readonly { readonly at: number; readonly end: number; readonly text: string }[] }> = ({ lines }) => {
  const t = useT();
  const m = useMise();
  return (
    <>
      <div
        style={{
          position: "absolute",
          left: m.margin,
          top: m.footY,
          width: (m.W - m.margin * 2) * ease(t, 0.2, 1.4),
          height: 4,
          background: P.light,
        }}
      />
      {lines.map((l) => (
        <div
          key={l.text + l.at}
          style={{
            position: "absolute",
            left: m.margin,
            top: m.footY + 22,
            fontFamily: THEME.text,
            fontSize: 26,
            fontWeight: 600,
            letterSpacing: "0.02em",
            color: P.soft,
            opacity: ease(t, l.at, l.at + 0.4) * (1 - ease(t, l.end - 0.3, l.end)),
          }}
        >
          {l.text}
        </div>
      ))}
    </>
  );
};
