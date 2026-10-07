import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, interpolate, staticFile, useVideoConfig } from "remotion";
import { THEME, EASE } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import type { Habit } from "../yumi/blob";
import { bodyPath, bodyPoints } from "../yumi/shape";
import { CLAMP, P, Plan, ease, useT } from "./page";

// An English carousel, one 6-second slide per chapter, 4:5, on Yumi's magazine page: a cover,
// then how he is drawn, his faces, his habits, the island, Claude live, what is new. The
// island slides are real takes of the app (in French, with example data).

export const SLIDE_LENGTH = 6;

/** The page of a slide: the visual on top, the title, the chapter number set large. */
const Page: React.FC<{ readonly n?: string; readonly title: string; readonly sub?: string; readonly children: React.ReactNode }> = ({ n, title, sub, children }) => {
  const t = useT();
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <div style={{ position: "absolute", left: 0, right: 0, top: 0, height: 860 }}>{children}</div>
      <div style={{ position: "absolute", left: 70, top: 900 }}>
        <Words lines={[title]} enter={0.2} size={92} style={{ textAlign: "left", fontWeight: 800, color: P.ink, whiteSpace: "nowrap" }} />
        {sub ? (
          <div style={{ marginTop: 14, fontFamily: THEME.text, fontSize: 36, fontWeight: 600, color: P.soft, opacity: ease(t, 0.6, 1.1) }}>{sub}</div>
        ) : null}
      </div>
      {n ? (
        <div
          style={{
            position: "absolute",
            right: 60,
            bottom: 30,
            fontFamily: THEME.text,
            fontSize: 230,
            fontWeight: 800,
            letterSpacing: "-0.05em",
            lineHeight: 1,
            background: P.light,
            WebkitBackgroundClip: "text",
            color: "transparent",
            clipPath: `inset(${(1 - ease(t, 0.35, 1.0, EASE.out)) * 100}% 0 0 0)`,
          }}
        >
          {n}
        </div>
      ) : null}
      <Audio src={staticFile("musique/lofi-recap.wav")} trimBefore={Math.round(4 * 60)} volume={(f) => 0.4 * interpolate(f / 60, [0, 0.4, SLIDE_LENGTH - 0.6, SLIDE_LENGTH], [0, 1, 1, 0], CLAMP)} />
    </AbsoluteFill>
  );
};

const Center: React.FC<{ readonly size: number; readonly script: YumiScript; readonly y?: number }> = ({ size, script, y = 430 }) => {
  const { width } = useVideoConfig();
  return <Yumi script={script} size={size} style={{ position: "absolute", left: (width - size) / 2, top: y - size * 0.42 }} />;
};

export const SlideCover: React.FC = () => {
  const t = useT();
  return (
    <Page title="Yumi" sub="A companion in your Mac's notch, drawn in code.">
      <div style={{ position: "absolute", left: (1080 - 300) / 2, top: 0, width: 300, height: 70, backgroundColor: "#000", borderRadius: "0 0 36px 36px" }} />
      <Center
        size={460}
        y={interpolate(t, [0.2, 0.9], [120, 470], { ...CLAMP, easing: EASE.spring })}
        script={{ seed: 601, cues: [{ at: 0, lit: false, mood: "asleep" }, { at: 0.4, mood: "surprised", pose: "pop" }, { at: 1.0, lit: true, mood: "happy", rim: "joy", pose: "wave" }] }}
      />
    </Page>
  );
};

export const SlideDrawn: React.FC = () => {
  const t = useT();
  const s = 7.2;
  const { anchors, controls } = bodyPoints(1, 1, 0);
  const draw = ease(t, 0.2, 2.0);
  const fill = ease(t, 2.4, 3.2);
  return (
    <Page n="01" title="Drawn in code" sub="Four Bézier curves and a soft body.">
      <svg width={1080} height={860} viewBox={`${50 - 540 / s} ${44 - 430 / s} ${1080 / s} ${860 / s}`} style={{ position: "absolute", inset: 0 }}>
        <path d={bodyPath(1, 1, 0)} fill="none" stroke={P.ink} strokeWidth={0.5} pathLength={1} strokeDasharray="1 1" strokeDashoffset={1 - draw} />
        {controls.map(([a, b], i) => (
          <g key={i} opacity={ease(t, 0.6 + i * 0.25, 1.0 + i * 0.25) * (1 - fill)}>
            <line x1={anchors[i][0]} y1={anchors[i][1]} x2={a[0]} y2={a[1]} stroke="#8B6CFF" strokeWidth={0.25} />
            <line x1={anchors[(i + 1) % 4][0]} y1={anchors[(i + 1) % 4][1]} x2={b[0]} y2={b[1]} stroke="#8B6CFF" strokeWidth={0.25} />
            <circle cx={a[0]} cy={a[1]} r={0.9} fill="#F58AD9" />
            <circle cx={b[0]} cy={b[1]} r={0.9} fill="#F58AD9" />
          </g>
        ))}
        {anchors.map(([x, y], i) => (
          <rect key={i} x={x - 1.1} y={y - 1.1} width={2.2} height={2.2} fill={P.ink} opacity={1 - fill} />
        ))}
      </svg>
      <div style={{ opacity: fill }}>
        <Center size={720} y={430} script={{ seed: 602, cues: [{ at: 0, mood: "happy", rim: "calm" }, { at: 3.6, pose: "boing" }] }} />
      </div>
    </Page>
  );
};

const MOODS = ["neutral", "happy", "curious", "focused", "thinking", "surprised", "worried", "annoyed", "wink", "asleep"] as const;

export const SlideFaces: React.FC = () => (
  <Page n="02" title="Expressions" sub="Every mood is a few numbers on his eyes.">
    {MOODS.map((mood, i) => {
      const col = i % 4;
      const row = Math.floor(i / 4);
      return (
        <div key={mood} style={{ position: "absolute", left: 60 + col * 245, top: 90 + Math.floor(i / 4) * 0 + row * 260 }}>
          <Yumi size={200} script={{ seed: 610 + i, cues: [{ at: 0, mood, rim: "calm" }] }} />
          <div style={{ textAlign: "center", width: 200, marginTop: -6, fontFamily: P.mono, fontSize: 22, color: P.soft }}>{mood}</div>
        </div>
      );
    })}
  </Page>
);

const HABITS: readonly Habit[] = ["coffee", "matcha", "headphones", "sunglasses", "cloud", "sleep"];

export const SlideHabits: React.FC = () => (
  <Page n="03" title="Habits" sub="What he does while you work.">
    {HABITS.map((habit, i) => {
      const col = i % 3;
      const row = Math.floor(i / 3);
      return (
        <div key={habit} style={{ position: "absolute", left: 50 + col * 330, top: 110 + row * 360 }}>
          <Yumi size={300} script={{ seed: 620 + i, lead: 2 + i, cues: [{ at: 0, habit }] }} />
          <div style={{ textAlign: "center", width: 300, marginTop: -10, fontFamily: P.mono, fontSize: 24, color: P.soft }}>{habit}</div>
        </div>
      );
    })}
  </Page>
);

/** A real take, on the page, centred in the visual area. */
const Prise: React.FC<{ readonly take: "apercu" | "a5-claude"; readonly crop: { x: number; y: number; w: number; h: number }; readonly source: number }> = ({ take, crop, source }) => (
  <div style={{ position: "absolute", inset: 0, translate: "0 -320px" }}>
    <Plan take={take} source={source} crop={crop} from={0.2} to={SLIDE_LENGTH + 1} />
  </div>
);

export const SlideIsland: React.FC = () => (
  <Page n="04" title="The island" sub="Real take: your modules, under the notch.">
    <Prise take="apercu" source={2.4} crop={{ x: 140, y: 0, w: 1400, h: 467 }} />
  </Page>
);

export const SlideLive: React.FC = () => (
  <Page n="05" title="Claude, live" sub="Real take: the task, its progress, the action.">
    <Prise take="a5-claude" source={0} crop={{ x: 0, y: 0, w: 1320, h: 540 }} />
  </Page>
);

export const SlideNew: React.FC = () => {
  const t = useT();
  const items = ["Claude Code sessions, live", "All your GitHub repos, exact commits", "Notion tasks in the notch", "Free and open source"];
  return (
    <Page n="06" title="What's new" sub="Yumi alpha 5 · github.com/estebanbaigts/Yumi">
      <Center size={300} y={220} script={{ seed: 630, cues: [{ at: 0, mood: "happy", rim: "joy", pose: "celebrate" }] }} />
      {items.map((it, i) => (
        <div
          key={it}
          style={{
            position: "absolute",
            left: 120,
            top: 470 + i * 84,
            fontFamily: THEME.text,
            fontSize: 44,
            fontWeight: 700,
            color: P.ink,
            opacity: ease(t, 0.6 + i * 0.25, 1.0 + i * 0.25),
            translate: `${(1 - ease(t, 0.6 + i * 0.25, 1.1 + i * 0.25, EASE.out)) * 30}px 0`,
          }}
        >
          <span style={{ display: "inline-block", width: 18, height: 18, borderRadius: 9, background: P.light, marginRight: 24, verticalAlign: "middle" }} />
          {it}
        </div>
      ))}
    </Page>
  );
};
