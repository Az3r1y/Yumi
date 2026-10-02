import React from "react";
import { AbsoluteFill } from "remotion";
import { THEME } from "../theme";
import { Yumi } from "../yumi/Yumi";
import { HABITS, type Pose } from "../yumi/blob";
import type { YumiScript } from "../yumi/engine";
import { MOODS, type Mood, type RimTone } from "../yumi/faces";

// The character sheet, as `YUMI_DEMO=gallery` shows it in the app (Character/YumiGallery.swift):
// same rows, so the two can be compared side by side. Not a shot of the film.

type Cell = { readonly label: string; readonly script: YumiScript };

const POSES: readonly [Pose, string, Mood][] = [
  ["jump", "Saut", "neutral"], ["stretch", "Étirer", "surprised"], ["squash", "S'écraser", "worried"],
  ["shake", "Secouer", "annoyed"], ["celebrate", "Célébrer", "happy"], ["wave", "Salut", "happy"],
  ["boing", "Boing", "neutral"], ["arrive", "Arrive", "neutral"],
];

const TONES: readonly [RimTone, string, Mood][] = [
  ["calm", "Au repos", "neutral"], ["work", "Au travail", "focused"], ["think", "Réfléchit", "thinking"],
  ["warn", "Attend ta réponse", "surprised"], ["error", "Erreur", "worried"], ["done", "Terminé", "happy"],
  ["joy", "Content", "wink"],
];

const ROWS: readonly { readonly title: string; readonly cells: readonly Cell[] }[] = [
  {
    title: "Habitudes",
    cells: HABITS.map((habit, i) => ({ label: habit, script: { seed: 10 + i, cues: [{ at: 0, habit }] } })),
  },
  {
    title: "Poses",
    cells: POSES.map(([pose, label, mood], i) => ({
      label,
      script: { seed: 30 + i, cues: [{ at: 0, mood }, { at: 0.6, pose }, { at: 3.2, pose }, { at: 5.8, pose }] },
    })),
  },
  {
    title: "Expressions",
    cells: (Object.keys(MOODS) as Mood[]).map((mood, i) => ({
      label: mood,
      script: { seed: 50 + i, cues: [{ at: 0, mood }] },
    })),
  },
  {
    title: "La lumière de contour porte l'état",
    cells: TONES.map(([rim, label, mood], i) => ({
      label,
      script: { seed: 70 + i, cues: [{ at: 0, mood, rim }] },
    })),
  },
];


export const Planche: React.FC = () => (
  <AbsoluteFill
    style={{ backgroundColor: "#0F0F0F", padding: "44px 60px", gap: 26, fontFamily: THEME.text, color: THEME.muted }}
  >
    {ROWS.map((row) => (
      <div key={row.title} style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase" }}>{row.title}</div>
        <div style={{ display: "flex", gap: 12 }}>
          {row.cells.map((cell) => (
            <div
              key={cell.label}
              style={{
                width: 166, height: 186, borderRadius: 18, backgroundColor: THEME.black,
                display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "flex-end",
                gap: 10, paddingBottom: 14, fontSize: 17, fontWeight: 700,
              }}
            >
              <Yumi script={cell.script} size={132} />
              {cell.label}
            </div>
          ))}
        </div>
      </div>
    ))}
  </AbsoluteFill>
);
