import React from "react";
import { AbsoluteFill, Sequence, interpolate, useVideoConfig } from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { CLAMP, Folio, Kicker, Legende, P, Pied, Plan, Titre, ease, useMise, useT, type Rect } from "./page";

// A recap of the project, in under a minute, set as a magazine page (JourneeEdito's paper,
// large type, the matcha page). Five numbered chapters, like a table of contents: where it
// started, what was built, the figures, how, what comes next.
//
// Nothing is invented. The figures were checked against the repository on 6 October 2026
// (commits, Swift lines outside the tests, tests, the share of lines unchanged since the
// Coucou import, releases, stars), the reach of the first post is the one LinkedIn gave. The
// images of the island are the real takes of public/prises; the branches of chapter 04 are
// branches of the repository.

export const RECAP_LENGTH = 58.6;

// The chapters
const BUILT = 6.5;
const FIGURES = 30.5;
const HOW = 42.0;
const NEXT = 49.0;
const END = 54.6;

// Chapter 02, one beat every 2.2 seconds
const BEAT = 2.2;
const ITEMS = 8.5;
const at = (i: number) => ITEMS + i * BEAT;

// The parts of the takes shown: the island under the notch, all cut to the same proportion so
// one take can cover the next
const ILE: Rect = { x: 140, y: 0, w: 1400, h: 467 };
const JOURNEE: Rect = { x: 0, y: 0, w: 1380, h: 460 };
const REVEIL: Rect = { x: 340, y: 0, w: 1000, h: 380 };

const COUCOU = "Code MIT de Louis Raillé, crédité. 1er octobre 2026.";

const ARRIVEE: YumiScript = {
  seed: 501,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 0.9, pose: "wave" },
    { at: 1.8, mood: "neutral", rim: "calm" },
  ],
};
const ECOUTE: YumiScript = {
  seed: 502,
  cues: [
    { at: 0, mood: "curious", rim: "calm", pose: "pop" },
    { at: 1.2, mood: "thinking", rim: "think" },
  ],
};
const FIN: YumiScript = {
  seed: 503,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.4, mood: "wink", rim: "calm" },
    { at: 2.0, mood: "happy" },
  ],
};

/** The figures of chapter 03, in the order the subtitles say them. */
const CHIFFRES: readonly { readonly n: number; readonly label: string; readonly about?: boolean; readonly unit?: string }[] = [
  { n: 206, label: "commits" },
  { n: 27000, label: "lignes de Swift", about: true },
  { n: 778, label: "tests" },
  { n: 2, label: "alphas publiées" },
  { n: 6, label: "de code d'origine restant", about: true, unit: " %" },
  { n: 1, label: "site" },
  { n: 4, label: "vidéos" },
  { n: 40000, label: "impressions, premier post LinkedIn", about: true },
  { n: 11, label: "étoiles sur GitHub" },
];
const WAVES = [FIGURES + 0.5, FIGURES + 4.1, FIGURES + 7.7];

/** French grouping: 27 000. */
const groupe = (n: number) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");

/** One figure: it counts up to its value, its label opens under it. */
const Chiffre: React.FC<{ readonly i: number }> = ({ i }) => {
  const t = useT();
  const m = useMise();
  const c = CHIFFRES[i];
  const start = WAVES[Math.floor(i / 3)] + (i % 3) * 0.22;
  const k = ease(t, start, start + 1.1, EASE.out);
  const show = ease(t, start, start + 0.3) * (1 - ease(t, HOW - 0.45, HOW - 0.1, EASE.in));
  // Three columns across the wide page, two down the 4:5 one
  const cols = m.wide ? 3 : 2;
  const col = i % cols;
  const row = Math.floor(i / cols);
  const cell = m.wide ? { x: m.margin + col * 580, y: 190 + row * 220, w: 540 } : { x: m.margin + col * 480, y: 200 + row * 152, w: 440 };
  const size = m.wide ? 120 : 84;
  return (
    <div style={{ position: "absolute", left: cell.x, top: cell.y, width: cell.w, opacity: show, translate: `0 ${(1 - k) * 30}px` }}>
      <div style={{ fontFamily: THEME.text, fontSize: size, fontWeight: 800, letterSpacing: "-0.04em", lineHeight: 1, color: P.ink, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
        {c.about ? <span style={{ fontWeight: 600, color: P.soft, marginRight: "0.08em" }}>≈</span> : null}
        {groupe(Math.round(c.n * k))}
        {c.unit ?? ""}
      </div>
      <div
        style={{
          marginTop: m.wide ? 14 : 10,
          fontFamily: THEME.text,
          fontSize: m.wide ? 30 : 25,
          fontWeight: 600,
          lineHeight: 1.2,
          color: P.ink,
          opacity: 0.75,
          clipPath: `inset(0 ${(1 - ease(t, start + 0.3, start + 0.9, EASE.out)) * 100}% 0 0)`,
        }}
      >
        {c.label}
      </div>
    </div>
  );
};

/** Chapter 04: branches of the repository run side by side, then meet in main. */
const BRANCHES = ["yumi/personnage", "yumi/ile", "yumi/agent", "yumi/outils", "yumi/permissions", "yumi/moteurs", "yumi/langues", "yumi/menage", "yumi/site", "yumi/motion"];
const MERGE = HOW + 3.5;

const Branches: React.FC = () => {
  const t = useT();
  const m = useMise();
  const g = m.wide
    ? { label: m.margin, start: 470, bend: 1240, merge: 1500, end: m.W - m.margin, top: 418, gap: 42, font: 25 }
    : { label: m.margin, start: 360, bend: 700, merge: 860, end: m.W - m.margin, top: 420, gap: 47, font: 22 };
  const mid = g.top + ((BRANCHES.length - 1) * g.gap) / 2;
  const gone = 1 - ease(t, NEXT - 0.45, NEXT - 0.1, EASE.in);
  const main = ease(t, MERGE + 0.7, MERGE + 1.5);
  return (
    <div style={{ position: "absolute", inset: 0, opacity: gone }}>
      <svg width={m.W} height={m.H} style={{ position: "absolute", inset: 0 }}>
        <defs>
          <linearGradient id="recap-main" gradientUnits="userSpaceOnUse" x1={g.merge} x2={g.end} y1={0} y2={0}>
            <stop offset="0" stopColor="#5B8CFF" />
            <stop offset="0.5" stopColor="#8B6CFF" />
            <stop offset="1" stopColor="#F58AD9" />
          </linearGradient>
        </defs>
        {BRANCHES.map((b, i) => {
          const y = g.top + i * g.gap;
          const run = ease(t, HOW + 0.4 + i * 0.12, HOW + 1.5 + i * 0.12);
          const join = ease(t, MERGE + i * 0.04, MERGE + 0.8 + i * 0.04);
          return (
            <g key={b}>
              <path d={`M ${g.start} ${y} L ${g.bend} ${y}`} pathLength={1} stroke={P.ink} strokeWidth={3} fill="none" strokeDasharray="1 1" strokeDashoffset={1 - run} />
              <path
                d={`M ${g.bend} ${y} C ${g.bend + (g.merge - g.bend) * 0.6} ${y}, ${g.merge - (g.merge - g.bend) * 0.6} ${mid}, ${g.merge} ${mid}`}
                pathLength={1}
                stroke={P.ink}
                strokeWidth={3}
                fill="none"
                strokeDasharray="1 1"
                strokeDashoffset={1 - join}
              />
            </g>
          );
        })}
        <path d={`M ${g.merge} ${mid} L ${g.end} ${mid}`} pathLength={1} stroke="url(#recap-main)" strokeWidth={10} strokeLinecap="round" fill="none" strokeDasharray="1 1" strokeDashoffset={1 - main} />
      </svg>
      {BRANCHES.map((b, i) => {
        const k = ease(t, HOW + 0.3 + i * 0.12, HOW + 0.8 + i * 0.12, EASE.out);
        return (
          <div
            key={b}
            style={{
              position: "absolute",
              left: g.label,
              top: g.top + i * g.gap - g.font * 0.62,
              fontFamily: P.mono,
              fontSize: g.font,
              color: P.ink,
              opacity: k,
              clipPath: `inset(0 ${(1 - k) * 100}% 0 0)`,
            }}
          >
            {b}
          </div>
        );
      })}
      <div style={{ position: "absolute", right: m.margin, top: mid - g.font * 2.6, fontFamily: P.mono, fontSize: g.font + 4, fontWeight: 700, color: P.ink, opacity: main }}>main</div>
    </div>
  );
};

/** What sits in the right column when it is not a take. Times inside are counted from `from`. */
const Scene: React.FC<{ readonly from: number; readonly to: number; readonly children: React.ReactNode }> = ({ from, to, children }) => {
  const t = useT();
  const m = useMise();
  const { fps } = useVideoConfig();
  const k = ease(t, from, from + 0.4) * (1 - ease(t, to - 0.3, to, EASE.in));
  return (
    <Sequence from={Math.round(from * fps)} durationInFrames={Math.round((to - from) * fps)} layout="none">
      <div style={{ position: "absolute", left: m.stage.x, top: m.stage.y, width: m.wide ? m.stage.w - m.margin : m.stage.w - m.margin, height: m.stage.h, opacity: k }}>
        {children}
      </div>
    </Sequence>
  );
};

export const Recap: React.FC = () => {
  const m = useMise();
  const t = useT();
  const { fps } = useVideoConfig();
  const stageW = m.wide ? m.stage.w - m.margin : m.stage.w - m.margin;
  const yumiSize = m.wide ? 340 : 300;

  // The matcha page climbs for the figures, and leaves through the top
  const up = ease(t, FIGURES - 0.2, FIGURES + 0.4);
  const off = ease(t, HOW - 0.4, HOW + 0.15);

  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <div style={{ position: "absolute", inset: 0, backgroundColor: P.matcha, clipPath: `inset(${(1 - up) * 100}% 0 ${off * 100}% 0)` }} />

      {/* 01. Where it started */}
      <Kicker at={0.1} end={BUILT - 0.5}>01 · Le point de départ</Kicker>
      <Titre at={0.2} end={BUILT - 0.5} lines={["Un fork", "de Coucou."]} sub={COUCOU} size={m.wide ? 120 : 110} />
      <Plan take="lancement" source={0.7} crop={REVEIL} from={0.4} to={BUILT - 0.3} />
      <Legende at={0.5} end={BUILT - 0.3}>Début octobre, je pars d'un fork de Coucou, sous licence MIT, crédité.</Legende>

      {/* 02. What was built, one beat at a time, numbered like a contents page */}
      <Kicker at={BUILT + 0.1} end={FIGURES - 0.5}>02 · Ce qui a été construit</Kicker>
      <Titre at={BUILT + 0.15} end={ITEMS - 0.3} lines={["En quelques", "jours."]} size={m.wide ? 120 : 110} />
      <Legende at={BUILT + 0.2} end={ITEMS - 0.1}>Depuis, voilà ce qui a été construit.</Legende>

      {[
        { lines: ["Un personnage", "dessiné en code."], legende: "D'abord, un personnage dessiné en code." },
        { lines: ["L'île,", "dans la notch."], legende: "Il vit dans l'île, sous la notch." },
        { lines: ["Claude Code,", "l'accord depuis", "la notch."], legende: "Il suit mes sessions Claude Code. J'accorde depuis la notch." },
        { lines: ["Un agent qui", "propose un plan."], legende: "Un agent propose un plan avant d'agir." },
        {
          lines: ["Une seule", "porte."],
          sub: "Le Permission System : le risque est décidé par le code.",
          legende: "Chaque action passe par la même porte, puis elle est vérifiée.",
        },
        { lines: ["6 actions."], sub: "Fichier · ajout à un fichier · rappel · agenda · focus · résumé du jour et temps libre", legende: "Six actions, du fichier au résumé du jour et au temps libre." },
        { lines: ["Les modules."], sub: "Musique · agenda · rappels · météo · GitHub", legende: "Des modules : musique, agenda, rappels, météo, GitHub." },
        { lines: ["Une mémoire", "locale.", "L'initiative."], legende: "Une mémoire qui reste sur le Mac, et il prend l'initiative." },
        { lines: ["5 moteurs."], legende: "Cinq moteurs au choix." },
        { lines: ["Anglais", "et français."], sub: "Des réglages refaits.", legende: "En anglais et en français, avec des réglages refaits." },
      ].map((item, i) => (
        <React.Fragment key={item.lines.join()}>
          <Folio at={at(i) + 0.05} end={at(i + 1) - 0.25}>{`${String(i + 1).padStart(2, "0")} / 10`}</Folio>
          <Titre at={at(i)} end={at(i + 1) - 0.3} lines={item.lines} sub={item.sub} />
          <Legende at={at(i) + 0.1} end={at(i + 1) - 0.05}>{item.legende}</Legende>
          <Son name="tick" at={at(i)} volume={0.18} />
        </React.Fragment>
      ))}

      {/* The right column of chapter 02 */}
      <Scene from={at(0)} to={at(1)}>
        <Yumi script={ARRIVEE} size={yumiSize} style={{ position: "absolute", left: (stageW - yumiSize) / 2, top: (m.stage.h - yumiSize * 0.84) / 2 }} />
      </Scene>
      <Plan take="apercu" source={2.4} crop={ILE} from={at(1)} to={at(2)} stays bleed="left" />
      <Plan take="ile" source={2.9} crop={ILE} from={at(2)} to={at(3)} stays />
      <Plan take="ile" source={19.4} crop={ILE} from={at(3)} to={at(4)} stays bleed="left" />
      <Plan take="ile" source={22.2} crop={ILE} from={at(4)} to={at(5)} stays />
      <Plan take="journee-temps-libre" source={1.0} crop={JOURNEE} from={at(5)} to={at(6)} stays bleed="left" />
      <Plan take="ile" source={13.6} crop={ILE} from={at(6)} to={at(7)} stays />
      <Plan take="ile" source={28.6} crop={ILE} from={at(7)} to={at(8)} bleed="left" />
      <Scene from={at(8)} to={at(9)}>
        <Words
          lines={["Claude Code", "Anthropic", "OpenAI", "Gemini", "Ollama"]}
          enter={0.15}
          exit={BEAT - 0.4}
          stagger={0.08}
          size={m.wide ? 64 : 58}
          style={{ textAlign: m.wide ? "left" : "right", fontWeight: 700, color: P.ink, lineHeight: 1.04 }}
        />
      </Scene>
      <Scene from={at(9)} to={FIGURES - 0.1}>
        <Words
          lines={["English.", "Français."]}
          enter={0.15}
          exit={FIGURES - at(9) - 0.5}
          size={m.wide ? 120 : 104}
          style={{ textAlign: m.wide ? "left" : "right", fontWeight: 800, color: P.ink, lineHeight: 1.0 }}
        />
      </Scene>

      {/* 03. The figures, on the matcha page */}
      <Kicker at={FIGURES + 0.2} end={HOW - 0.5}>03 · En chiffres</Kicker>
      {CHIFFRES.map((c, i) => (
        <Chiffre key={c.label} i={i} />
      ))}
      <Legende at={FIGURES + 0.4} end={WAVES[1] - 0.1}>206 commits, environ 27 000 lignes de Swift, 778 tests.</Legende>
      <Legende at={WAVES[1]} end={WAVES[2] - 0.1}>2 alphas publiées, environ 6 % de code d'origine restant, un site.</Legende>
      <Legende at={WAVES[2]} end={HOW - 0.2}>4 vidéos, environ 40 000 impressions sur le premier post, 11 étoiles.</Legende>

      {/* 04. How: sessions in parallel, one that coordinates */}
      <Kicker at={HOW + 0.1} end={NEXT - 0.5}>04 · Comment</Kicker>
      <Titre at={HOW + 0.15} end={MERGE - 0.3} lines={["Plusieurs sessions", "en parallèle."]} size={m.wide ? 84 : 72} />
      <Titre at={MERGE} end={NEXT - 0.5} lines={["Une qui coordonne", "et fusionne."]} size={m.wide ? 84 : 72} />
      <Branches />
      <Legende at={HOW + 0.2} end={MERGE - 0.1}>Plusieurs sessions Claude Code travaillent en parallèle.</Legende>
      <Legende at={MERGE} end={NEXT - 0.2}>Une session de coordination tient les contrats et fusionne.</Legende>

      {/* 05. What comes next */}
      <Kicker at={NEXT + 0.1} end={END - 0.5}>05 · La suite</Kicker>
      <Titre at={NEXT + 0.15} end={NEXT + 2.2} lines={["Les retours", "de l'alpha."]} />
      <Scene from={NEXT + 0.2} to={NEXT + 2.5}>
        <Yumi script={ECOUTE} size={yumiSize} style={{ position: "absolute", left: (stageW - yumiSize) / 2, top: (m.stage.h - yumiSize * 0.84) / 2 }} />
      </Scene>
      <Titre at={NEXT + 2.5} end={END - 0.4} lines={["Lire,", "puis agir."]} sub="Un aperçu du plan avant d'agir." />
      <Scene from={NEXT + 2.8} to={END - 0.2}>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: m.wide ? 150 : 120,
            fontFamily: THEME.text,
            fontSize: m.wide ? 70 : 64,
            whiteSpace: "nowrap",
            fontWeight: 700,
            fontStyle: "italic",
            letterSpacing: "-0.02em",
            textAlign: m.wide ? "left" : "right",
            color: P.ink,
            clipPath: `inset(-20px ${(1 - ease(t, NEXT + 2.9, NEXT + 3.6, EASE.out)) * 100}% -20px 0)`,
          }}
        >
          «{" "}Prépare ma journée.{" "}»
        </div>
      </Scene>
      <Legende at={NEXT + 0.2} end={NEXT + 2.45}>La suite : les retours de l'alpha.</Legende>
      <Legende at={NEXT + 2.5} end={END - 0.2}>Puis « lire puis agir » : prépare ma journée, avec un aperçu du plan.</Legende>

      <Pied
        lines={[
          { at: 0.8, end: FIGURES - 0.2, text: "Prises réelles de l'app · mode tournage, données d'exemple" },
          { at: HOW + 0.5, end: NEXT - 0.2, text: "Branches réelles du dépôt" },
        ]}
      />

      {/* The end: the name set large on the left, him on the right */}
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <Yumi
          script={FIN}
          size={m.wide ? 420 : 380}
          style={{ position: "absolute", right: m.wide ? 160 : 60, top: m.wide ? 200 : 120 }}
        />
        <div style={{ position: "absolute", left: m.margin - 14, top: m.wide ? 300 : 560 }}>
          <Words lines={["Yumi."]} by="letter" enter={0.3} size={m.wide ? 280 : 300} style={{ textAlign: "left", fontWeight: 800, color: P.ink }} />
        </div>
        <div style={{ position: "absolute", left: m.margin, top: m.wide ? 640 : 900 }}>
          <Words lines={["Alpha gratuite."]} enter={0.8} size={m.wide ? 64 : 62} style={{ textAlign: "left", fontWeight: 700, color: P.ink }} />
          <div
            style={{
              marginTop: 18,
              fontFamily: P.mono,
              fontSize: m.wide ? 40 : 36,
              color: P.soft,
              clipPath: `inset(0 ${(1 - interpolate(t - END, [1.2, 2.0], [0, 1], { ...CLAMP, easing: EASE.out })) * 100}% 0 0)`,
            }}
          >
            github.com/estebanbaigts/Yumi
          </div>
        </div>
      </Sequence>

      <Son name="pop" at={0.5} volume={0.35} />
      <Son name="pop" at={FIGURES} volume={0.4} />
      {WAVES.map((w) => (
        <Son key={w} name="tick" at={w} volume={0.25} />
      ))}
      <Son name="finish" at={MERGE + 0.8} volume={0.45} />
      <Son name="pop" at={NEXT} volume={0.35} />
      <Son name="wink" at={END + 1.4} volume={0.6} />
    </AbsoluteFill>
  );
};
