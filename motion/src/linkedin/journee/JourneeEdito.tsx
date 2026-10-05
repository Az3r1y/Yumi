import React from "react";
import { AbsoluteFill, Sequence, interpolate, useVideoConfig } from "remotion";
import { Son } from "../../son/Son";
import { EASE, THEME } from "../../theme";
import { Words } from "../../type/Words";
import { Yumi } from "../../yumi/Yumi";
import type { YumiScript } from "../../yumi/engine";
import { ANSWER, CLAMP, END, MATCHA, MATCHA_YUMI, PRISES, Prise, REQUEST, SESSIONS, SIP, TAKE, YES, ease, useT } from "./prises";

// The same day, staged as a magazine page instead of a black screen. The page is paper, the
// type is ink and large, and the real takes are dark slices of the screen laid on the page,
// offset, bleeding off one edge or the other. Each beat has one big word that the take
// covers in part; the matcha turns the page green. Changes happen through masks: the words
// rise from behind their line, the takes open sideways, the colour climbs the page.
// Same takes, same beats and same sentences as Journee.tsx.

const P = {
  paper: "#ECE9E1",
  ink: "#0C0C10",
  soft: "#55545C",
  matcha: "#B4C98C",
  amber: "#C77A10",
  green: "#1F8F5A",
  light: "linear-gradient(90deg, #5B8CFF, #8B6CFF 50%, #F58AD9)",
};

const useMise = () => {
  const { width, height } = useVideoConfig();
  const tall = height / width > 1.5;
  const w = 1000;
  const h = Math.round((w * TAKE.h) / TAKE.w);
  const y = tall ? 900 : 520;
  return {
    W: width,
    tall,
    margin: 80,
    kickerY: tall ? 300 : 86,
    headY: tall ? 370 : 150,
    /** The takes bleed off the right edge, the matcha off the left. */
    right: { x: width - w, y, w, h },
    left: { x: 0, y, w, h },
    captionY: y + h + 50,
    footY: tall ? 1790 : 1250,
  };
};

/** The small line above the headline: number and subject of the beat. */
const Kicker: React.FC<{ readonly at: number; readonly end: number; readonly children: string; readonly color?: string }> = ({ at, end, children, color = P.soft }) => {
  const m = useMise();
  return (
    <div style={{ position: "absolute", left: m.margin, top: m.kickerY }}>
      <Words
        lines={[children]}
        enter={at}
        exit={end}
        size={30}
        stagger={0.05}
        style={{ textAlign: "left", fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", color }}
      />
    </div>
  );
};

/** The big word of a beat. It sits behind the take: the take covers its foot. */
const Titre: React.FC<{ readonly at: number; readonly end?: number; readonly lines: readonly string[]; readonly size: number; readonly color?: string; readonly top?: number }> = ({
  at,
  end,
  lines,
  size,
  color = P.ink,
  top = 0,
}) => {
  const m = useMise();
  return (
    <div style={{ position: "absolute", left: m.margin - size * 0.06, right: 40, top: m.headY + top }}>
      <Words lines={lines} enter={at} exit={end} size={size} style={{ textAlign: "left", fontWeight: 800, lineHeight: 0.98, whiteSpace: "nowrap", color }} />
    </div>
  );
};

/** The sentence of the beat, under the take: what is happening, said plainly. */
const Legende: React.FC<{ readonly at: number; readonly end: number; readonly children: string }> = ({ at, end, children }) => {
  const t = useT();
  const m = useMise();
  if (t < at - 0.05 || t > end + 0.05) return null;
  const k = ease(t, at, at + 0.4, EASE.out) * (1 - ease(t, end - 0.25, end, EASE.in));
  return (
    <div
      style={{
        position: "absolute",
        left: m.margin,
        right: m.margin + 60,
        top: m.captionY,
        fontFamily: THEME.text,
        fontSize: 46,
        fontWeight: 600,
        lineHeight: 1.18,
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

const FIN: YumiScript = {
  seed: 405,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.4, mood: "wink", rim: "calm" },
    { at: 2.0, mood: "happy" },
  ],
};

export const JourneeEdito: React.FC = () => {
  const m = useMise();
  const t = useT();
  const { fps } = useVideoConfig();

  // The matcha climbs the page from the bottom, then leaves through the top
  const up = ease(t, MATCHA - 0.15, MATCHA + 0.45);
  const off = ease(t, SESSIONS - 0.45, SESSIONS + 0.1);
  const opens = (from: number, to: number) => (s: number) => ease(s, from, from + 0.6) * (1 - ease(s, to - 0.45, to, EASE.in));

  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <div style={{ position: "absolute", inset: 0, backgroundColor: P.matcha, clipPath: `inset(${(1 - up) * 100}% 0 ${off * 100}% 0)` }} />

      {/* 01. The question, then the figure of the answer */}
      <Kicker at={0.1} end={MATCHA - 0.5}>01 · Temps libre</Kicker>
      <Titre at={0.15} end={ANSWER - 0.35} lines={["Combien de temps", "libre demain ?"]} size={112} />
      <Titre at={ANSWER} end={MATCHA - 0.5} lines={["7 h."]} size={330} top={-30} />
      <Prise {...PRISES.libre} box={m.right} reveal={opens(PRISES.libre.from, PRISES.libre.to)} side="right" />

      {/* 02. The matcha, on a green page */}
      <Kicker at={MATCHA + 0.2} end={SESSIONS - 0.5} color={P.ink}>02 · Pendant que l'agent travaille</Kicker>
      <Titre at={MATCHA + 0.3} end={SESSIONS - 0.5} lines={["Matcha."]} size={250} top={40} />
      <Prise
        {...PRISES.matcha}
        box={m.left}
        reveal={opens(PRISES.matcha.from, PRISES.matcha.to)}
        camera={{ focus: MATCHA_YUMI, zoom: 2.6, at: MATCHA + 0.8, length: 1.0 }}
      />

      {/* 03. Three sessions, one asks, the answer */}
      <Kicker at={SESSIONS + 0.15} end={END - 0.5}>03 · Claude Code</Kicker>
      <Titre at={SESSIONS + 0.2} end={REQUEST - 0.35} lines={["3 sessions."]} size={175} top={60} />
      <Titre at={REQUEST} end={YES - 0.3} lines={["1 attend."]} size={175} top={60} color={P.amber} />
      <Titre at={YES} end={END - 0.5} lines={["Oui."]} size={250} top={20} color={P.green} />
      <Prise {...PRISES.sessions} box={m.right} reveal={opens(PRISES.sessions.from, PRISES.sessions.to)} side="right" />

      <Legende at={0.3} end={ANSWER}>Je lui demande mon temps libre de demain.</Legende>
      <Legende at={ANSWER + 0.1} end={MATCHA - 0.2}>Il regarde mon agenda et me répond.</Legende>
      <Legende at={MATCHA + 0.3} end={SESSIONS - 0.2}>Pendant que l'agent travaille, il boit son matcha.</Legende>
      <Legende at={SESSIONS + 0.3} end={REQUEST - 0.1}>Trois sessions Claude Code ouvertes.</Legende>
      <Legende at={REQUEST} end={YES - 0.1}>L'une attend mon accord.</Legende>
      <Legende at={YES} end={END - 0.3}>Je réponds depuis la notch, sans changer de fenêtre.</Legende>

      {/* The foot of the page: Yumi's light as a rule, and what the images are */}
      <div
        style={{
          position: "absolute",
          left: m.margin,
          top: m.footY,
          width: interpolate(t, [0.2, 1.4], [0, m.W - m.margin * 2], { ...CLAMP, easing: EASE.camera }),
          height: 4,
          background: P.light,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: m.margin,
          top: m.footY + 22,
          fontFamily: THEME.text,
          fontSize: 26,
          fontWeight: 600,
          letterSpacing: "0.02em",
          color: P.soft,
          opacity: ease(t, 0.8, 1.3) * (1 - ease(t, END - 0.4, END)),
        }}
      >
        Filmé sur mon Mac · mode tournage, données d'exemple
      </div>

      {/* The end: the name set large on the left, him at the top right, hanging from the page */}
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <Yumi script={FIN} size={m.tall ? 440 : 380} style={{ position: "absolute", right: 60, top: m.tall ? 300 : 120 }} />
        <div style={{ position: "absolute", left: m.margin - 14, top: m.tall ? 820 : 560 }}>
          <Words lines={["Yumi."]} by="letter" enter={0.3} size={300} style={{ textAlign: "left", fontWeight: 800, color: P.ink }} />
        </div>
        <div style={{ position: "absolute", left: m.margin, top: m.tall ? 1180 : 900 }}>
          <Words lines={["Alpha gratuite.", "Lien en commentaire."]} enter={0.8} size={62} style={{ textAlign: "left", fontWeight: 600, color: P.soft, lineHeight: 1.15 }} />
        </div>
      </Sequence>

      <Son name="send" at={0.15} volume={0.45} />
      <Son name="tick" at={ANSWER} volume={0.3} />
      <Son name="pop" at={MATCHA + 0.1} volume={0.4} />
      <Son name="tick" at={SIP} volume={0.25} />
      <Son name="approval" at={REQUEST} volume={0.6} />
      <Son name="approve" at={YES} volume={0.7} />
      <Son name="finish" at={YES + 0.3} volume={0.5} />
      <Son name="wink" at={END + 1.4} volume={0.6} />
    </AbsoluteFill>
  );
};
