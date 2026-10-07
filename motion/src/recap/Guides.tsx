import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, Sequence, interpolate, staticFile, useVideoConfig } from "remotion";
import { EASE } from "../theme";
import { Words } from "../type/Words";
import { Balade } from "./Alpha5";
import { CLAMP, Folio, Kicker, Legende, P, Pied, Titre, useMise, useT } from "./page";

// Short explainers, one feature each, on the magazine page: a hook, four numbered steps, the
// link. Yumi walks behind. Every sentence says what the code does (commit messages of
// dcee045 GitHub, 14ded30 Notion, acaf092 live sessions, 7291eb7 modules, and the site's
// install steps); there is no take of these screens, so nothing pretends to show them.

const HOOK = 2.4;
const STEP = 3.2;
const END = HOOK + 4 * STEP;
export const GUIDE_LENGTH = END + 2.8;

type Etape = { readonly lines: readonly string[]; readonly sub: string };
type Guide = { readonly kicker: string; readonly hook: readonly string[]; readonly steps: readonly Etape[] };

const GUIDES: Record<string, Record<"fr" | "en", Guide>> = {
  github: {
    fr: {
      kicker: "Yumi · GitHub",
      hook: ["GitHub,", "dans ta notch."],
      steps: [
        { lines: ["Colle un jeton."], sub: "Dans les réglages de Yumi. La lecture seule suffit." },
        { lines: ["Tous tes", "dépôts."], sub: "Tous ceux que ton jeton voit. Tu peux en masquer." },
        { lines: ["Les commits", "exacts."], sub: "Chaque push avec ses commits : message, sha, auteur. Un clic ouvre le commit." },
        { lines: ["Les pull", "requests."], sub: "Avec leurs checks. Un check rouge remonte dans l'île repliée." },
      ],
    },
    en: {
      kicker: "Yumi · GitHub",
      hook: ["GitHub,", "in your notch."],
      steps: [
        { lines: ["Paste a token."], sub: "In Yumi's settings. Read-only is enough." },
        { lines: ["All your", "repos."], sub: "Every repo your token can see. Hide the ones you don't want." },
        { lines: ["The exact", "commits."], sub: "Every push with its commits: message, sha, author. One click opens the commit." },
        { lines: ["Pull", "requests."], sub: "With their checks. A red check shows up in the folded island." },
      ],
    },
  },
  notion: {
    fr: {
      kicker: "Yumi · Notion",
      hook: ["Notion,", "dans ta notch."],
      steps: [
        { lines: ["Ta clé", "d'intégration."], sub: "Dans les réglages de Yumi. Elle reste dans le trousseau du Mac." },
        { lines: ["Choisis", "tes bases."], sub: "Celles partagées avec l'intégration, avec leur date et leur case « fait »." },
        { lines: ["Le jour", "et le retard."], sub: "Tes tâches du jour et en retard. Un clic ouvre la page." },
        { lines: ["« Ajoute", "une tâche. »"], sub: "Yumi crée la page après ton accord. Il ne modifie ni ne supprime rien." },
      ],
    },
    en: {
      kicker: "Yumi · Notion",
      hook: ["Notion,", "in your notch."],
      steps: [
        { lines: ["Your", "integration key."], sub: "In Yumi's settings. It stays in your Mac's keychain." },
        { lines: ["Pick your", "databases."], sub: "The ones shared with the integration, with their date and done fields." },
        { lines: ["Today and", "overdue."], sub: "Your tasks for today and the late ones. One click opens the page." },
        { lines: ["“Add a", "task.”"], sub: "Yumi creates the page after you approve. It never edits or deletes anything." },
      ],
    },
  },
  claude: {
    fr: {
      kicker: "Yumi · Claude Code",
      hook: ["Ce que fait", "Claude,", "en direct."],
      steps: [
        { lines: ["La demande."], sub: "Chaque session affiche ta demande, sur une ligne." },
        { lines: ["3/7"], sub: "La liste de tâches de Claude, et celle en cours." },
        { lines: ["L'action", "en cours."], sub: "Avec sa cible, et les six dernières actions." },
        { lines: ["Le résumé."], sub: "À la fin du tour, sa dernière phrase. Rien ne quitte le Mac." },
      ],
    },
    en: {
      kicker: "Yumi · Claude Code",
      hook: ["What Claude", "is doing,", "live."],
      steps: [
        { lines: ["The request."], sub: "Each session shows what you asked, on one line." },
        { lines: ["3/7"], sub: "Claude's todo list, and the task in progress." },
        { lines: ["The current", "action."], sub: "With its target, and the last six actions." },
        { lines: ["The summary."], sub: "At the end of a turn, its last sentence. Nothing leaves your Mac." },
      ],
    },
  },
  usage: {
    fr: {
      kicker: "Yumi · Prise en main",
      hook: ["Yumi", "en 4 gestes."],
      steps: [
        { lines: ["Installe."], sub: "Glisse Yumi dans Applications. La première fois : Réglages Système, Confidentialité, « Ouvrir quand même »." },
        { lines: ["Branche", "Claude Code."], sub: "Installe ses hooks depuis les réglages. Il te montre le changement avant de l'écrire." },
        { lines: ["Clique", "sur l'île."], sub: "Tes modules, dans l'ordre que tu choisis. Le mode édition les range." },
        { lines: ["Parle-lui."], sub: "Il te montre ce qu'il va faire, et attend ton accord." },
      ],
    },
    en: {
      kicker: "Yumi · Getting started",
      hook: ["Yumi in", "4 moves."],
      steps: [
        { lines: ["Install."], sub: "Drag Yumi to Applications. The first time: System Settings, Privacy, “Open Anyway”." },
        { lines: ["Connect", "Claude Code."], sub: "Install its hooks from the settings. It shows you the change before writing it." },
        { lines: ["Click the", "island."], sub: "Your modules, in the order you choose. Edit mode rearranges them." },
        { lines: ["Talk to it."], sub: "It shows you what it's about to do, and waits for your OK." },
      ],
    },
  },
};

const GuideFilm: React.FC<{ readonly sujet: keyof typeof GUIDES; readonly langue: "fr" | "en" }> = ({ sujet, langue }) => {
  const g = GUIDES[sujet][langue];
  const m = useMise();
  const t = useT();
  const { fps } = useVideoConfig();
  const at = (i: number) => HOOK + i * STEP;
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <Kicker at={0.1} end={END - 0.4}>{g.kicker}</Kicker>
      <Titre at={0.15} end={HOOK - 0.3} lines={g.hook} size={m.tall ? 128 : 116} />
      {g.steps.map((s, i) => (
        <React.Fragment key={s.sub}>
          <Folio at={at(i) + 0.05} end={at(i + 1) - 0.25}>{`${i + 1} / 4`}</Folio>
          <Titre at={at(i)} end={at(i + 1) - 0.3} lines={s.lines} size={s.lines[0] === "3/7" ? 300 : m.tall ? 116 : 104} />
          <Legende at={at(i) + 0.25} end={at(i + 1) - 0.05}>{s.sub}</Legende>
        </React.Fragment>
      ))}
      <Balade from={0.2} to={END} y={m.tall ? 840 : 640} size={m.tall ? 260 : 220} hop={0.6} />
      <Pied lines={[]} />
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <div style={{ position: "absolute", left: m.margin - 8, top: m.tall ? 700 : 480 }}>
          <Words lines={["Yumi."]} by="letter" enter={0.2} size={m.tall ? 220 : 200} style={{ textAlign: "left", fontWeight: 800, color: P.ink }} />
          <div
            style={{
              marginTop: 24,
              fontFamily: P.mono,
              fontSize: 36,
              color: P.soft,
              clipPath: `inset(0 ${(1 - interpolate(t - END, [0.7, 1.4], [0, 1], { ...CLAMP, easing: EASE.out })) * 100}% 0 0)`,
            }}
          >
            github.com/estebanbaigts/Yumi
          </div>
        </div>
      </Sequence>
      <Audio
        src={staticFile("musique/lofi-recap.wav")}
        trimBefore={Math.round(8 * fps)}
        volume={(f) => 0.42 * interpolate(f / fps, [0, 0.6, GUIDE_LENGTH - 1.5, GUIDE_LENGTH], [0, 1, 1, 0], CLAMP)}
      />
    </AbsoluteFill>
  );
};

export const GuideGithubFr: React.FC = () => <GuideFilm sujet="github" langue="fr" />;
export const GuideGithubEn: React.FC = () => <GuideFilm sujet="github" langue="en" />;
export const GuideNotionFr: React.FC = () => <GuideFilm sujet="notion" langue="fr" />;
export const GuideNotionEn: React.FC = () => <GuideFilm sujet="notion" langue="en" />;
export const GuideClaudeFr: React.FC = () => <GuideFilm sujet="claude" langue="fr" />;
export const GuideClaudeEn: React.FC = () => <GuideFilm sujet="claude" langue="en" />;
export const GuideUsageFr: React.FC = () => <GuideFilm sujet="usage" langue="fr" />;
export const GuideUsageEn: React.FC = () => <GuideFilm sujet="usage" langue="en" />;
