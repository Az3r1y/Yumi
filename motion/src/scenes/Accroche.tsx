import React from "react";
import {
  AbsoluteFill,
  interpolate,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { EASE, THEME } from "../theme";
import { CLOSE, EYES, NOTCH, SIZE, YUMI_AT } from "./stage";
import { Son } from "../son/Son";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";

// The hook (design/yumi/video.md, 0 to 5 s). Nothing but him on black.
//
// Dark: the camera is close on two sleeping eyes. They snap open, check left, then right,
// and find the viewer. « Il vit dans ton Mac. »
// Light: it comes on, the rim draws itself round him while the camera pulls back to show
// that the eyes had a body all along. He bounces, waves, winks. « Voici Yumi. »

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** When the light comes on, in seconds: the turning point of the shot. */
const LIGHT = 2;
/** When he leaves for the notch. */
const LEAVE = 4.5;

// The launch of the app (IslandLaunch.swift), retimed for the shot. Times in seconds.
const SCRIPT: YumiScript = {
  seed: 7,
  // The breath Fin ends on: the loop has no seam
  breath: 0,
  cues: [
    { at: 0, lit: false, mood: "asleep" },
    { at: 0.4, mood: "surprised", pose: "pop" },
    { at: 0.8, gaze: [-1, 0] },
    { at: 1.15, gaze: [1, 0] },
    { at: 1.55, mood: "curious" },
    { at: 2.0, lit: true, mood: "happy", rim: "joy", pose: "boing" },
    { at: 2.65, pose: "wave" },
    { at: 3.75, mood: "wink", rim: "calm" },
    { at: 4.4, mood: "happy" },
  ],
};

export const Accroche: React.FC = () => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {/* The way out: he shrinks up to where the notch is, and the next scene finds him there */}
      <AbsoluteFill
        style={{
          transformOrigin: `${NOTCH.x}px ${NOTCH.y}px`,
          scale:
            1 -
            interpolate(t, [LEAVE, LEAVE + 0.5], [0, 0.92], {
              ...CLAMP,
              easing: EASE.in,
            }),
          opacity: interpolate(t, [LEAVE + 0.38, LEAVE + 0.5], [1, 0], CLAMP),
        }}
      >
        {/* Camera: a slow push in the dark, then a pull back when the light comes on */}
        <AbsoluteFill
          style={{
            transformOrigin: `${EYES.x}px ${EYES.y}px`,
            scale:
              interpolate(t, [0, LIGHT], [CLOSE, 1.48], CLAMP) -
              interpolate(t, [LIGHT - 0.07, LIGHT + 1], [0, 0.48], {
                ...CLAMP,
                easing: EASE.camera,
              }),
          }}
        >
          <Yumi script={SCRIPT} size={SIZE} style={YUMI_AT} />
        </AbsoluteFill>
      </AbsoluteFill>

      {/* Type sits in front of the camera move: it drifts a little, he moves a lot */}
      <AbsoluteFill
        style={{
          top: 1270,
          translate: `0 ${interpolate(t, [LIGHT - 0.07, LIGHT + 1], [-40, 0], { ...CLAMP, easing: EASE.camera })}px`,
        }}
      >
        <Words
          lines={["Il vit", "dans ton Mac."]}
          enter={0.53}
          exit={LIGHT - 0.4}
          size={118}
        />
      </AbsoluteFill>
      <AbsoluteFill style={{ top: 1300 }}>
        <Words
          lines={["Voici Yumi."]}
          enter={LIGHT + 0.73}
          exit={LEAVE - 0.2}
          size={136}
        />
      </AbsoluteFill>

      {/* His sounds, on what he does */}
      <Son name="pop" at={0.4} />
      <Son name="blip" at={0.8} volume={0.5} />
      <Son name="blip" at={1.15} volume={0.5} />
      <Son name="greet" at={LIGHT} />
      <Son name="wink" at={3.8} />
      <Son name="peek" at={LEAVE + 0.1} volume={0.6} />
    </AbsoluteFill>
  );
};
