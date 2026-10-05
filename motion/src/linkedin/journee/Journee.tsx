import React from "react";
import { AbsoluteFill, Sequence, useVideoConfig } from "remotion";
import { Son } from "../../son/Son";
import { EASE, THEME } from "../../theme";
import { Words } from "../../type/Words";
import { Yumi } from "../../yumi/Yumi";
import type { YumiScript } from "../../yumi/engine";
import { ANSWER, END, MATCHA, MATCHA_YUMI, PRISES, Prise, REQUEST, SESSIONS, SIP, TAKE, YES, ease, useT } from "./prises";

// LinkedIn, after the alpha: a developer's day with Yumi, in 25 seconds, told only by what is
// new and was never shown. One question about tomorrow's free time, the matcha while an agent
// works, and three Claude Code sessions, one of which waits for an answer given from the notch.
//
// Every image of the island is a real take (see prises.tsx). The film is written for 4:5 (the
// feed) and 9:16. JourneeEdito.tsx tells the same with another staging.

export { JOURNEE_LENGTH } from "./prises";

const C = { fg: "#F4F5F8", muted: "#8D92A8", faint: "#5A5F74" };

/** The frame: 4:5 or 9:16, and where things go in it. */
const useCadre = () => {
  const { width, height } = useVideoConfig();
  const tall = height / width > 1.5;
  const w = width - 40;
  return { W: width, H: height, tall, box: { x: 20, y: tall ? 680 : 380, w, h: Math.round((w * TAKE.h) / TAKE.w) }, captionY: tall ? 1180 : 880 };
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

      <Prise {...PRISES.libre} box={c.box} style={{ borderRadius: 26 }} />
      {/* The matcha: the island opens on the session at work, the camera goes in on him */}
      <Prise {...PRISES.matcha} box={c.box} style={{ borderRadius: 26 }} camera={{ focus: MATCHA_YUMI, zoom: 2.6, at: MATCHA + 0.7, length: 1.0 }} />
      <Prise {...PRISES.sessions} box={c.box} style={{ borderRadius: 26 }} />

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
      <SousTitre at={MATCHA + 0.2} end={SESSIONS - 0.1}>Pendant que l'agent travaille, il boit son matcha.</SousTitre>
      <SousTitre at={SESSIONS + 0.2} end={REQUEST - 0.1}>Trois sessions Claude Code ouvertes.</SousTitre>
      <SousTitre at={REQUEST} end={YES - 0.1}>L'une attend mon accord.</SousTitre>
      <SousTitre at={YES} end={END - 0.2}>Je réponds depuis la notch, sans changer de fenêtre.</SousTitre>

      <Son name="send" at={0.15} volume={0.45} />
      <Son name="tick" at={ANSWER} volume={0.3} />
      <Son name="pop" at={MATCHA + 0.1} volume={0.4} />
      <Son name="tick" at={SIP} volume={0.25} />
      <Son name="approval" at={REQUEST} volume={0.6} />
      <Son name="approve" at={YES} volume={0.7} />
      <Son name="finish" at={YES + 0.3} volume={0.5} />
      <Son name="wink" at={END + 1.3} volume={0.6} />
    </AbsoluteFill>
  );
};
