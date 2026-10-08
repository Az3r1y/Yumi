import React from "react";
import { Video } from "@remotion/media";
import { AbsoluteFill, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import type { CalculateMetadataFunction } from "remotion";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";

// A short demo for TikTok, Reels and Shorts, built around a REAL screen recording of the app.
// Five beats: the hook, the take, the strong moment (a zoom), the proof, the end card.
//
// To make one: put the raw recording in public/demo/ (ignored by git if large), duplicate the
// default props below in Root.tsx with your own times, and render:
//   npx remotion render Demo-9x16 out/demo.mp4 --props='{"clip":"demo/rappel.mov", ...}'
// Never stage the take: the whole point is that it is the real app doing the real thing.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Length of the end card, in seconds. */
const END = 2.6;

export type DemoProps = {
  /** First words on screen, read in under a second. */
  readonly hook: string;
  /** The recording, relative to public/ (« demo/rappel.mov »). Empty: a placeholder is shown. */
  readonly clip: string;
  /** Where to start in the recording, and how long to keep, in seconds. */
  readonly clipStart: number;
  readonly clipLength: number;
  /** Size of the recording, in its own pixels. */
  readonly source: { readonly width: number; readonly height: number };
  /** The part of the recording to show (the notch, the island, the app where the result lands). */
  readonly crop: { readonly x: number; readonly y: number; readonly width: number; readonly height: number };
  /** The strong moment: a zoom on a point of the crop, in its own pixels, between two times of the video. */
  readonly highlight: { readonly at: number; readonly end: number; readonly x: number; readonly y: number; readonly zoom: number };
  /** The proof, written when it happens: « It's really in Reminders. » */
  readonly proof: { readonly at: number; readonly text: string };
  /** Burned-in captions, in seconds of the video. */
  readonly captions: readonly { readonly at: number; readonly end: number; readonly text: string }[];
  /** The two lines of the end card. */
  readonly endLine: string;
  readonly endCta: string;
};

export const DEMO_DEFAULTS: DemoProps = {
  hook: "The AI in my notch asks permission for everything.",
  clip: "",
  clipStart: 0,
  clipLength: 12,
  source: { width: 1680, height: 1040 },
  crop: { x: 240, y: 0, width: 1200, height: 900 },
  highlight: { at: 4, end: 7, x: 600, y: 160, zoom: 1.6 },
  proof: { at: 9, text: "It's really in Reminders." },
  captions: [
    { at: 1.2, end: 3.8, text: "« Remind me to call mom tomorrow at 10 »" },
    { at: 4, end: 7, text: "He shows exactly what he'll add. I click." },
  ],
  endLine: "The little AI in your notch that asks before it acts.",
  endCta: "Yumi · free and open source · link in bio",
};

export const demoMetadata: CalculateMetadataFunction<DemoProps> = ({ props }) => ({
  durationInFrames: Math.round((props.clipLength + END) * 60),
});

const SCRIPT: YumiScript = { seed: 7, breath: 0, cues: [{ at: 0, mood: "happy", pose: "boing" }, { at: 1.1, mood: "wink" }, { at: 1.5, mood: "happy" }] };

const W = 1080;
const H = 1920;

const Take: React.FC<DemoProps & { readonly t: number }> = (p) => {
  const { fps } = useVideoConfig();
  const unit = W / p.crop.width;
  const height = p.crop.height * unit;
  const zoom =
    interpolate(p.t, [p.highlight.at - 0.4, p.highlight.at + 0.3], [1, p.highlight.zoom], { ...CLAMP, easing: EASE.camera }) *
    interpolate(p.t, [p.highlight.end - 0.2, p.highlight.end + 0.5], [1, 1 / p.highlight.zoom], { ...CLAMP, easing: EASE.camera });
  return (
    <div style={{ position: "absolute", left: 0, top: (H - height) / 2, width: W, height, overflow: "hidden", background: "#0b0b10" }}>
      <div style={{ position: "absolute", inset: 0, transformOrigin: `${p.highlight.x * unit}px ${p.highlight.y * unit}px`, scale: zoom }}>
        {p.clip ? (
          <Video
            src={staticFile(p.clip)}
            muted
            trimBefore={Math.round(p.clipStart * fps)}
            style={{ position: "absolute", left: -p.crop.x * unit, top: -p.crop.y * unit, width: p.source.width * unit, height: p.source.height * unit }}
          />
        ) : (
          <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", color: THEME.muted, fontFamily: THEME.text, fontSize: 40, textAlign: "center", padding: 80 }}>
            Put a real screen recording in motion/public/demo/ and set « clip ».
          </AbsoluteFill>
        )}
      </div>
    </div>
  );
};

export const Demo: React.FC<DemoProps> = (p) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  const ending = t >= p.clipLength;
  const hookSize = interpolate(t, [1.1, 1.6], [92, 52], { ...CLAMP, easing: EASE.camera });
  const proof = interpolate(t, [p.proof.at, p.proof.at + 0.35], [0, 1], { ...CLAMP, easing: EASE.spring });

  if (ending) {
    const e = t - p.clipLength;
    return (
      <AbsoluteFill style={{ backgroundColor: THEME.black }}>
        <Yumi script={SCRIPT} size={520} style={{ position: "absolute", left: (W - 520) / 2, top: 520 }} />
        <AbsoluteFill style={{ top: 1110 }}>
          <Words lines={[p.endLine]} enter={0.1} size={64} style={{ padding: "0 90px" }} />
        </AbsoluteFill>
        <div style={{ position: "absolute", top: 1420, left: 0, right: 0, textAlign: "center", fontFamily: THEME.text, fontSize: 38, color: THEME.muted, opacity: interpolate(e, [0.5, 0.9], [0, 1], CLAMP) }}>
          {p.endCta}
        </div>
      </AbsoluteFill>
    );
  }

  const caption = p.captions.find((c) => t >= c.at && t <= c.end);
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <Take {...p} t={t} />
      <div
        style={{
          position: "absolute",
          top: interpolate(t, [1.1, 1.6], [700, 190], { ...CLAMP, easing: EASE.camera }),
          left: 70,
          right: 70,
          textAlign: "center",
          fontFamily: THEME.text,
          fontWeight: 700,
          fontSize: hookSize,
          lineHeight: 1.1,
          letterSpacing: "-0.02em",
          color: THEME.fg,
          textShadow: "0 4px 30px rgba(0,0,0,0.9)",
        }}
      >
        {p.hook}
      </div>
      {caption ? (
        <div style={{ position: "absolute", bottom: 360, left: 80, right: 80, textAlign: "center", fontFamily: THEME.text, fontWeight: 600, fontSize: 46, lineHeight: 1.25, color: THEME.fg, textShadow: "0 2px 18px rgba(0,0,0,0.95)" }}>
          {caption.text}
        </div>
      ) : null}
      <div
        style={{
          position: "absolute",
          bottom: 220,
          left: 0,
          right: 0,
          display: "flex",
          justifyContent: "center",
          opacity: proof,
          scale: 0.85 + 0.15 * proof,
        }}
      >
        <div style={{ padding: "22px 38px", borderRadius: 999, background: "#1f9d55", color: "#fff", fontFamily: THEME.text, fontWeight: 700, fontSize: 44 }}>
          ✓ {p.proof.text}
        </div>
      </div>
    </AbsoluteFill>
  );
};
