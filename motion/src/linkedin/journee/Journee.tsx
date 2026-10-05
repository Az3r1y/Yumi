import { Video } from "@remotion/media";
import React from "react";
import { AbsoluteFill, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Son } from "../../son/Son";
import { EASE, THEME } from "../../theme";
import { Words } from "../../type/Words";
import { Yumi } from "../../yumi/Yumi";
import type { YumiScript } from "../../yumi/engine";

// LinkedIn, after the alpha: a developer's day with Yumi, in 24 seconds, told only by what is
// new and was never shown. One question about tomorrow's free time, the matcha while an agent
// works, and three Claude Code sessions, one of which waits for an answer given from the notch.
//
// Every image of the island is a real take: the app filmed on the built-in screen of the Mac
// in its filming mode (YUMI_STUDIO, shots 10 to 12 of Island/IslandStudio.swift), with its
// example data. The takes are cropped around the notch, never redrawn. The film is written for
// 4:5 (the feed) and 9:16.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = (t: number, a: number, b: number, e = EASE.camera) => interpolate(t, [a, b], [0, 1], { ...CLAMP, easing: e });

const C = { fg: "#F4F5F8", muted: "#8D92A8", faint: "#5A5F74" };

// The three takes, their size in pixels of the recording, and where they sit in the film
const TAKE = { w: 1380, h: 500 };
const MATCHA = 6.4;
const SESSIONS = 11.2;
const END = 21.0;
export const JOURNEE_LENGTH = 24.4;
// Moments inside the takes, in film time
const ANSWER = 2.1; // the answer arrives
const REQUEST = 13.2; // the api session asks
const YES = 15.8; // the green button is pressed

/** The frame: 4:5 or 9:16, and where things go in it. */
const useCadre = () => {
  const { width, height } = useVideoConfig();
  const tall = height / width > 1.5;
  const w = width - 40;
  return { W: width, H: height, tall, box: { x: 20, y: tall ? 680 : 380, w, h: Math.round((w * TAKE.h) / TAKE.w) }, captionY: tall ? 1180 : 880 };
};

const useT = () => {
  const { fps } = useVideoConfig();
  return useCurrentFrame() / fps;
};

/** One subtitle at a time, burned in. */
const SousTitre: React.FC<{ readonly at: number; readonly end: number; readonly children: string }> = ({ at, end, children }) => {
  const t = useT();
  const c = useCadre();
  if (t < at - 0.05 || t > end + 0.05) return null;
  const k = ease(t, at, at + 0.35, EASE.out) * (1 - ease(t, end - 0.25, end, EASE.in));
  return (
    <div
      style={{
        position: "absolute",
        left: 70,
        right: 70,
        top: c.captionY,
        textAlign: "center",
        fontFamily: THEME.text,
        fontSize: 54,
        fontWeight: 700,
        lineHeight: 1.18,
        letterSpacing: "-0.02em",
        color: C.fg,
        opacity: k,
        translate: `0 ${(1 - k) * 16}px`,
        textWrap: "balance",
      }}
    >
      {children}
    </div>
  );
};

/** A real take, cut from the recording, as wide as the frame's box. `zoom` goes towards `focus`,
 * given as fractions of the box width. */
const Prise: React.FC<{
  readonly take: string;
  readonly from: number;
  readonly to: number;
  /** Height over width of the take. */
  readonly ratio?: number;
  readonly zoom?: (t: number) => number;
  readonly focus?: readonly [number, number];
}> = ({ take, from, to, ratio = TAKE.h / TAKE.w, zoom, focus = [0.5, 0] }) => {
  const t = useT();
  const { fps } = useVideoConfig();
  const c = useCadre();
  const opacity = ease(t, from, from + 0.25) * (1 - ease(t, to - 0.25, to));
  return (
    <Sequence from={Math.round(from * fps)} durationInFrames={Math.round((to - from) * fps)} layout="none">
      <div
        style={{
          position: "absolute",
          left: c.box.x,
          top: c.box.y,
          width: c.box.w,
          height: c.box.h,
          overflow: "hidden",
          borderRadius: 26,
          backgroundColor: "#000",
          boxShadow: "0 0 0 1.5px rgba(255,255,255,0.09), 0 40px 120px rgba(0,0,0,0.55)",
          opacity,
        }}
      >
        <Video
          src={staticFile(`prises/${take}.mp4`)}
          muted
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: c.box.w,
            height: c.box.w * ratio,
            transformOrigin: `${focus[0] * c.box.w}px ${focus[1] * c.box.w}px`,
            scale: zoom ? zoom(t - from) : 1,
          }}
        />
      </div>
    </Sequence>
  );
};

const FIN: YumiScript = {
  seed: 404,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.3, mood: "wink", rim: "calm" },
    { at: 1.9, mood: "happy" },
  ],
};

export const Journee: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {/* What the images are, said once, quietly */}
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: c.box.y - 64,
          textAlign: "center",
          fontFamily: THEME.text,
          fontSize: 28,
          fontWeight: 600,
          letterSpacing: "0.04em",
          color: C.faint,
          opacity: ease(t, 0.3, 0.8) * (1 - ease(t, END - 0.4, END)),
        }}
      >
        Filmé sur mon Mac · mode tournage, données d'exemple
      </div>

      {/* 1. The question, and his answer */}
      <Prise take="journee-temps-libre" from={0} to={MATCHA} />
      {/* 2. Folded while an agent works: the matcha. The take is wider than the notch, the
          camera goes in on him */}
      <Prise
        take="journee-matcha"
        ratio={300 / 900}
        from={MATCHA}
        to={SESSIONS}
        focus={[0.47, 0.04]}
        zoom={(s) => interpolate(s, [0, 1.2], [1, 2.6], { ...CLAMP, easing: EASE.camera })}
      />
      {/* 3. Three sessions; one asks, the answer is given from the notch */}
      <Prise take="journee-sessions" from={SESSIONS} to={END} />

      {/* The end */}
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <Yumi script={FIN} size={c.tall ? 560 : 500} style={{ position: "absolute", left: (c.W - (c.tall ? 560 : 500)) / 2, top: c.tall ? 470 : 200 }} />
        <AbsoluteFill style={{ top: c.tall ? 1010 : 730 }}>
          <Words lines={["Yumi."]} by="letter" enter={0.25} size={150} style={{ fontWeight: 700 }} />
          <Words lines={["Alpha gratuite.", "Lien en commentaire."]} enter={0.75} size={60} style={{ color: C.muted, marginTop: 18, lineHeight: 1.2 }} />
        </AbsoluteFill>
      </Sequence>

      <SousTitre at={-1} end={ANSWER}>Je lui demande mon temps libre de demain.</SousTitre>
      <SousTitre at={ANSWER + 0.1} end={MATCHA - 0.1}>Il regarde mon agenda et me répond.</SousTitre>
      <SousTitre at={MATCHA + 0.2} end={SESSIONS - 0.1}>Pendant que l'agent code, il boit son matcha.</SousTitre>
      <SousTitre at={SESSIONS + 0.2} end={YES - 0.2}>Trois sessions. Une attend mon accord.</SousTitre>
      <SousTitre at={YES - 0.1} end={END - 0.2}>Je réponds depuis la notch, sans changer de fenêtre.</SousTitre>

      <Son name="send" at={0.15} volume={0.45} />
      <Son name="tick" at={ANSWER} volume={0.3} />
      <Son name="pop" at={MATCHA} volume={0.4} />
      <Son name="approval" at={REQUEST} volume={0.6} />
      <Son name="approve" at={YES} volume={0.7} />
      <Son name="finish" at={YES + 0.3} volume={0.5} />
      <Son name="wink" at={END + 1.3} volume={0.6} />
    </AbsoluteFill>
  );
};
