import React from "react";
import { AbsoluteFill, Sequence, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Son } from "../../son/Son";
import { EASE, THEME } from "../../theme";
import { Words } from "../../type/Words";
import { Yumi } from "../../yumi/Yumi";
import type { YumiScript } from "../../yumi/engine";

// LinkedIn, after the alpha: a developer's day with Yumi, in 22 seconds, told only by what is
// new and was never shown. One question about tomorrow's free time (get_today with
// free_time: its sentence is the one the tool writes), the matcha while an agent works, and
// three Claude Code sessions, one of which waits for an answer given from the notch.
//
// The filming mode of the app does not show these scenes yet, so the island is drawn here,
// large, after Island/IslandRows.swift and the approval view: same colours, same words, same
// layout, example data only. The film is written for 4:5 (the feed) and 9:16.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = (t: number, a: number, b: number, e = EASE.camera) => interpolate(t, [a, b], [0, 1], { ...CLAMP, easing: e });

const C = {
  island: "#000",
  bubble: "#23263A",
  fg: "#F4F5F8",
  muted: "#8D92A8",
  faint: "#5A5F74",
  blue: "#5B8CFF",
  amber: "#FFB547",
  green: "#3DDC97",
  red: "#FF5D6C",
};

// The beats, in seconds
const ANSWER = 1.5; // he answers
const MATCHA = 6.6;
const SESSIONS = 11.2;
const REQUEST = 12.3; // a session asks
const YES = 14.9; // the click on the green button
const END = 18.2;
export const JOURNEE_LENGTH = 22.6;

const QUESTION = "Combien de temps libre j'ai demain pour avancer sur Yumi ?";
// What GetTodayTool.reply writes for a day with two appointments (10:00 to 12:00, 17:00 to 20:00)
const REPONSE = [
  "Demain, deux rendez-vous, le premier c'est Point produit à 10:00.",
  "Du temps libre entre 8\u00a0h et 20\u00a0h : 7\u00a0h, le plus long créneau de 12\u00a0h\u00a0à\u00a017\u00a0h.",
];

/** The frame: 4:5 or 9:16, and where things go in it. */
const useCadre = () => {
  const { width, height } = useVideoConfig();
  const tall = height / width > 1.5;
  return {
    W: width,
    H: height,
    tall,
    /** The top of the screen: the island hangs from it. */
    screenTop: tall ? 330 : 150,
    captionY: tall ? 1080 : 820,
  };
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

/** Words that appear one after the other, as the chat writes them. */
const Ecrit: React.FC<{ readonly text: string; readonly at: number; readonly every?: number; readonly highlight?: readonly string[] }> = ({
  text,
  at,
  every = 0.075,
  highlight = [],
}) => {
  const t = useT();
  const words = text.split(" ");
  const shown = Math.max(0, Math.floor((t - at) / every));
  let joined = words.slice(0, shown).join(" ");
  const parts: React.ReactNode[] = [];
  // Colours the figures that answer the question, once they are written
  for (const h of highlight) {
    const i = joined.indexOf(h);
    if (i >= 0) {
      parts.push(joined.slice(0, i), <span key={h} style={{ color: C.green }}>{h}</span>);
      joined = joined.slice(i + h.length);
    }
  }
  parts.push(joined);
  return <>{parts}</>;
};

// Yumi in each part of the film
const PENSE: YumiScript = {
  seed: 401,
  cues: [
    { at: 0, mood: "curious", rim: "calm" },
    { at: 0.9, mood: "thinking", rim: "think" },
    { at: ANSWER + 0.2, mood: "happy", rim: "calm" },
  ],
};
// The matcha, cut in the middle of its routine: the long sip comes at once, then the sigh
const MATCHA_YUMI: YumiScript = { seed: 402, lead: 3.05, cues: [{ at: 0, habit: "matcha" }] };
const ACCORD: YumiScript = {
  seed: 403,
  cues: [
    { at: 0, mood: "neutral", rim: "work" },
    { at: REQUEST - SESSIONS, mood: "surprised", rim: "warn", pose: "pop" },
    { at: YES - SESSIONS + 0.2, mood: "happy", rim: "done", pose: "celebrate" },
  ],
};
const FIN: YumiScript = {
  seed: 404,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.3, mood: "wink", rim: "calm" },
    { at: 1.9, mood: "happy" },
  ],
};

/** A Claude Code session, as one line of the island. */
const Ligne: React.FC<{ readonly dot: string; readonly name: string; readonly detail: string; readonly label: string; readonly time: string; readonly style?: React.CSSProperties }> = ({
  dot,
  name,
  detail,
  label,
  time,
  style,
}) => (
  <div style={{ display: "flex", alignItems: "center", gap: 18, height: 66, padding: "0 18px", fontFamily: THEME.text, ...style }}>
    <span style={{ width: 16, height: 16, borderRadius: 8, backgroundColor: dot, flexShrink: 0 }} />
    <span style={{ fontSize: 32, fontWeight: 600, color: C.fg }}>{name}</span>
    <span style={{ flex: 1, fontSize: 30, color: C.muted, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{detail}</span>
    <span style={{ fontSize: 29, fontWeight: 600, color: dot }}>{label}</span>
    <span style={{ minWidth: 90, textAlign: "right", fontSize: 29, fontWeight: 600, color: C.faint, fontVariantNumeric: "tabular-nums" }}>{time}</span>
  </div>
);

export const Journee: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const { fps } = useVideoConfig();

  // The island changes size with what it shows: the chat, the folded agent at work, the sessions
  const h =
    interpolate(t, [0, MATCHA - 0.3, MATCHA + 0.25, SESSIONS - 0.3, SESSIONS + 0.3, END - 0.4, END], [480, 480, 300, 300, 530, 530, 0], {
      ...CLAMP,
      easing: EASE.camera,
    }) -
    230 * ease(t, REQUEST + 0.1, REQUEST + 0.5) * (1 - ease(t, YES + 0.45, YES + 0.85));
  const w = interpolate(t, [MATCHA - 0.3, MATCHA + 0.25, SESSIONS - 0.3, SESSIONS + 0.3], [1000, 760, 760, 1000], { ...CLAMP, easing: EASE.camera });
  const show = (a: number, b: number) => ease(t, a, a + 0.3) * (1 - ease(t, b - 0.3, b));
  // The request takes the place of the header, then gives it back: never both at once
  const asked = ease(t, REQUEST + 0.15, REQUEST + 0.55, EASE.spring) * (1 - ease(t, YES + 0.35, YES + 0.6));
  const header = (1 - ease(t, REQUEST - 0.05, REQUEST + 0.15)) + ease(t, YES + 0.65, YES + 0.95);
  const ok = ease(t, YES + 0.5, YES + 0.8);

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {/* The screen, and the island hanging from its top edge */}
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: c.screenTop,
          height: c.tall ? 1060 : 960,
          background: "radial-gradient(120% 90% at 50% 0%, #1D2030 0%, #0D0E15 60%, #000 100%)",
          opacity: 1 - ease(t, END - 0.2, END + 0.5),
        }}
      />
      <div
        style={{
          position: "absolute",
          left: (c.W - w) / 2,
          top: c.screenTop,
          width: w,
          height: h,
          backgroundColor: C.island,
          borderRadius: "0 0 64px 64px",
          overflow: "hidden",
          boxShadow: "0 30px 90px rgba(0,0,0,0.5)",
        }}
      >
        {/* 1. The question, and his answer */}
        <Sequence durationInFrames={Math.round(MATCHA * fps)} layout="none">
          <div style={{ position: "absolute", inset: 0, opacity: show(-1, MATCHA - 0.1) }}>
            <div
              style={{
                position: "absolute",
                right: 40,
                top: 44,
                maxWidth: 700,
                padding: "20px 28px",
                borderRadius: 30,
                backgroundColor: C.bubble,
                fontFamily: THEME.text,
                fontSize: 36,
                fontWeight: 500,
                lineHeight: 1.3,
                color: C.fg,
              }}
            >
              {QUESTION}
            </div>
            <Yumi script={PENSE} size={190} style={{ position: "absolute", left: 30, top: 250 }} />
            <div style={{ position: "absolute", left: 240, right: 50, top: 236, fontFamily: THEME.text, fontSize: 36, lineHeight: 1.36, color: C.fg }}>
              {t < ANSWER ? (
                <span style={{ color: C.muted, opacity: ease(t, 0.7, 0.95), letterSpacing: "0.2em" }}>···</span>
              ) : (
                <>
                  <Ecrit text={REPONSE[0]} at={ANSWER} />{" "}
                  <Ecrit text={REPONSE[1]} at={ANSWER + REPONSE[0].split(" ").length * 0.075} highlight={["7\u00a0h,", "12\u00a0h\u00a0à\u00a017\u00a0h"]} />
                </>
              )}
            </div>
          </div>
        </Sequence>

        {/* 2. Folded while an agent works: the matcha */}
        <Sequence from={Math.round((MATCHA - 0.2) * fps)} durationInFrames={Math.round((SESSIONS - MATCHA + 0.1) * fps)} layout="none">
          <div style={{ position: "absolute", inset: 0, opacity: show(MATCHA - 0.1, SESSIONS - 0.1) }}>
            <Yumi script={MATCHA_YUMI} size={230} style={{ position: "absolute", left: 28, top: 40 }} />
            <div style={{ position: "absolute", left: 290, right: 40, top: 70, fontFamily: THEME.text }}>
              <div style={{ display: "flex", alignItems: "center", gap: 14, fontSize: 32, fontWeight: 600, color: C.fg }}>
                <span style={{ width: 16, height: 16, borderRadius: 8, backgroundColor: C.blue }} />
                atelier
              </div>
              <div style={{ marginTop: 10, fontSize: 32, color: C.muted }}>Modifie Accueil.swift</div>
              <div style={{ marginTop: 10, fontSize: 30, fontWeight: 600, color: C.blue }}>
                travaille · <span style={{ fontVariantNumeric: "tabular-nums" }}>{12 + Math.floor((t - MATCHA) / 4)} min</span>
              </div>
            </div>
          </div>
        </Sequence>

        {/* 3. Three sessions; one asks */}
        <Sequence from={Math.round((SESSIONS - 0.2) * fps)} durationInFrames={Math.round((END - SESSIONS + 0.2) * fps)} layout="none">
          <div style={{ position: "absolute", inset: 0, opacity: show(SESSIONS - 0.1, END - 0.2) }}>
            <Yumi script={ACCORD} size={170} style={{ position: "absolute", left: 30, top: 34 }} />
            {/* The header, or the request when one comes */}
            <div style={{ position: "absolute", left: 230, right: 40, top: 60, fontFamily: THEME.text, opacity: header }}>
              <div style={{ fontSize: 38, fontWeight: 700, color: C.fg }}>Claude Code</div>
              <div style={{ marginTop: 6, fontSize: 30, color: C.muted }}>3 sessions</div>
            </div>
            <div style={{ position: "absolute", left: 230, right: 40, top: 40, fontFamily: THEME.text, opacity: asked, translate: `0 ${(1 - asked) * 20}px` }}>
              <div style={{ fontSize: 26, fontWeight: 600, color: C.amber }}>● Claude Code · api</div>
              <div style={{ marginTop: 6, fontSize: 34, fontWeight: 700, color: C.fg, maxWidth: 450, lineHeight: 1.2 }}>Claude veut lancer ça. Je laisse passer ?</div>
              <div style={{ marginTop: 8, fontFamily: '"SF Mono", ui-monospace, Menlo, monospace', fontSize: 28, color: "#D6DAEA" }}>
                <span style={{ color: C.amber }}>$</span> npm test
              </div>
              {/* No and yes, as round buttons */}
              <div style={{ position: "absolute", right: 0, top: 30, display: "flex", gap: 22 }}>
                <span style={{ width: 92, height: 92, borderRadius: 46, backgroundColor: C.red, display: "flex", alignItems: "center", justifyContent: "center", color: "#fff", fontSize: 44, fontWeight: 600 }}>✕</span>
                <span
                  style={{
                    width: 92,
                    height: 92,
                    borderRadius: 46,
                    backgroundColor: C.green,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    color: "#06070C",
                    fontSize: 46,
                    fontWeight: 700,
                    scale: 1 - 0.12 * interpolate(t, [YES - 0.06, YES, YES + 0.15], [0, 1, 0], CLAMP),
                    position: "relative",
                  }}
                >
                  ✓
                  <span
                    style={{
                      position: "absolute",
                      left: "50%",
                      top: "50%",
                      width: interpolate(t, [YES, YES + 0.5], [92, 220], { ...CLAMP, easing: EASE.out }),
                      aspectRatio: "1",
                      translate: "-50% -50%",
                      borderRadius: "50%",
                      border: `4px solid ${C.green}`,
                      opacity: interpolate(t, [YES - 0.01, YES + 0.03, YES + 0.5], [0, 0.9, 0], CLAMP),
                    }}
                  />
                </span>
              </div>
            </div>
            {/* The sessions, one line each */}
            <div style={{ position: "absolute", left: 30, right: 30, top: 270, opacity: 1 - asked }}>
              <Ligne
                dot={ok > 0.5 ? C.green : C.amber}
                name="api"
                detail={ok > 0.5 ? "C'est passé." : "Demande Bash : npm test"}
                label={ok > 0.5 ? "terminée" : "attend un accord"}
                time={ok > 0.5 ? "0 s" : `${40 + Math.floor(Math.max(0, t - SESSIONS))} s`}
                style={{ borderRadius: 16 }}
              />
              <Ligne dot={C.blue} name="atelier" detail="Modifie Accueil.swift" label="travaille" time="12 min" />
              <Ligne dot={C.green} name="site" detail="C'est passé." label="terminée" time="2 min" />
            </div>
          </div>
        </Sequence>
      </div>

      {/* The end */}
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <Yumi script={FIN} size={c.tall ? 560 : 500} style={{ position: "absolute", left: (c.W - (c.tall ? 560 : 500)) / 2, top: c.tall ? 470 : 200 }} />
        <AbsoluteFill style={{ top: c.tall ? 1010 : 730 }}>
          <Words lines={["Yumi."]} by="letter" enter={0.25} size={150} style={{ fontWeight: 700 }} />
          <Words lines={["Alpha gratuite.", "Lien en commentaire."]} enter={0.75} size={60} style={{ color: C.muted, marginTop: 18, lineHeight: 1.2 }} />
        </AbsoluteFill>
      </Sequence>

      <SousTitre at={-1} end={3.2}>Je lui demande mon temps libre de demain.</SousTitre>
      <SousTitre at={3.3} end={6.4}>Il me répond. Mon agenda ne quitte pas mon Mac.</SousTitre>
      <SousTitre at={MATCHA + 0.2} end={SESSIONS - 0.1}>Pendant que l'agent code, il boit son matcha.</SousTitre>
      <SousTitre at={SESSIONS + 0.2} end={YES - 0.3}>Une session attend mon accord.</SousTitre>
      <SousTitre at={YES - 0.2} end={END - 0.2}>Je réponds depuis la notch, sans quitter ce que je fais.</SousTitre>

      <Son name="send" at={0.1} volume={0.45} />
      <Son name="think" at={0.8} volume={0.45} />
      <Son name="tick" at={ANSWER} volume={0.3} />
      <Son name="pop" at={MATCHA} volume={0.4} />
      <Son name="approval" at={REQUEST} volume={0.6} />
      <Son name="approve" at={YES} volume={0.7} />
      <Son name="finish" at={YES + 0.4} volume={0.5} />
      <Son name="wink" at={END + 1.3} volume={0.6} />
    </AbsoluteFill>
  );
};
