import React from "react";
import { AbsoluteFill, Sequence, interpolate, useVideoConfig } from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { CLAMP, Folio, Kicker, Legende, P, Pied, Plan, Titre, ease, useMise, useT, type Rect } from "./page";
import { TEXTE, type Langue, type Texte } from "./texte";

// A recap of the project, in under a minute, set as a magazine page (JourneeEdito's paper,
// large type, the matcha page). Five numbered chapters, like a table of contents: where it
// started, what was built, the figures, how, what comes next.
//
// One film, two languages (texte.ts), four frames: 16:9 and 4:5 for the feeds (LinkedIn,
// Reddit, X), and a 9:16 reel for Instagram and TikTok that opens on a two-second hook.
//
// Nothing is invented. The figures were checked against the repository on 6 October 2026
// (commits, Swift lines outside the tests, tests, the share of lines unchanged since the
// Coucou import, published releases, stars); the reach of the first post is the one LinkedIn
// gave. The images of the island are the real takes of public/prises, filmed with the app in
// French; the branches of chapter 04 are branches of the repository.

export const RECAP_LENGTH = 58.6;
/** The reel's hook, before the recap. */
const OPEN = 2.6;
export const REEL_LENGTH = OPEN + RECAP_LENGTH;

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
const SORTIE: YumiScript = {
  seed: 504,
  cues: [
    { at: 0, mood: "surprised", rim: "joy", pose: "pop" },
    { at: 0.7, mood: "happy", pose: "wave" },
  ],
};

const WAVES = [FIGURES + 0.5, FIGURES + 4.1, FIGURES + 7.7];

/** One figure: it counts up to its value, its label opens under it. */
const Chiffre: React.FC<{ readonly i: number; readonly tx: Texte }> = ({ i, tx }) => {
  const t = useT();
  const m = useMise();
  const c = tx.chiffres.list[i];
  const start = WAVES[Math.floor(i / 3)] + (i % 3) * 0.22;
  const k = ease(t, start, start + 1.1, EASE.out);
  const show = ease(t, start, start + 0.3) * (1 - ease(t, HOW - 0.45, HOW - 0.1, EASE.in));
  // Three columns across the wide page, two down the others
  const cols = m.wide ? 3 : 2;
  const col = i % cols;
  const row = Math.floor(i / cols);
  const cell = m.wide
    ? { x: m.margin + col * 580, y: 190 + row * 220, w: 540 }
    : m.tall
      ? { x: m.margin + col * 430, y: 330 + row * 168, w: 410 }
      : { x: m.margin + col * 480, y: 200 + row * 152, w: 440 };
  const size = m.wide ? 120 : m.tall ? 86 : 84;
  return (
    <div style={{ position: "absolute", left: cell.x, top: cell.y, width: cell.w, opacity: show, translate: `0 ${(1 - k) * 30}px` }}>
      <div style={{ fontFamily: THEME.text, fontSize: size, fontWeight: 800, letterSpacing: "-0.04em", lineHeight: 1, color: P.ink, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
        {c.about ? <span style={{ fontWeight: 600, color: P.soft, marginRight: "0.08em" }}>≈</span> : null}
        {tx.groupe(Math.round(c.n * k))}
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
    ? { label: m.margin, start: 470, bend: 1240, merge: 1500, end: m.W - m.right, top: 418, gap: 42, font: 25 }
    : m.tall
      ? { label: m.margin, start: 350, bend: 640, merge: 790, end: m.W - m.right, top: 560, gap: 54, font: 23 }
      : { label: m.margin, start: 360, bend: 700, merge: 860, end: m.W - m.right, top: 420, gap: 47, font: 22 };
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
      <div style={{ position: "absolute", right: m.right, top: mid - g.font * 2.6, fontFamily: P.mono, fontSize: g.font + 4, fontWeight: 700, color: P.ink, opacity: main }}>main</div>
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
      <div style={{ position: "absolute", left: m.stage.x, top: m.stage.y, width: m.wide ? m.stage.w - m.margin : m.W - m.margin - m.right, height: m.stage.h, opacity: k }}>
        {children}
      </div>
    </Sequence>
  );
};

/** The recap itself, 58.6 seconds, in one language. */
const Corps: React.FC<{ readonly langue: Langue }> = ({ langue }) => {
  const tx = TEXTE[langue];
  const m = useMise();
  const t = useT();
  const { fps } = useVideoConfig();
  const stageW = m.wide ? m.stage.w - m.margin : m.W - m.margin - m.right;
  const yumiSize = m.wide ? 340 : 300;
  const align = m.wide ? "left" : "right";

  // The matcha page climbs for the figures, and leaves through the top
  const up = ease(t, FIGURES - 0.2, FIGURES + 0.4);
  const off = ease(t, HOW - 0.4, HOW + 0.15);

  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <div style={{ position: "absolute", inset: 0, backgroundColor: P.matcha, clipPath: `inset(${(1 - up) * 100}% 0 ${off * 100}% 0)` }} />

      {/* 01. Where it started */}
      <Kicker at={0.1} end={BUILT - 0.5}>{tx.depart.kicker}</Kicker>
      <Titre at={0.2} end={BUILT - 0.5} lines={tx.depart.lines} sub={tx.depart.sub} size={m.wide ? 120 : 110} />
      <Plan take="lancement" source={0.7} crop={REVEIL} from={0.4} to={BUILT - 0.3} />
      <Legende at={0.5} end={BUILT - 0.3}>{tx.depart.legende}</Legende>

      {/* 02. What was built, one beat at a time, numbered like a contents page */}
      <Kicker at={BUILT + 0.1} end={FIGURES - 0.5}>{tx.construit.kicker}</Kicker>
      <Titre at={BUILT + 0.15} end={ITEMS - 0.3} lines={tx.construit.lines} size={m.wide ? 120 : 110} />
      <Legende at={BUILT + 0.2} end={ITEMS - 0.1}>{tx.construit.legende}</Legende>

      {tx.construit.items.map((item, i) => (
        <React.Fragment key={item.lines.join()}>
          <Folio at={at(i) + 0.05} end={at(i + 1) - 0.25}>{`${String(i + 1).padStart(2, "0")} / ${tx.construit.items.length}`}</Folio>
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
          style={{ textAlign: align, fontWeight: 700, color: P.ink, lineHeight: 1.04 }}
        />
      </Scene>
      <Scene from={at(9)} to={FIGURES - 0.1}>
        <Words lines={tx.construit.langues} enter={0.15} exit={FIGURES - at(9) - 0.5} size={m.wide ? 120 : 104} style={{ textAlign: align, fontWeight: 800, color: P.ink, lineHeight: 1.0 }} />
      </Scene>

      {/* 03. The figures, on the matcha page */}
      <Kicker at={FIGURES + 0.2} end={HOW - 0.5}>{tx.chiffres.kicker}</Kicker>
      {tx.chiffres.list.map((c, i) => (
        <Chiffre key={c.label} i={i} tx={tx} />
      ))}
      <Legende at={FIGURES + 0.4} end={WAVES[1] - 0.1}>{tx.chiffres.legendes[0]}</Legende>
      <Legende at={WAVES[1]} end={WAVES[2] - 0.1}>{tx.chiffres.legendes[1]}</Legende>
      <Legende at={WAVES[2]} end={HOW - 0.2}>{tx.chiffres.legendes[2]}</Legende>

      {/* 04. How: sessions in parallel, one that coordinates */}
      <Kicker at={HOW + 0.1} end={NEXT - 0.5}>{tx.comment.kicker}</Kicker>
      <Titre at={HOW + 0.15} end={MERGE - 0.3} lines={tx.comment.avant} size={m.wide ? 84 : 72} />
      <Titre at={MERGE} end={NEXT - 0.5} lines={tx.comment.apres} size={m.wide ? 84 : 72} />
      <Branches />
      <Legende at={HOW + 0.2} end={MERGE - 0.1}>{tx.comment.legendes[0]}</Legende>
      <Legende at={MERGE} end={NEXT - 0.2}>{tx.comment.legendes[1]}</Legende>

      {/* 05. What comes next */}
      <Kicker at={NEXT + 0.1} end={END - 0.5}>{tx.suite.kicker}</Kicker>
      <Titre at={NEXT + 0.15} end={NEXT + 2.2} lines={tx.suite.retours} />
      <Scene from={NEXT + 0.2} to={NEXT + 2.5}>
        <Yumi script={ECOUTE} size={yumiSize} style={{ position: "absolute", left: (stageW - yumiSize) / 2, top: (m.stage.h - yumiSize * 0.84) / 2 }} />
      </Scene>
      <Titre at={NEXT + 2.5} end={END - 0.4} lines={tx.suite.agir} sub={tx.suite.agirSub} />
      <Scene from={NEXT + 2.8} to={END - 0.2}>
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            top: m.wide ? 150 : 120,
            fontFamily: THEME.text,
            fontSize: m.wide ? 70 : 64,
            fontWeight: 700,
            fontStyle: "italic",
            letterSpacing: "-0.02em",
            whiteSpace: "nowrap",
            textAlign: align,
            color: P.ink,
            clipPath: `inset(-20px ${(1 - ease(t, NEXT + 2.9, NEXT + 3.6, EASE.out)) * 100}% -20px 0)`,
          }}
        >
          {tx.suite.citation}
        </div>
      </Scene>
      <Legende at={NEXT + 0.2} end={NEXT + 2.45}>{tx.suite.legendes[0]}</Legende>
      <Legende at={NEXT + 2.5} end={END - 0.2}>{tx.suite.legendes[1]}</Legende>

      <Pied
        lines={[
          { at: 0.8, end: FIGURES - 0.2, text: tx.pied.prises },
          { at: HOW + 0.5, end: NEXT - 0.2, text: tx.pied.branches },
        ]}
      />

      {/* The end: the name set large on the left, him on the right */}
      <Sequence from={Math.round(END * fps)} premountFor={fps}>
        <Yumi
          script={FIN}
          size={m.wide ? 420 : 380}
          style={{ position: "absolute", right: m.wide ? 160 : 60, top: m.wide ? 200 : m.tall ? 300 : 120 }}
        />
        <div style={{ position: "absolute", left: m.margin - 14, top: m.wide ? 300 : m.tall ? 760 : 560 }}>
          <Words lines={["Yumi."]} by="letter" enter={0.3} size={m.wide ? 280 : 300} style={{ textAlign: "left", fontWeight: 800, color: P.ink }} />
        </div>
        <div style={{ position: "absolute", left: m.margin, top: m.wide ? 640 : m.tall ? 1100 : 900 }}>
          <Words lines={[tx.fin.alpha]} enter={0.8} size={m.wide ? 64 : 62} style={{ textAlign: "left", fontWeight: 700, color: P.ink }} />
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

/**
 * The reel's hook: the top of a screen with its notch, Yumi drops out of it, and one sentence
 * says what he is. Then the page turns to the recap.
 */
const Ouverture: React.FC<{ readonly langue: Langue }> = ({ langue }) => {
  const tx = TEXTE[langue];
  const t = useT();
  const m = useMise();
  const size = 460;
  const drop = interpolate(t, [0.15, 0.75], [-size * 0.9, 330], { ...CLAMP, easing: EASE.spring });
  const leave = ease(t, OPEN - 0.45, OPEN, EASE.in);
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <div style={{ position: "absolute", inset: 0, translate: `0 ${-leave * 140}px`, opacity: 1 - leave }}>
        <Yumi script={SORTIE} size={size} style={{ position: "absolute", left: (m.W - size) / 2, top: drop }} />
        {/* The notch, in front of him: he comes out from under it */}
        <div style={{ position: "absolute", left: (m.W - 360) / 2, top: 0, width: 360, height: 84, backgroundColor: "#000", borderRadius: "0 0 40px 40px" }} />
        <div style={{ position: "absolute", left: m.margin - 6, top: 860, width: m.W - m.margin - m.right + 60 }}>
          <Words lines={tx.ouverture.lines} enter={0.35} exit={OPEN - 0.5} stagger={0.07} size={112} style={{ textAlign: "left", fontWeight: 800, lineHeight: 1.0, color: P.ink, whiteSpace: "nowrap" }} />
        </div>
        <div
          style={{
            position: "absolute",
            left: m.margin,
            top: 1250,
            width: m.W - m.margin - m.right,
            fontFamily: THEME.text,
            fontSize: 40,
            fontWeight: 600,
            lineHeight: 1.2,
            color: P.soft,
            clipPath: `inset(0 ${(1 - ease(t, 0.9, 1.5, EASE.out)) * 100}% 0 0)`,
          }}
        >
          {tx.ouverture.sub}
        </div>
      </div>
      <Son name="pop" at={0.2} volume={0.45} />
    </AbsoluteFill>
  );
};

const Reel: React.FC<{ readonly langue: Langue }> = ({ langue }) => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <Sequence durationInFrames={Math.round(OPEN * fps)}>
        <Ouverture langue={langue} />
      </Sequence>
      <Sequence from={Math.round(OPEN * fps)}>
        <Corps langue={langue} />
      </Sequence>
    </AbsoluteFill>
  );
};

export const Recap: React.FC = () => <Corps langue="fr" />;
export const RecapEn: React.FC = () => <Corps langue="en" />;
export const ReelFr: React.FC = () => <Reel langue="fr" />;
export const ReelEn: React.FC = () => <Reel langue="en" />;
