import { Video } from "@remotion/media";
import React from "react";
import { Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { EASE } from "../../theme";

// What both cuts of « une journée de dev » share: the three real takes and their beats.
//
// The takes are the app filmed on the built-in screen of the Mac in its filming mode
// (YUMI_STUDIO, shots 10 to 12 of Island/IslandStudio.swift), with its example data, cut
// around the notch: 1380 × 500 pixels of the recording. Never redrawn.

export const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const ease = (t: number, a: number, b: number, e = EASE.camera) => interpolate(t, [a, b], [0, 1], { ...CLAMP, easing: e });

export const TAKE = { w: 1380, h: 500 };

// The beats, in seconds of the film
export const MATCHA = 6.2;
export const SESSIONS = 11.2;
export const END = 21.4;
export const JOURNEE_LENGTH = 24.8;
/** The answer arrives in the chat. */
export const ANSWER = 2.2;
/** He tilts the bowl, then sighs with his eyes shut. */
export const SIP = 7.85;
/** The api session asks to run npm test. */
export const REQUEST = 15.3;
/** The green button is pressed in the notch. */
export const YES = 17.9;

export const PRISES = {
  libre: { take: "journee-temps-libre", from: 0, to: MATCHA },
  matcha: { take: "journee-matcha", from: MATCHA, to: SESSIONS },
  sessions: { take: "journee-sessions", from: SESSIONS, to: END },
} as const;

/** Yumi in the matcha take, in pixels of the take: where the camera goes. */
export const MATCHA_YUMI = { x: 135, y: 165 };

export const useT = () => {
  const { fps } = useVideoConfig();
  return useCurrentFrame() / fps;
};

export type Box = { readonly x: number; readonly y: number; readonly w: number; readonly h: number };

/**
 * A take in its box. The camera, when given, goes from the whole take to `zoom` times larger
 * with the point `focus` (pixels of the take) brought to the box's centre.
 * `reveal` (0 to 1) opens the box from left to right, or from right to left with `from: "right"`.
 */
export const Prise: React.FC<{
  readonly take: string;
  readonly from: number;
  readonly to: number;
  readonly box: Box;
  readonly camera?: { readonly focus: { x: number; y: number }; readonly zoom: number; readonly at: number; readonly length: number };
  readonly reveal?: (t: number) => number;
  readonly side?: "left" | "right";
  readonly style?: React.CSSProperties;
}> = ({ take, from, to, box, camera, reveal, side = "left", style }) => {
  const t = useT();
  const { fps } = useVideoConfig();
  const k = box.w / TAKE.w;
  let z = 1;
  let x = 0;
  let y = 0;
  if (camera) {
    const p = ease(t, camera.at, camera.at + camera.length);
    z = 1 + (camera.zoom - 1) * p;
    x = p * (box.w / 2 - camera.focus.x * k * camera.zoom);
    y = p * (box.h / 2 - camera.focus.y * k * camera.zoom);
  }
  const open = reveal ? reveal(t) : ease(t, from, from + 0.25) * (1 - ease(t, to - 0.25, to));
  const hidden = (1 - open) * 100;
  return (
    <Sequence from={Math.round(from * fps)} durationInFrames={Math.round((to - from) * fps)} layout="none">
      <div
        style={{
          position: "absolute",
          left: box.x,
          top: box.y,
          width: box.w,
          height: box.h,
          overflow: "hidden",
          backgroundColor: "#000",
          clipPath: reveal ? (side === "left" ? `inset(0 ${hidden}% 0 0)` : `inset(0 0 0 ${hidden}%)`) : undefined,
          opacity: reveal ? 1 : open,
          ...style,
        }}
      >
        <Video
          src={staticFile(`prises/${take}.mp4`)}
          muted
          style={{ position: "absolute", left: x, top: y, width: box.w * z, height: box.h * z }}
        />
      </div>
    </Sequence>
  );
};
