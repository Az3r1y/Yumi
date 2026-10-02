import React from "react";
import { AbsoluteFill } from "remotion";
import { THEME } from "../theme";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { SIZE, YUMI_AT } from "./stage";

// The cover of the post: him in his light and his name. Everything sits in the middle of the
// frame, so it survives the crop of a profile grid (4:5 on Instagram, about 3:4 on TikTok).

const SCRIPT: YumiScript = { seed: 3, breath: 0, cues: [{ at: 0, mood: "happy" }] };

export const Couverture: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Yumi script={SCRIPT} size={SIZE} style={YUMI_AT} />
    <div
      style={{
        position: "absolute",
        top: 1215,
        left: 0,
        right: 0,
        textAlign: "center",
        fontFamily: THEME.text,
        fontSize: 220,
        fontWeight: 700,
        letterSpacing: "-0.028em",
        lineHeight: 1,
        color: THEME.fg,
      }}
    >
      Yumi.
    </div>
  </AbsoluteFill>
);
