import React from "react";
import { Audio } from "@remotion/media";
import { AbsoluteFill, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Bord, PERMISSION, Take, arrivee } from "../scenes/Fonctions";
import { Pov } from "../scenes/Pov";
import { CLOSE, EYES, SIZE, YUMI_AT } from "../scenes/stage";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";

// The five stories of design/yumi/video.md. Each one is a short film of its own, in the
// same frame as the reel. Instagram covers the top 250 pixels (the account) and the bottom
// 340 (the reply field): nothing that matters sits there.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** The music of the reel under a story. `from` 0 is the dark, 2 the moment it opens. */
const Musique: React.FC<{ readonly from: number }> = ({ from }) => {
  const { fps } = useVideoConfig();
  return <Audio src={staticFile("musique/ambiance.wav")} trimBefore={Math.round(from * fps)} volume={0.45} />;
};

// 1. The eyes in the dark. « Devine qui arrive. »

const YEUX: YumiScript = {
  seed: 31,
  cues: [
    { at: 0, lit: false, mood: "asleep" },
    { at: 0.5, mood: "surprised", pose: "pop" },
    { at: 0.95, gaze: [-1, 0] },
    { at: 1.3, gaze: [1, 0] },
    { at: 1.75, mood: "curious" },
    { at: 2.7, blink: true },
    // Still unlit: the smile is only in the eyes
    { at: 3.3, mood: "happy" },
  ],
};

export const StoryYeux: React.FC = () => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <AbsoluteFill
        style={{
          transformOrigin: `${EYES.x}px ${EYES.y}px`,
          scale: interpolate(t, [0, 4.5], [CLOSE, 1.52], CLAMP),
        }}
      >
        <Yumi script={YEUX} size={SIZE} style={YUMI_AT} />
      </AbsoluteFill>
      <AbsoluteFill style={{ top: 1250 }}>
        <Words lines={["Devine", "qui arrive."]} enter={1.9} size={124} />
      </AbsoluteFill>
      <Musique from={0} />
      <Son name="pop" at={0.5} />
      <Son name="blip" at={0.95} volume={0.5} />
      <Son name="blip" at={1.3} volume={0.5} />
    </AbsoluteFill>
  );
};

// 2. The whole launch, on the real screen, without a word.

export const StoryLancement: React.FC = () => (
  <AbsoluteFill>
    <Pov lines={[]} />
    <Musique from={0} />
  </AbsoluteFill>
);

// 3. One thing he does, close up: a permission granted in one click.

export const StoryPermission: React.FC = () => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black, perspective: 1800 }}>
      <AbsoluteFill style={arrivee(t)}>
        <Take {...PERMISSION} />
        <Bord />
      </AbsoluteFill>
      <Musique from={2} />
      <Son name="approval" at={0.2} />
      <Son name="approve" at={2.6} />
      <Son name="finish" at={2.9} />
    </AbsoluteFill>
  );
};

// 4. His moods, all four at once, for a poll: « Laquelle te ressemble le lundi ? »
//    The poll itself is a sticker added in Instagram; the space under the grid (from 1270 to
//    1580) is left for it.

const MOODS: readonly { readonly label: string; readonly script: YumiScript; readonly x: number; readonly y: number }[] = [
  { label: "Café", x: 290, y: 545, script: { seed: 41, lead: 3.2, cues: [{ at: 0, habit: "coffee" }] } },
  { label: "Nuage", x: 790, y: 545, script: { seed: 42, cues: [{ at: 0.6, habit: "cloud", pose: "pop" }] } },
  { label: "Lunettes", x: 290, y: 900, script: { seed: 43, cues: [{ at: 0.95, habit: "sunglasses", pose: "pop" }] } },
  { label: "Dodo", x: 790, y: 900, script: { seed: 44, cues: [{ at: 1.3, habit: "sleep" }] } },
];

const CELL = 320;

export const StoryHumeurs: React.FC = () => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <AbsoluteFill style={{ top: 285 }}>
        <Words lines={["Laquelle te ressemble", "le lundi ?"]} enter={0.15} size={88} />
      </AbsoluteFill>
      {MOODS.map((mood, i) => (
        <div
          key={mood.label}
          style={{
            position: "absolute",
            left: mood.x - CELL / 2,
            top: mood.y,
            width: CELL,
            transformOrigin: `${CELL / 2}px ${CELL * 0.76}px`,
            opacity: interpolate(t, [0.1 + i * 0.12, 0.3 + i * 0.12], [0, 1], CLAMP),
            scale: interpolate(t, [0.1 + i * 0.12, 0.65 + i * 0.12], [0.7, 1], { ...CLAMP, easing: EASE.spring }),
          }}
        >
          <Yumi script={mood.script} size={CELL} />
          <div
            style={{
              marginTop: 18,
              textAlign: "center",
              fontFamily: THEME.text,
              fontSize: 46,
              fontWeight: 600,
              letterSpacing: "-0.02em",
              color: THEME.muted,
            }}
          >
            {mood.label}
          </div>
        </div>
      ))}
      <Musique from={2} />
      <Son name="rate" at={0.65} volume={0.5} />
      <Son name="wink" at={1.05} />
      <Son name="pop" at={1.2} />
      <Son name="sleep" at={1.4} volume={0.7} />
    </AbsoluteFill>
  );
};

// 5. He waves. « Sortie bientôt. Active les notifications. »

const SALUT: YumiScript = {
  seed: 51,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 0.5, pose: "wave" },
    { at: 2.4, mood: "wink", rim: "calm" },
    { at: 3.0, mood: "happy" },
  ],
};

export const StorySalut: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Yumi script={SALUT} size={SIZE} style={YUMI_AT} />
    <AbsoluteFill style={{ top: 1230 }}>
      <Words lines={["Sortie bientôt."]} enter={0.7} size={128} />
      <Words
        lines={["Active les notifications."]}
        enter={1.3}
        size={56}
        style={{ fontWeight: 500, color: THEME.muted, marginTop: 26 }}
      />
    </AbsoluteFill>
    <Musique from={2} />
    <Son name="greet" at={0.5} />
    <Son name="wink" at={2.4} />
  </AbsoluteFill>
);
