import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, Sequence, interpolate, staticFile, useVideoConfig } from "remotion";
import { EASE } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { CLAMP, Kicker, Legende, P, Pied, Titre, ease, useMise, useT } from "./page";

// What is new in alpha 5, in 13 seconds, on the recap's magazine page. No take of these
// features exists yet, so the three beats are type only: nothing is drawn as if filmed.

export const ALPHA5_LENGTH = 13;
const B1 = 2.6;
const B2 = 5.0;
const B3 = 7.4;
const END = 9.8;

type Langue = "fr" | "en";
const T = {
  fr: {
    kicker: "Yumi · alpha 5",
    hook: ["Ce que fait", "Claude,", "en direct."],
    beats: [
      { lines: ["3/7"], sub: "La tâche de chaque session Claude Code, et son action en direct.", legende: "Chaque session montre sa tâche et ce qu'elle fait, en direct." },
      { lines: ["Tous tes", "dépôts."], sub: "GitHub : chaque push avec ses commits exacts.", legende: "GitHub suit tous tes dépôts, commit par commit." },
      { lines: ["Notion."], sub: "Tes tâches du jour et en retard, dans la notch.", legende: "Et Notion arrive dans la notch." },
    ],
    fin: ["Yumi alpha 5.", "Gratuit."],
    pied: "Nouveautés de l'alpha 5",
  },
  en: {
    kicker: "Yumi · alpha 5",
    hook: ["What Claude", "is doing,", "live."],
    beats: [
      { lines: ["3/7"], sub: "Each Claude Code session's task, and what it is doing right now.", legende: "Every session shows its task and what it's doing, live." },
      { lines: ["All your", "repos."], sub: "GitHub: every push with its exact commits.", legende: "GitHub follows all your repos, commit by commit." },
      { lines: ["Notion."], sub: "Today's and overdue tasks, in the notch.", legende: "And Notion comes to the notch." },
    ],
    fin: ["Yumi alpha 5.", "Free."],
    pied: "New in alpha 5",
  },
} as const;

const FIN: YumiScript = {
  seed: 505,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.2, mood: "wink", rim: "calm" },
    { at: 1.8, mood: "happy" },
  ],
};

const Film: React.FC<{ readonly langue: Langue }> = ({ langue }) => {
  const tx = T[langue];
  const m = useMise();
  const t = useT();
  const { fps } = useVideoConfig();
  const starts = [B1, B2, B3, END];
  // The Notion beat is set on the matcha page
  const up = ease(t, B3 - 0.2, B3 + 0.3);
  const off = ease(t, END - 0.35, END + 0.1);
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <div style={{ position: "absolute", inset: 0, backgroundColor: P.matcha, clipPath: `inset(${(1 - up) * 100}% 0 ${off * 100}% 0)` }} />
      <Kicker at={0.1} end={END - 0.4}>{tx.kicker}</Kicker>
      <Titre at={0.15} end={B1 - 0.3} lines={tx.hook} size={m.tall ? 128 : 116} />
      <Legende at={0.3} end={B1 - 0.1}>{tx.hook.join(" ")}</Legende>
      {tx.beats.map((b, i) => (
        <React.Fragment key={b.legende}>
          <Titre at={starts[i]} end={starts[i + 1] - 0.3} lines={b.lines} sub={b.sub} size={i === 0 ? 300 : m.tall ? 128 : 116} />
          <Legende at={starts[i] + 0.1} end={starts[i + 1] - 0.05}>{b.legende}</Legende>
        </React.Fragment>
      ))}
      {/* Him, crossing the page in small hops behind the type */}
      <Balade from={0.2} to={END - 0.1} y={m.tall ? 880 : 700} size={300} />
      <Pied lines={[{ at: 0.6, end: END - 0.2, text: tx.pied }]} />
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <Yumi script={FIN} size={360} style={{ position: "absolute", right: m.tall ? 120 : 60, top: m.tall ? 300 : 120 }} />
        <div style={{ position: "absolute", left: m.margin - 8, top: m.tall ? 780 : 560 }}>
          <Words lines={tx.fin} enter={0.25} size={m.tall ? 120 : 110} style={{ textAlign: "left", fontWeight: 800, color: P.ink, lineHeight: 1.0 }} />
          <div
            style={{
              marginTop: 30,
              fontFamily: P.mono,
              fontSize: 36,
              color: P.soft,
              clipPath: `inset(0 ${(1 - interpolate(t - END, [0.9, 1.6], [0, 1], { ...CLAMP, easing: EASE.out })) * 100}% 0 0)`,
            }}
          >
            github.com/estebanbaigts/Yumi
          </div>
        </div>
      </Sequence>
      <Audio
        src={staticFile("musique/lofi-recap.wav")}
        trimBefore={Math.round(4 * fps)}
        volume={(f) => 0.45 * interpolate(f / fps, [0, 0.6, ALPHA5_LENGTH - 1.5, ALPHA5_LENGTH], [0, 1, 1, 0], CLAMP)}
      />
    </AbsoluteFill>
  );
};

/**
 * Yumi has no legs: he walks in hops. He comes in from the left, crosses the frame and leaves
 * on the right, squashing a little at every landing, his eyes on where he is going.
 */
export const Balade: React.FC<{ readonly from: number; readonly to: number; readonly y: number; readonly size: number; readonly hop?: number }> = ({ from, to, y, size, hop = 0.55 }) => {
  const t = useT();
  const { width } = useVideoConfig();
  const s = Math.max(0, t - from);
  const x = interpolate(t, [from, to], [-size * 1.1, width + size * 0.1], CLAMP);
  const phase = (s % hop) / hop;
  const lift = Math.sin(Math.PI * phase) * size * 0.16;
  const script: YumiScript = {
    seed: 507,
    cues: [
      { at: 0, mood: "happy", rim: "joy", gaze: [1, 0] },
    ],
  };
  return (
    <Sequence from={Math.round(from * 60)} durationInFrames={Math.round((to - from) * 60)} layout="none">
      <div style={{ position: "absolute", left: x, top: y - lift }}>
        <Yumi script={script} size={size} />
      </div>
      {/* His shadow stays on the ground and shrinks while he is up */}
      <div
        style={{
          position: "absolute",
          left: x + size * 0.2,
          top: y + size * 0.8,
          width: size * 0.6,
          height: size * 0.07,
          borderRadius: "50%",
          backgroundColor: "rgba(12,12,16,0.18)",
          scale: 1 - (lift / (size * 0.16)) * 0.35,
        }}
      />
    </Sequence>
  );
};

export const Alpha5Fr: React.FC = () => <Film langue="fr" />;
export const Alpha5En: React.FC = () => <Film langue="en" />;
