import React from "react";
import { Sequence, interpolate, useVideoConfig } from "remotion";
import { Son } from "../../son/Son";
import { EASE, THEME } from "../../theme";
import { Words } from "../../type/Words";
import { Yumi } from "../../yumi/Yumi";
import type { YumiScript } from "../../yumi/engine";
import { Bouton, CLAMP, Chiffre, Clic, Ecran, Fenetre, MONO, Plan, Pointeur, Rubrique, SousTitres, ease, useCadre, useT } from "./kit";

// The second half: installing the alpha, one scene per step with its number in sight, then
// where to get it and how to send feedback. The windows of macOS are drawn plainly: they
// say where to click, they do not imitate the system pixel for pixel.

/** Where the step number and the window go. */
const useEtape = () => {
  const c = useCadre();
  return {
    c,
    number: c.vertical ? { x: 440, y: 250, size: 200 } : { x: 120, y: 330, size: 250 },
    win: c.vertical ? { x: 60, y: 560, w: 960, h: 680 } : { x: 520, y: 120, w: 1240, h: 690 },
  };
};

/** The pointer's path: from `a` to `b` between two times, eased. */
const path = (t: number, a: readonly [number, number], b: readonly [number, number], from: number, to: number) => {
  const k = ease(t, from, to);
  return [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k] as const;
};

/** Pressed: 1 for a moment around a click. */
const press = (t: number, at: number) => interpolate(t, [at - 0.08, at, at + 0.16], [0, 1, 0], CLAMP);

/** Install, intro. */
export const INSTALLER = 2.6;
export const Installer: React.FC = () => {
  const c = useCadre();
  return (
    <Plan length={INSTALLER}>
      <Rubrique>Installation</Rubrique>
      <div style={{ position: "absolute", left: 0, right: 0, top: c.vertical ? 760 : 380 }}>
        <Words lines={["Installer l'alpha."]} enter={0.15} size={c.vertical ? 104 : 120} style={{ fontWeight: 700 }} />
        <Words lines={["Cinq étapes."]} enter={0.55} size={c.vertical ? 56 : 56} style={{ color: THEME.muted, marginTop: 16 }} />
      </div>
    </Plan>
  );
};

/** Step 1: download the zip from the release page. */
export const ETAPE1 = 7;
const ASSETS = ["Yumi-0.1.0-alpha.zip", "Source code (zip)", "Source code (tar.gz)"];
export const Etape1: React.FC = () => {
  const { number, win } = useEtape();
  const t = useT();
  const row0 = { x: 48, y: 330 };
  const click = 2.4;
  const [px, py] = path(t, [win.w * 0.8, win.h * 0.85], [row0.x + 230, row0.y + 22], 0.9, 2.2);
  const progress = ease(t, click + 0.2, click + 1.8, EASE.out);
  return (
    <Plan length={ETAPE1}>
      <Chiffre n={1} {...number} />
      <Fenetre title="github.com/estebanbaigts/Yumi/releases" box={win}>
        <div style={{ position: "absolute", left: 48, top: 40, display: "flex", alignItems: "center", gap: 20 }}>
          <span style={{ fontSize: 46, fontWeight: 700, letterSpacing: "-0.02em" }}>Yumi 0.1.0-alpha</span>
          <span style={{ fontSize: 20, fontWeight: 600, color: "#FFB547", border: "2px solid rgba(255,181,71,0.6)", borderRadius: 999, padding: "4px 14px" }}>Pre-release</span>
        </div>
        {[0, 1, 2].map((i) => (
          <div key={i} style={{ position: "absolute", left: 48, top: 130 + i * 30, width: [620, 540, 380][i], height: 12, borderRadius: 6, backgroundColor: "rgba(255,255,255,0.07)" }} />
        ))}
        <div style={{ position: "absolute", left: 48, top: 270, fontSize: 26, fontWeight: 700, color: THEME.muted }}>Assets</div>
        {ASSETS.map((a, i) => (
          <div
            key={a}
            style={{
              position: "absolute",
              left: 32,
              right: 32,
              top: row0.y - 12 + i * 70,
              height: 60,
              display: "flex",
              alignItems: "center",
              gap: 16,
              padding: "0 16px",
              borderRadius: 12,
              backgroundColor: i === 0 ? `rgba(91,140,255,${0.08 + 0.14 * ease(t, 1.9, 2.3)})` : "transparent",
              fontFamily: i === 0 ? MONO : THEME.text,
              fontSize: 26,
              fontWeight: i === 0 ? 600 : 500,
              color: i === 0 ? "#9FBBFF" : THEME.muted,
            }}
          >
            <span style={{ width: 22, height: 26, borderRadius: 4, border: `2px solid ${i === 0 ? "#9FBBFF" : THEME.faint}` }} />
            {a}
          </div>
        ))}
        {/* The download */}
        <div style={{ position: "absolute", left: 48, right: 48, bottom: 48, opacity: ease(t, click + 0.15, click + 0.35) }}>
          <div style={{ fontSize: 24, color: THEME.muted, marginBottom: 12 }}>
            {progress < 1 ? "Téléchargement…" : "Yumi-0.1.0-alpha.zip, dans Téléchargements"}
          </div>
          <div style={{ height: 10, borderRadius: 5, backgroundColor: "rgba(255,255,255,0.08)" }}>
            <div style={{ width: `${progress * 100}%`, height: "100%", borderRadius: 5, backgroundColor: progress < 1 ? "#5B8CFF" : "#3DDC97" }} />
          </div>
        </div>
        <Clic x={px} y={py} at={click} />
        <Pointeur x={px} y={py} press={press(t, click)} />
      </Fenetre>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.6, text: "Sur la page de la release, télécharge Yumi-0.1.0-alpha.zip." },
          { at: 3.6, end: 6.8, text: "github.com/estebanbaigts/Yumi, onglet Releases." },
        ]}
      />
      <Son name="tick" at={click} volume={0.4} />
      <Son name="approve" at={click + 1.8} volume={0.4} />
    </Plan>
  );
};

/** The app icon: Yumi on a black rounded square. */
const ICONE: YumiScript = { seed: 211, cues: [{ at: 0, mood: "neutral", rim: "calm" }] };
const Icone: React.FC<{ readonly size: number }> = ({ size }) => (
  <div style={{ width: size, height: size, borderRadius: size * 0.23, backgroundColor: "#000", boxShadow: "0 0 0 1.5px rgba(255,255,255,0.12)", position: "relative", overflow: "hidden" }}>
    <Yumi script={ICONE} size={size * 0.86} style={{ position: "absolute", left: size * 0.07, top: size * 0.2 }} />
  </div>
);

/** Step 2: unzip, drag Yumi into Applications. */
export const ETAPE2 = 7;
const LIEUX = ["Applications", "Bureau", "Documents", "Téléchargements"];
export const Etape2: React.FC = () => {
  const { number, win } = useEtape();
  const t = useT();
  const side = 300;
  const iconAt = { x: side + 120, y: 150 };
  const target = { x: 40, y: 100 + 0 * 64 };
  const grab = 1.9;
  const drop = 3.6;
  const drag = ease(t, grab + 0.15, drop);
  const ix = iconAt.x + (target.x + 60 - iconAt.x) * drag;
  const iy = iconAt.y + (target.y - 30 - iconAt.y) * drag;
  const [px, py] = t < grab ? path(t, [win.w * 0.75, win.h * 0.8], [iconAt.x + 70, iconAt.y + 70], 0.9, grab) : ([ix + 70, iy + 70] as const);
  const over = ease(t, drop - 0.5, drop - 0.2);
  const done = ease(t, drop, drop + 0.3);
  return (
    <Plan length={ETAPE2}>
      <Chiffre n={2} {...number} />
      <Fenetre title="Téléchargements" box={win}>
        <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: side, backgroundColor: "#13151B", borderRight: "1px solid rgba(255,255,255,0.05)" }}>
          <div style={{ padding: "26px 26px 10px", fontSize: 20, fontWeight: 700, color: THEME.faint }}>Favoris</div>
          {LIEUX.map((l, i) => (
            <div
              key={l}
              style={{
                margin: "0 14px",
                padding: "14px 16px",
                borderRadius: 10,
                fontSize: 26,
                fontWeight: 500,
                color: i === 0 && over > 0 ? THEME.fg : THEME.muted,
                backgroundColor:
                  i === 0 ? `rgba(91,140,255,${0.45 * over * (1 - done * 0.6)})` : i === 3 ? "rgba(255,255,255,0.08)" : "transparent",
              }}
            >
              {l}
            </div>
          ))}
        </div>
        {/* The zip, then what it holds */}
        <div style={{ position: "absolute", left: side + 120 + 230, top: 150, textAlign: "center", fontSize: 22, color: THEME.muted }}>
          <div style={{ width: 140, height: 140, borderRadius: 18, border: "2px solid rgba(255,255,255,0.18)", display: "flex", alignItems: "center", justifyContent: "center", fontFamily: MONO, fontSize: 30 }}>zip</div>
          <div style={{ marginTop: 12 }}>Yumi-0.1.0-alpha.zip</div>
        </div>
        <div
          style={{
            position: "absolute",
            left: ix,
            top: iy,
            textAlign: "center",
            fontSize: 22,
            color: THEME.fg,
            opacity: ease(t, 0.5, 0.9) * (1 - done),
            scale: 1 - 0.4 * done,
          }}
        >
          <Icone size={140} />
          <div style={{ marginTop: 12, opacity: 1 - drag }}>Yumi</div>
        </div>
        <Pointeur x={px} y={py} press={press(t, grab) * 0.6} opacity={1 - ease(t, drop + 0.6, drop + 0.9)} />
      </Fenetre>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.8, text: "Ouvre le zip, puis glisse Yumi dans Applications." },
          { at: 3.8, end: 6.8, text: "Il s'installe comme n'importe quelle app." },
        ]}
      />
      <Son name="pop" at={0.55} volume={0.4} />
      <Son name="gulp" at={drop} volume={0.5} />
    </Plan>
  );
};

/** Step 3: macOS blocks it once; open it anyway from System Settings. */
export const ETAPE3 = 9.5;
const SECTIONS = ["Général", "Apparence", "Notifications", "Confidentialité et sécurité", "Écran"];
export const Etape3: React.FC = () => {
  const { c, number, win } = useEtape();
  const t = useT();
  const { fps } = useVideoConfig();
  const ok = 2.9;
  const anyway = 7.0;
  const alert = c.vertical ? { x: 140, y: 620, w: 800, h: 520 } : { x: 700, y: 170, w: 880, h: 560 };
  const side = c.vertical ? 300 : 360;
  const [ax, ay] = path(t, [alert.w * 0.9, alert.h * 1.1], [alert.w / 2 + 40, alert.h - 70], 1.2, 2.7);
  const btn = { x: side + 50 + 190, y: 400 };
  const [sx, sy] = path(t, [win.w * 0.9, win.h * 0.95], [btn.x + 20, btn.y + 26], 5.6, 6.8);
  return (
    <Plan length={ETAPE3}>
      <Chiffre n={3} {...number} />
      {/* The alert */}
      <Sequence durationInFrames={Math.round(3.5 * fps)} layout="none">
        <div style={{ opacity: ease(t, 0.15, 0.4) * (1 - ease(t, 3.2, 3.5)), scale: 0.96 + 0.04 * ease(t, 0.15, 0.5, EASE.out) }}>
          <div
            style={{
              position: "absolute",
              left: alert.x,
              top: alert.y,
              width: alert.w,
              height: alert.h,
              borderRadius: 26,
              backgroundColor: "#1C1F28",
              boxShadow: "0 0 0 1.5px rgba(255,255,255,0.10), 0 40px 120px rgba(0,0,0,0.6)",
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              padding: "50px 60px",
              textAlign: "center",
              fontFamily: THEME.text,
            }}
          >
            <Icone size={110} />
            <div style={{ marginTop: 30, fontSize: 36, fontWeight: 700, color: THEME.fg }}>Impossible d'ouvrir « Yumi »</div>
            <div style={{ marginTop: 18, fontSize: 25, lineHeight: 1.4, color: THEME.muted }}>macOS n'a pas pu vérifier cette app : elle n'est pas encore notarisée par Apple.</div>
            <div style={{ position: "absolute", bottom: 46, left: 0, right: 0 }}>
              <Bouton primary pressed={press(t, ok)} style={{ minWidth: 220 }}>
                OK
              </Bouton>
            </div>
            <Clic x={alert.w / 2 + 40} y={alert.h - 70} at={ok} />
            <Pointeur x={ax} y={ay} press={press(t, ok)} />
          </div>
        </div>
      </Sequence>
      {/* System Settings */}
      <Sequence from={Math.round(3.3 * fps)} layout="none">
        <div style={{ opacity: ease(t, 3.3, 3.7), translate: `0 ${(1 - ease(t, 3.3, 3.9, EASE.out)) * 30}px` }}>
          <Fenetre title="Réglages Système" box={win}>
            <div style={{ position: "absolute", left: 0, top: 0, bottom: 0, width: side, backgroundColor: "#13151B", borderRight: "1px solid rgba(255,255,255,0.05)", paddingTop: 22 }}>
              {SECTIONS.map((s) => {
                const on = s === "Confidentialité et sécurité" && t > 4.4;
                return (
                  <div
                    key={s}
                    style={{
                      margin: "0 14px",
                      padding: "13px 16px",
                      borderRadius: 10,
                      fontSize: c.vertical ? 22 : 24,
                      fontWeight: 500,
                      color: on ? THEME.fg : THEME.muted,
                      backgroundColor: on ? "rgba(91,140,255,0.45)" : "transparent",
                    }}
                  >
                    {s}
                  </div>
                );
              })}
            </div>
            <div style={{ position: "absolute", left: side + 50, right: 40, top: 40, opacity: ease(t, 4.5, 4.9) }}>
              <div style={{ fontSize: 34, fontWeight: 700 }}>Confidentialité et sécurité</div>
              <div style={{ marginTop: 40, fontSize: 22, fontWeight: 700, color: THEME.faint, letterSpacing: "0.06em", textTransform: "uppercase" }}>Sécurité</div>
              <div style={{ marginTop: 16, fontSize: 25, lineHeight: 1.45, color: THEME.muted }}>« Yumi » a été bloqué parce qu'il ne vient pas d'un développeur identifié.</div>
            </div>
            <div style={{ position: "absolute", left: btn.x, top: btn.y, opacity: ease(t, 4.7, 5.1) }}>
              <Bouton pressed={press(t, anyway)} style={{ backgroundColor: `rgba(91,140,255,${0.3 + 0.5 * ease(t, anyway - 0.1, anyway + 0.2)})` }}>
                Ouvrir quand même
              </Bouton>
            </div>
            <Clic x={btn.x + 120} y={btn.y + 26} at={anyway} />
            <Pointeur x={sx} y={sy} press={press(t, anyway)} opacity={ease(t, 5.4, 5.6)} />
          </Fenetre>
        </div>
      </Sequence>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.4, text: "La première fois, macOS le bloque : cette alpha n'est pas encore notarisée par Apple." },
          { at: 3.5, end: 6.6, text: "Ouvre Réglages Système › Confidentialité et sécurité." },
          { at: 6.6, end: 9.3, text: "Clique sur « Ouvrir quand même ». Une seule fois." },
        ]}
      />
      <Son name="error" at={0.2} volume={0.35} />
      <Son name="tick" at={ok} volume={0.4} />
      <Son name="approve" at={anyway} volume={0.5} />
    </Plan>
  );
};

/** Step 4: he appears in the notch. Real take. */
export const ETAPE4 = 5;
export const Etape4: React.FC = () => {
  const { c, number } = useEtape();
  const t = useT();
  const box = c.vertical ? { x: 40, y: 560, w: 1000, h: 640 } : { x: 520, y: 120, w: 1240, h: 690 };
  return (
    <Plan length={ETAPE4}>
      <Chiffre n={4} {...number} />
      <Ecran take="lancement" source={0.72} rate={1.1} box={box} zoom={1.9 - 0.9 * ease(t, 2.0, 3.6)} />
      <SousTitres lines={[{ at: 0.3, end: 4.8, text: "Yumi apparaît dans la notch." }]} />
      <Son name="greet" at={2.0} volume={0.6} />
    </Plan>
  );
};

/** Step 5 (optional): the Claude Code hooks, from his settings. */
export const ETAPE5 = 7;
export const Etape5: React.FC = () => {
  const { number, win } = useEtape();
  const t = useT();
  const click = 2.6;
  const btn = { x: 60, y: 300 };
  const [px, py] = path(t, [win.w * 0.85, win.h * 0.9], [btn.x + 110, btn.y + 26], 1.0, 2.4);
  const done = ease(t, click + 0.3, click + 0.6);
  return (
    <Plan length={ETAPE5}>
      <Chiffre n={5} {...number} />
      <Fenetre title="Réglages de Yumi" box={win}>
        <div style={{ position: "absolute", left: 60, top: 40, fontSize: 22, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase", color: "#FFB547" }}>Facultatif</div>
        <div
          style={{
            position: "absolute",
            left: 40,
            right: 40,
            top: 90,
            height: 340,
            borderRadius: 16,
            backgroundColor: "rgba(255,255,255,0.04)",
            boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.07)",
          }}
        >
          <div style={{ position: "absolute", left: 20, top: 24, fontSize: 30, fontWeight: 700 }}>Claude Code Hooks</div>
          <div style={{ position: "absolute", left: 20, right: 20, top: 82, fontSize: 24, lineHeight: 1.45, color: THEME.muted }}>
            Tes sessions Claude Code dans la notch, et leurs demandes de permission.
          </div>
        </div>
        <div style={{ position: "absolute", left: btn.x, top: btn.y }}>
          <Bouton pressed={press(t, click)}>Install hooks</Bouton>
        </div>
        <div style={{ position: "absolute", left: 60, right: 40, top: 470, fontFamily: MONO, fontSize: 24, color: "#3DDC97", opacity: done }}>
          ✓ Hooks installed in ~/.claude/settings.json
        </div>
        <Clic x={btn.x + 110} y={btn.y + 26} at={click} />
        <Pointeur x={px} y={py} press={press(t, click)} />
      </Fenetre>
      <SousTitres
        lines={[
          { at: 0.3, end: 3.6, text: "Facultatif : installe les hooks Claude Code depuis ses réglages." },
          { at: 3.6, end: 6.8, text: "Il te montre le changement avant de l'écrire, et garde une sauvegarde." },
        ]}
      />
      <Son name="approve" at={click + 0.3} volume={0.5} />
    </Plan>
  );
};

/** What you need. */
export const PREREQUIS = 5.5;
export const Prerequis: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const items = [
    { text: "macOS 15 ou plus récent", note: "" },
    { text: "Claude Code installé et connecté", note: "pour le chat et les actions : chaque demande compte dans ton forfait Claude Code" },
  ];
  return (
    <Plan length={PREREQUIS}>
      <Rubrique>Ce qu'il te faut</Rubrique>
      <div style={{ position: "absolute", left: c.vertical ? 80 : 360, right: c.vertical ? 80 : 360, top: c.vertical ? 640 : 280, fontFamily: THEME.text }}>
        {items.map((it, i) => {
          const k = ease(t, 0.3 + i * 0.6, 0.8 + i * 0.6, EASE.out);
          return (
            <div key={it.text} style={{ display: "flex", gap: 30, marginBottom: 56, opacity: k, translate: `0 ${(1 - k) * 24}px` }}>
              <svg width={56} height={56} viewBox="0 0 40 40" style={{ flexShrink: 0, marginTop: 6 }}>
                <circle cx={20} cy={20} r={18} fill="none" stroke="rgba(61,220,151,0.35)" strokeWidth={2.5} />
                <path d="M11 20.5L17.5 27L29 14" fill="none" stroke="#3DDC97" strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <div>
                <div style={{ fontSize: c.vertical ? 58 : 64, fontWeight: 700, letterSpacing: "-0.02em", color: THEME.fg }}>{it.text}</div>
                {it.note ? <div style={{ marginTop: 12, fontSize: c.vertical ? 36 : 36, lineHeight: 1.35, color: THEME.muted }}>{it.note}</div> : null}
              </div>
            </div>
          );
        })}
      </div>
    </Plan>
  );
};

/** The call: where to get it, how to send feedback. */
export const APPEL = 7.5;
const AU_REVOIR: YumiScript = {
  seed: 212,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.6, mood: "wink", rim: "calm" },
    { at: 2.2, mood: "happy" },
    { at: 4.0, pose: "wave" },
  ],
};
export const Appel: React.FC = () => {
  const c = useCadre();
  const t = useT();
  const align = c.vertical ? "center" : "left";
  return (
    <Plan length={APPEL + 0.3}>
      <Yumi script={AU_REVOIR} size={c.vertical ? 560 : 520} style={{ position: "absolute", left: c.vertical ? 260 : 250, top: c.vertical ? 360 : 260 }} />
      <div style={{ position: "absolute", left: c.vertical ? 60 : 880, top: c.vertical ? 920 : 270, width: c.vertical ? 960 : 960, fontFamily: THEME.text }}>
        <Words lines={["Yumi 0.1.0-alpha"]} enter={0.2} size={c.vertical ? 84 : 92} style={{ fontWeight: 700, textAlign: align }} />
        <div style={{ marginTop: 26, textAlign: align, fontFamily: MONO, fontSize: c.vertical ? 38 : 40, color: "#9FBBFF", opacity: ease(t, 0.8, 1.2) }}>
          github.com/estebanbaigts/Yumi
        </div>
        <div style={{ marginTop: 44, textAlign: align, fontSize: c.vertical ? 38 : 38, lineHeight: 1.4, color: THEME.muted, opacity: ease(t, 1.6, 2.0) }}>
          Un retour ? Réglages de Yumi › « Envoyer un retour ».
        </div>
      </div>
      <Son name="wink" at={1.6} volume={0.6} />
    </Plan>
  );
};
