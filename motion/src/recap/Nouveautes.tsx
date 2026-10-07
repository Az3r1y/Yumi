import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, Sequence, interpolate, staticFile, useVideoConfig } from "remotion";
import { EASE } from "../theme";
import { Words } from "../type/Words";
import { CLAMP, Kicker, Legende, P, Pied, Plan, Titre, useMise, useT, type TAKES } from "./page";

// Alpha 5, one feature per video, 10 seconds each, on the magazine page. Each one is a real
// take: the app filmed in its filming mode (shots 13 to 15 of IslandStudio, branch
// yumi/tournage-alpha5), with its example data, cut around the island.

export const NOUVEAUTE_LENGTH = 10;
const TAKE_END = 8.4;

type Sujet = { readonly take: keyof typeof TAKES; readonly fr: Texte; readonly en: Texte };
type Texte = { readonly kicker: string; readonly lines: readonly string[]; readonly legende: string };

const SUJETS: Record<"claude" | "github" | "notion", Sujet> = {
  claude: {
    take: "a5-claude",
    fr: { kicker: "Alpha 5 · Claude Code", lines: ["Claude,", "en direct."], legende: "Chaque session montre ta demande, sa tâche 2/7 et l'action en cours." },
    en: { kicker: "Alpha 5 · Claude Code", lines: ["Claude,", "live."], legende: "Each session shows your request, its task 2/7 and the action in progress." },
  },
  github: {
    take: "a5-github",
    fr: { kicker: "Alpha 5 · GitHub", lines: ["Tous tes", "dépôts."], legende: "Chaque push avec ses commits exacts. Un nouveau push remonte dans la notch." },
    en: { kicker: "Alpha 5 · GitHub", lines: ["All your", "repos."], legende: "Every push with its exact commits. A new push shows up in the notch." },
  },
  notion: {
    take: "a5-notion",
    fr: { kicker: "Alpha 5 · Notion", lines: ["Notion,", "dans la notch."], legende: "Tes tâches du jour et en retard, d'un coup d'œil." },
    en: { kicker: "Alpha 5 · Notion", lines: ["Notion,", "in the notch."], legende: "Today's and overdue tasks, at a glance." },
  },
};

const Film: React.FC<{ readonly sujet: keyof typeof SUJETS; readonly langue: "fr" | "en" }> = ({ sujet, langue }) => {
  const s = SUJETS[sujet];
  const tx = s[langue];
  const m = useMise();
  const t = useT();
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <Kicker at={0.1} end={TAKE_END - 0.3}>{tx.kicker}</Kicker>
      <Titre at={0.15} end={TAKE_END - 0.3} lines={tx.lines} size={m.tall ? 128 : 112} />
      <Plan take={s.take} source={0} crop={{ x: 0, y: 0, w: 1320, h: 540 }} from={0.2} to={TAKE_END} />
      <Legende at={0.5} end={TAKE_END - 0.1}>{tx.legende}</Legende>
      <Pied lines={[{ at: 0.6, end: TAKE_END - 0.2, text: langue === "fr" ? "Prise réelle de l'app · mode tournage, données d'exemple" : "Real take from the app (in French) · filming mode, sample data" }]} />
      <Sequence from={Math.round(TAKE_END * fps)} premountFor={fps}>
        <div style={{ position: "absolute", left: m.margin - 8, top: m.tall ? 640 : 440 }}>
          <Words lines={["Yumi alpha 5.", langue === "fr" ? "Gratuit." : "Free."]} enter={0.05} stagger={0.06} size={m.tall ? 120 : 110} style={{ textAlign: "left", fontWeight: 800, color: P.ink, lineHeight: 1.0 }} />
          <div
            style={{
              marginTop: 28,
              fontFamily: P.mono,
              fontSize: 36,
              color: P.soft,
              clipPath: `inset(0 ${(1 - interpolate(t - TAKE_END, [0.4, 1.0], [0, 1], { ...CLAMP, easing: EASE.out })) * 100}% 0 0)`,
            }}
          >
            github.com/estebanbaigts/Yumi
          </div>
        </div>
      </Sequence>
      <Audio
        src={staticFile("musique/lofi-recap.wav")}
        trimBefore={Math.round(4 * fps)}
        volume={(f) => 0.42 * interpolate(f / fps, [0, 0.5, NOUVEAUTE_LENGTH - 1.2, NOUVEAUTE_LENGTH], [0, 1, 1, 0], CLAMP)}
      />
    </AbsoluteFill>
  );
};

export const NouveauteClaudeFr: React.FC = () => <Film sujet="claude" langue="fr" />;
export const NouveauteClaudeEn: React.FC = () => <Film sujet="claude" langue="en" />;
export const NouveauteGithubFr: React.FC = () => <Film sujet="github" langue="fr" />;
export const NouveauteGithubEn: React.FC = () => <Film sujet="github" langue="en" />;
export const NouveauteNotionFr: React.FC = () => <Film sujet="notion" langue="fr" />;
export const NouveauteNotionEn: React.FC = () => <Film sujet="notion" langue="en" />;

/** The three in a row, in English: each take, then one end card. */
export const NOUVEAUTES_LENGTH = 3 * TAKE_END + (NOUVEAUTE_LENGTH - TAKE_END);
export const NouveautesEn: React.FC = () => {
  const { fps } = useVideoConfig();
  const step = Math.round(TAKE_END * fps);
  return (
    <AbsoluteFill>
      <Sequence durationInFrames={step}><Film sujet="claude" langue="en" /></Sequence>
      <Sequence from={step} durationInFrames={step}><Film sujet="github" langue="en" /></Sequence>
      <Sequence from={2 * step}><Film sujet="notion" langue="en" /></Sequence>
    </AbsoluteFill>
  );
};
