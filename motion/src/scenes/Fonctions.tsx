import React from "react";
import { Video } from "@remotion/media";
import { AbsoluteFill, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";

// What he does today (design/yumi/video.md, 5 to 18 s), filmed on the real screen with the
// filming mode of the app (`YUMI_STUDIO=1`), at its normal size.
//
// One window onto the top of the Mac's screen stays in place for the whole scene; the island
// hangs from its upper edge as it hangs from the notch. Four takes follow one another inside
// it, and each has one camera move that points at what matters: the button being pressed,
// Yumi keeping the beat, the answer writing itself, the few words he says on his own.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** The takes: the top of the screen around the notch, 840 × 520 points filmed at 2 pixels a point. */
const TAKE = { width: 840, height: 520 };
/** The window onto the screen, in the 1080 × 1920 frame. */
const WINDOW = { left: 40, top: 330, width: 1000, height: 700 };
/** Pixels of the film for one point of the screen: the open island (660 points) fits the window. */
const UNIT = 1.42;

/** A take seen through the window, with the camera closed in on `focus` by `scale`. */
export const Ecran: React.FC<{
  /** The footage, in public/prises. */
  readonly take: string;
  /** Where it starts in the footage, in seconds, and how fast it plays. */
  readonly source: number;
  readonly rate?: number;
  /** A point of the window, in its own pixels. */
  readonly focus: readonly [number, number];
  readonly scale: number;
  /** How the take sits in the window (a soft arrival, for instance). */
  readonly style?: React.CSSProperties;
  /** Drawn over the take, in the window. */
  readonly children?: React.ReactNode;
}> = ({ take, source, rate = 1, focus, scale, style, children }) => {
  const { fps } = useVideoConfig();
  return (
    <div style={{ position: "absolute", ...WINDOW, overflow: "hidden", borderRadius: 44 }}>
      <AbsoluteFill style={style}>
        <Video
          src={staticFile(`prises/${take}.mp4`)}
          muted
          trimBefore={Math.round(source * fps)}
          playbackRate={rate}
          style={{
            position: "absolute",
            left: (WINDOW.width - TAKE.width * UNIT) / 2,
            top: 0,
            width: TAKE.width * UNIT,
            height: TAKE.height * UNIT,
            transformOrigin: `${focus[0] - (WINDOW.width - TAKE.width * UNIT) / 2}px ${focus[1]}px`,
            scale,
          }}
        />
      </AbsoluteFill>
      {children}
    </div>
  );
};

/** The edge of the screen, drawn over the takes. */
export const Bord: React.FC = () => (
  <div
    style={{
      position: "absolute",
      ...WINDOW,
      borderRadius: 44,
      boxShadow: "inset 0 0 0 1.5px rgba(255,255,255,0.09)",
    }}
  />
);

/** How the window arrives: it rises, tilted back like a screen being opened. `t` in seconds. */
export const arrivee = (t: number): React.CSSProperties => ({
  transformOrigin: "540px 1030px",
  opacity: interpolate(t, [0, 0.35], [0, 1], CLAMP),
  translate: `0 ${interpolate(t, [0, 0.8], [70, 0], { ...CLAMP, easing: EASE.out })}px`,
  rotate: `x ${interpolate(t, [0, 0.9], [14, 0], { ...CLAMP, easing: EASE.out })}deg`,
  scale: interpolate(t, [0, 0.8], [0.94, 1], { ...CLAMP, easing: EASE.out }),
});

/** When each take starts, and when the last one ends, in seconds. */
const CUTS = [0, 4.25, 7.75, 12.4, 15.9] as const;

export const FONCTIONS_LENGTH = CUTS[4];

const ramp = (t: number, from: number, to: number, easing = EASE.camera) =>
  interpolate(t, [from, to], [0, 1], { ...CLAMP, easing });

export type TakeProps = {
  /** Which of the four takes it is: it starts at `CUTS[index]` and stays until the next one. */
  readonly index: 0 | 1 | 2 | 3;
  /** Where it starts in the footage, in seconds, and how fast it plays. */
  readonly source: number;
  readonly rate?: number;
  /** The point of the window the camera closes in on, and its scale at `t` seconds into the take. */
  readonly focus: readonly [number, number];
  readonly zoom: (t: number) => number;
  /** A click the take shows without a pointer: a ring opens on `focus` at this time. */
  readonly click?: number;
  readonly lines: readonly string[];
};

export const Take: React.FC<TakeProps> = ({ index, source, rate = 1, focus, zoom, click, lines }) => {
  const { fps } = useVideoConfig();
  const at = CUTS[index];
  const length = CUTS[index + 1] - at;
  const t = useCurrentFrame() / fps - at;
  return (
    <Sequence from={Math.round(at * fps)} durationInFrames={Math.round(length * fps)} premountFor={fps}>
      <Ecran
        take="ile"
        source={source}
        rate={rate}
        focus={focus}
        scale={zoom(t)}
        // After the first, a take settles into the window instead of cutting in
        style={{
          opacity: index === 0 ? 1 : interpolate(t, [0, 0.25], [0, 1], CLAMP),
          scale: index === 0 ? 1 : interpolate(t, [0, 0.6], [1.035, 1], { ...CLAMP, easing: EASE.out }),
        }}
      >
        {click !== undefined ? (
          <div
            style={{
              position: "absolute",
              left: focus[0],
              top: focus[1],
              width: interpolate(t, [click, click + 0.55], [44, 190], { ...CLAMP, easing: EASE.out }),
              aspectRatio: "1",
              translate: "-50% -50%",
              borderRadius: "50%",
              border: "3px solid #3DDC97",
              opacity: interpolate(t, [click, click + 0.06, click + 0.55], [0, 0.9, 0], CLAMP),
            }}
          />
        ) : null}
      </Ecran>
      <AbsoluteFill style={{ top: 1170 }}>
        <Words lines={lines} enter={0.2} exit={length - 0.4} size={108} />
      </AbsoluteFill>
    </Sequence>
  );
};

/** A permission: the camera goes to the buttons for the click, then back to him celebrating. */
export const PERMISSION: TakeProps = {
  index: 0,
  source: 0.95,
  focus: [899, 118],
  zoom: (s) => 1 + 0.25 * ramp(s, 1.5, 2.3) - 0.25 * ramp(s, 2.95, 3.6),
  click: 2.58,
  lines: ["Il surveille", "tes agents."],
};

/** Four short lines under the window: which of the four things he does is on, and how far along. */
const Progress: React.FC<{ readonly t: number }> = ({ t }) => (
  <div style={{ position: "absolute", top: 1078, left: 0, right: 0, display: "flex", justifyContent: "center", gap: 12 }}>
    {[0, 1, 2, 3].map((i) => (
      <div
        key={i}
        style={{
          // The one that is on is longer
          width: interpolate(t, [CUTS[i] - 0.3, CUTS[i] + 0.2, CUTS[i + 1] - 0.3, CUTS[i + 1] + 0.2], [26, 84, 84, 26], { ...CLAMP, easing: EASE.camera }),
          height: 5,
          borderRadius: 3,
          backgroundColor: "rgba(255,255,255,0.16)",
          overflow: "hidden",
        }}
      >
        <div
          style={{
            width: `${interpolate(t, [CUTS[i], CUTS[i + 1]], [0, 100], CLAMP)}%`,
            height: "100%",
            borderRadius: 3,
            backgroundColor: THEME.fg,
          }}
        />
      </div>
    ))}
  </div>
);

export const Fonctions: React.FC<{
  /** false when the scene before already brought the window in. */
  readonly arrive?: boolean;
}> = ({ arrive = true }) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black, perspective: 1800 }}>
      {/* The window arrives once, tilted back like a screen being opened, and leaves once;
          the takes change inside it */}
      <AbsoluteFill
        style={{
          ...(arrive ? arrivee(t) : {}),
          opacity: (arrive ? interpolate(t, [0, 0.35], [0, 1], CLAMP) : 1) - interpolate(t, [FONCTIONS_LENGTH - 0.3, FONCTIONS_LENGTH], [0, 1], CLAMP),
        }}
      >
        <Take {...PERMISSION} />
        {/* Music: a slow push on Yumi and his headphones */}
        <Take
          index={1}
          source={10.85}
          focus={[110, 118]}
          zoom={(s) => 1 + 0.45 * ramp(s, 0.9, 2.6)}
          lines={["Il écoute", "avec toi."]}
        />
        {/* The chat, a little faster than life: the answer writes itself, the file appears */}
        <Take
          index={2}
          source={16.3}
          rate={1.75}
          focus={[500, 0]}
          zoom={(s) => 1 + 0.05 * ramp(s, 0, 4.65, EASE.out)}
          lines={["Tu lui parles,", "il agit."]}
        />
        {/* Folded, he speaks first: the camera comes close to read it */}
        <Take
          index={3}
          source={26.4}
          focus={[500, 14]}
          zoom={(s) => 1 + 1.0 * ramp(s, 0.35, 1.3)}
          lines={["Il pense", "à toi."]}
        />
        <Bord />
        <Progress t={t} />
      </AbsoluteFill>

      {/* The sounds the island makes at these moments, laid over the silent takes */}
      <Son name="approval" at={0.2} />
      <Son name="approve" at={2.6} />
      <Son name="finish" at={2.9} />
      <Son name="open" at={4.4} volume={0.6} />
      <Son name="send" at={7.95} />
      <Son name="attach" at={10.8} />
      <Son name="question" at={12.65} />
    </AbsoluteFill>
  );
};
