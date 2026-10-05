import React from "react";
import { Sequence, useVideoConfig } from "remotion";
import { Son } from "../../son/Son";
import { EASE, THEME } from "../../theme";
import { Code } from "../../type/Code";
import { Words } from "../../type/Words";
import { Yumi } from "../../yumi/Yumi";
import type { YumiScript } from "../../yumi/engine";
import { Clic, Ecran, Fenetre, MONO, Plan, Rubrique, SousTitres, ease, useCadre, useT } from "./kit";

// The first half of the masterclass: what Yumi is, what he does, why you can trust him.
// Real takes from the app (its filming mode) wherever one exists.

/** 1. Hook: he lights up in the notch. Real take. */
export const ACCROCHE = 5;
export const Accroche: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const box = c.vertical ? { x: 40, y: 380, w: 1000, h: 820 } : { x: 160, y: 60, w: 1600, h: 760 };
  const zoom = 2.3 - 0.8 * ease(t, 1.45, 2.15) - 0.5 * ease(t, 3.4, 4.6);
  return (
    <Plan length={ACCROCHE}>
      {/* A little faster than life, so his light comes on at 2 s */}
      <Ecran take="lancement" source={0.72} rate={1.1} box={box} zoom={zoom} />
      <SousTitres
        lines={[
          { at: 0.15, end: 2.0, text: "Il y a un trou noir en haut de ton Mac." },
          { at: 2.1, end: 4.9, text: "Quelqu'un y habite maintenant." },
        ]}
      />
      <Son name="pop" at={0.05} volume={0.6} />
      <Son name="blip" at={0.62} volume={0.4} />
      <Son name="greet" at={2.0} volume={0.7} />
    </Plan>
  );
};

/** 2. What he is, in one sentence. */
export const PRESENTATION = 6;
const SALUT: YumiScript = {
  seed: 201,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 0.7, pose: "wave" },
    { at: 3.2, mood: "wink", rim: "calm" },
    { at: 3.8, mood: "happy" },
  ],
};
export const Presentation: React.FC = () => {
  const c = useCadre();
  const align = c.vertical ? "center" : "left";
  return (
    <Plan length={PRESENTATION}>
      <Yumi
        script={SALUT}
        size={c.vertical ? 600 : 560}
        style={{ position: "absolute", left: c.vertical ? 240 : 230, top: c.vertical ? 380 : 260 }}
      />
      <div style={{ position: "absolute", left: c.vertical ? 60 : 900, top: c.vertical ? 1000 : 300, width: c.vertical ? 960 : 900 }}>
        <Words lines={["Yumi."]} by="letter" enter={0.2} size={c.vertical ? 170 : 170} style={{ fontWeight: 700, textAlign: align }} />
        <Words
          lines={c.vertical ? ["Un compagnon qui vit", "dans la notch de ton Mac."] : ["Un compagnon qui vit", "dans la notch de ton Mac."]}
          enter={0.7}
          size={c.vertical ? 62 : 60}
          style={{ textAlign: align, marginTop: 18, lineHeight: 1.15 }}
        />
        <div
          style={{
            marginTop: 34,
            textAlign: align,
            fontFamily: MONO,
            fontSize: c.vertical ? 32 : 30,
            color: THEME.muted,
            opacity: ease(useT(), 1.4, 1.9),
          }}
        >
          0.1.0-alpha · open source · macOS 15+
        </div>
      </div>
      <Son name="greet" at={0.7} volume={0.6} />
    </Plan>
  );
};

/** 3a. Claude Code sessions, and approving from the notch. Real take. */
export const SESSIONS = 9;
export const Sessions: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const box = c.stage;
  const s = box.w / 1680;
  // The green button of the permission, in the take
  const green = [1402 * s, 166 * s] as const;
  const zoom = 1 + 0.22 * ease(t, 1.5, 2.3) - 0.22 * ease(t, 2.95, 3.6);
  return (
    <Plan length={SESSIONS}>
      <Rubrique>Ce qu'il fait</Rubrique>
      <Ecran take="ile" source={0.95} box={box} focus={green} zoom={zoom}>
        <Clic x={green[0]} y={green[1]} at={2.58} colour="#3DDC97" />
      </Ecran>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.0, text: "Il suit tes sessions Claude Code, dans tous tes terminaux." },
          { at: 3.0, end: 6.2, text: "Quand l'une demande une permission, tu réponds depuis la notch." },
          { at: 6.2, end: 8.8, text: "Sans changer de fenêtre." },
        ]}
      />
      <Son name="approval" at={0.25} volume={0.6} />
      <Son name="approve" at={2.6} volume={0.7} />
      <Son name="finish" at={2.9} volume={0.6} />
    </Plan>
  );
};

/** 3b. You talk, he acts: a real take of the chat, then everything else he can do. */
export const ACTIONS = 14;
const LISTE = ["Créer un fichier", "Y ajouter une ligne", "Ajouter un rappel", "Bloquer un créneau dans ton agenda", "Lancer un focus", "Résumer ta journée"];
const ATTENTIF: YumiScript = {
  seed: 202,
  cues: [
    { at: 0, mood: "focused", rim: "work" },
    { at: 8.3, mood: "happy", rim: "done", pose: "pop" },
    { at: 11.4, mood: "wink" },
    { at: 12.0, mood: "happy" },
  ],
};
export const Actions: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const { fps } = useVideoConfig();
  const listAt = 8.4;
  return (
    <Plan length={ACTIONS}>
      <Rubrique>Ce qu'il fait</Rubrique>
      <Sequence durationInFrames={Math.round(8.3 * fps)} layout="none">
        <Ecran take="ile" source={16.3} box={c.stage} opacity={1 - ease(t, 7.9, 8.3)} />
      </Sequence>
      <Sequence from={Math.round(8.0 * fps)} layout="none">
        <div style={{ opacity: ease(t, 8.0, 8.5) }}>
          <Yumi
            script={ATTENTIF}
            size={c.vertical ? 420 : 380}
            style={{ position: "absolute", left: c.vertical ? 330 : 250, top: c.vertical ? 400 : 250 }}
          />
          <div style={{ position: "absolute", left: c.vertical ? 120 : 760, top: c.vertical ? 790 : 190 }}>
            {LISTE.map((item, i) => {
              const at = listAt + 0.35 + i * 0.42;
              const k = ease(t, at, at + 0.4, EASE.out);
              const tick = ease(t, at + 0.25, at + 0.6);
              return (
                <div
                  key={item}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 26,
                    height: c.vertical ? 82 : 86,
                    opacity: k,
                    translate: `${(1 - k) * 30}px 0`,
                    fontFamily: THEME.text,
                    fontSize: c.vertical ? 46 : 48,
                    fontWeight: 600,
                    color: THEME.fg,
                  }}
                >
                  <svg width={40} height={40} viewBox="0 0 40 40">
                    <circle cx={20} cy={20} r={18} fill="none" stroke="rgba(61,220,151,0.35)" strokeWidth={2.5} />
                    <path d="M11 20.5L17.5 27L29 14" fill="none" stroke="#3DDC97" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" pathLength={1} strokeDasharray={`${tick} 1`} />
                  </svg>
                  {item}
                </div>
              );
            })}
          </div>
        </div>
      </Sequence>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.4, text: "Tu lui parles. Il agit." },
          { at: 3.4, end: 7.9, text: "Ici, il écrit un fichier dans tes Téléchargements." },
          { at: 8.4, end: 13.8, text: "Avant de créer ou de modifier quoi que ce soit, il te demande ton accord." },
        ]}
      />
      <Son name="send" at={0.4} volume={0.5} />
      <Son name="attach" at={5.4} volume={0.6} />
      {LISTE.map((item, i) => (
        <Son key={item} name="tick" at={listAt + 0.6 + i * 0.42} volume={0.25} />
      ))}
    </Plan>
  );
};

/** 3c. One activity at a time: the overview, the music, GitHub. Real takes. */
export const ACTIVITES = 14;
export const Activites: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const { fps } = useVideoConfig();
  const fade = (a: number, b: number) => ease(t, a, a + 0.25) * (1 - ease(t, b - 0.25, b));
  return (
    <Plan length={ACTIVITES}>
      <Rubrique>Ce qu'il fait</Rubrique>
      <Sequence durationInFrames={Math.round(7.2 * fps)} layout="none">
        <Ecran take="apercu" source={1.8} box={c.stage} opacity={fade(-1, 7.2)} />
      </Sequence>
      <Sequence from={Math.round(7.0 * fps)} durationInFrames={Math.round(3.7 * fps)} layout="none">
        <Ecran take="ile" source={10.85} box={c.stage} opacity={fade(7.0, 10.7)} focus={[c.stage.w * 0.1, 0]} zoom={1 + 0.25 * ease(t, 7.6, 10.4)} />
      </Sequence>
      <Sequence from={Math.round(10.5 * fps)} layout="none">
        <Ecran take="github" source={1.2} box={c.stage} opacity={fade(10.5, 99)} />
      </Sequence>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.6, text: "Ta musique, ton agenda, la météo, tes rappels, GitHub." },
          { at: 3.6, end: 7.0, text: "Une seule chose à la fois : celle qui compte maintenant." },
          { at: 7.1, end: 10.4, text: "Il écoute avec toi." },
          { at: 10.6, end: 13.8, text: "Et il a une petite scène pour chaque événement GitHub." },
        ]}
      />
      <Son name="blip" at={7.1} volume={0.4} />
      <Son name="wink" at={11.6} volume={0.5} />
    </Plan>
  );
};

/** 3d. He speaks first (real take), and he remembers, on your Mac (recreated). */
export const MEMOIRE = 10;
const NOTE = ["# Alex", "", "## Toi", "- Préfère les réponses courtes.", "", "## Tes projets", "- Atelier : une page d'accueil plus calme.", "", "## Le fil", "- Point produit mardi, à 14:30."];
export const Memoire: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const { fps } = useVideoConfig();
  const win = c.vertical ? { x: 60, y: 430, w: 960, h: 760 } : { x: 400, y: 120, w: 1120, h: 680 };
  return (
    <Plan length={MEMOIRE}>
      <Rubrique>Ce qu'il fait</Rubrique>
      <Sequence durationInFrames={Math.round(4.0 * fps)} layout="none">
        <Ecran take="ile" source={26.4} box={c.stage} opacity={1 - ease(t, 3.6, 4.0)} zoom={1 + 0.9 * ease(t, 0.5, 1.6)} />
      </Sequence>
      <Sequence from={Math.round(3.8 * fps)} layout="none">
        <div style={{ opacity: ease(t, 3.8, 4.2), translate: `0 ${(1 - ease(t, 3.8, 4.4, EASE.out)) * 30}px` }}>
          <Fenetre title="memoire.md" box={win}>
            <Code lines={NOTE} start={0.3} speed={70} size={c.vertical ? 32 : 32} style={{ position: "absolute", left: 20, top: 26 }} />
          </Fenetre>
        </div>
      </Sequence>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.6, text: "Il parle le premier. Rarement, et à propos." },
          { at: 4.0, end: 7.0, text: "Il retient ce que tu lui dis, dans un fichier texte sur ton Mac." },
          { at: 7.0, end: 9.8, text: "Tu peux tout lire, corriger ou effacer." },
        ]}
      />
      <Son name="peek" at={0.7} volume={0.6} />
    </Plan>
  );
};

/** 4. Trust. */
export const CONFIANCE = 9;
const PROMESSES = ["Rien sans ton accord.", "Pas de compte.", "Pas de télémétrie.", "Tes données restent sur ton Mac."];
export const Confiance: React.FC = () => {
  const c = useCadre();
  const t = useT();
  return (
    <Plan length={CONFIANCE}>
      <Rubrique>Confiance</Rubrique>
      <div style={{ position: "absolute", left: 0, right: 0, top: c.vertical ? 520 : 200 }}>
        {PROMESSES.map((p, i) => {
          const at = 0.4 + i * 0.85;
          const k = ease(t, at, at + 0.5, EASE.out);
          return (
            <div
              key={p}
              style={{
                textAlign: "center",
                fontFamily: THEME.text,
                fontSize: c.vertical ? 64 : 84,
                fontWeight: 700,
                letterSpacing: "-0.025em",
                lineHeight: c.vertical ? 1.5 : 1.45,
                color: THEME.fg,
                opacity: k,
                translate: `0 ${(1 - k) * 26}px`,
              }}
            >
              {p}
            </div>
          );
        })}
      </div>
      <div
        style={{
          position: "absolute",
          left: (c.W - c.captionW) / 2,
          width: c.captionW,
          top: c.vertical ? 1300 : 860,
          textAlign: "center",
          fontFamily: THEME.text,
          fontSize: c.vertical ? 40 : 36,
          fontWeight: 500,
          color: THEME.muted,
          opacity: ease(t, 4.2, 4.8),
        }}
      >
        Seuls les services que tu actives sont contactés : la météo, GitHub, Claude Code.
      </div>
      {PROMESSES.map((p, i) => (
        <Son key={p} name="tick" at={0.45 + i * 0.85} volume={0.3} />
      ))}
    </Plan>
  );
};
