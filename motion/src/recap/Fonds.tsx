import React from "react";
import { AbsoluteFill, useVideoConfig } from "remotion";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { Balade } from "./Alpha5";
import { P } from "./page";

// Backgrounds that loop: Yumi on the paper page, nothing else, to lay text or other content
// over. The walk loops cleanly because he comes in and leaves off frame; the matcha lasts two
// of its 7-second routines.

export const BALADE_LENGTH = 8;
export const MATCHA_LENGTH = 14;

export const FondBalade: React.FC = () => {
  const { height } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <Balade from={0} to={BALADE_LENGTH} y={height * 0.55} size={Math.round(height * 0.2)} />
    </AbsoluteFill>
  );
};

const MATCHA: YumiScript = { seed: 508, cues: [{ at: 0, habit: "matcha" }] };

export const FondMatcha: React.FC = () => {
  const { width, height } = useVideoConfig();
  const size = Math.round(Math.min(width, height) * 0.5);
  return (
    <AbsoluteFill style={{ backgroundColor: P.paper }}>
      <Yumi script={MATCHA} size={size} style={{ position: "absolute", left: (width - size) / 2, top: (height - size * 0.84) / 2 }} />
    </AbsoluteFill>
  );
};
