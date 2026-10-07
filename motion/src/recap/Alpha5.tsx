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

// One Yumi through the three beats, large and still in the frame, Apple-keynote clean: only
// his face and his light change with each feature
const SUIT: YumiScript = {
  seed: 506,
  cues: [
    { at: 0, lit: false, mood: "asleep" },
    { at: 0.3, mood: "surprised", pose: "pop" },
    { at: 0.7, lit: true, mood: "curious", rim: "calm" },
    { at: B1, mood: "thinking", rim: "work" },
    { at: B1 + 1.2, gaze: [1, -0.4] },
    { at: B2, gaze: null, mood: "happy", rim: "done", pose: "celebrate" },
    { at: B3, mood: "happy", rim: "joy", pose: "wave" },
  ],
};

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
      {/* Him, centred under the type, through the hook and the three beats */}
      <div
        style={{
          position: "absolute",
          left: (m.W - 400) / 2,
          top: m.tall ? 760 : 620,
          opacity: ease(t, 0.1, 0.5) * (1 - ease(t, END - 0.45, END - 0.1, EASE.in)),
          scale: interpolate(t, [0, 0.8], [0.92, 1], { ...CLAMP, easing: EASE.camera }),
        }}
      >
        <Yumi script={SUIT} size={400} />
      </div>
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

export const Alpha5Fr: React.FC = () => <Film langue="fr" />;
export const Alpha5En: React.FC = () => <Film langue="en" />;
