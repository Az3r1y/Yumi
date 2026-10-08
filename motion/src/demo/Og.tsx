import React from "react";
import { AbsoluteFill } from "remotion";
import { THEME } from "../theme";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";

// The social preview of the site and the repository (1200 × 630): Yumi, the promise, and the
// three beats he follows. Words only, no mock of the app: the real app is in the demos.

const SCRIPT: YumiScript = { seed: 3, breath: 0, cues: [{ at: 0, mood: "happy" }] };

const STEPS = ["You ask", "He shows exactly what will change", "You click", "He checks it's done"];

export const Og: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black, fontFamily: THEME.text, color: THEME.fg }}>
    <div style={{ position: "absolute", top: 0, left: 520, width: 160, height: 26, borderRadius: "0 0 18px 18px", background: "#16161c" }} />
    <Yumi script={SCRIPT} size={360} style={{ position: "absolute", left: 40, top: 150 }} />
    <div style={{ position: "absolute", left: 440, top: 110, right: 60 }}>
      <div style={{ fontSize: 30, fontWeight: 600, color: THEME.muted, marginBottom: 14 }}>Yumi</div>
      <div style={{ fontSize: 60, fontWeight: 700, lineHeight: 1.05, letterSpacing: "-0.03em" }}>The little AI in your notch that asks before it acts.</div>
      <div style={{ marginTop: 34, display: "flex", flexWrap: "wrap", gap: 12 }}>
        {STEPS.map((s, i) => (
          <div
            key={s}
            style={{
              padding: "10px 18px",
              borderRadius: 999,
              fontSize: 22,
              fontWeight: 600,
              background: i === 2 ? "#1f9d55" : "#1b1c24",
              color: i === 2 ? "#fff" : THEME.fg,
              boxShadow: "inset 0 0 0 1px rgba(255,255,255,0.08)",
            }}
          >
            {s}
          </div>
        ))}
      </div>
      <div style={{ marginTop: 30, fontSize: 22, color: THEME.faint, fontFamily: '"SF Mono", ui-monospace, Menlo, monospace' }}>
        free · open source · macOS 15+
      </div>
    </div>
  </AbsoluteFill>
);
