import React from "react";
import { AbsoluteFill } from "remotion";
import { THEME } from "../theme";

// LinkedIn shows a feed video at 4:5 (1080 × 1350). The films are drawn at 9:16 on pure
// black, so a portrait shot is shrunk and centred on what matters: the black around it
// blends into the frame and nothing is cut.

/** Height of the portrait film the scenes are drawn in. */
const FILM = { w: 1080, h: 1920 };

export const Cadre: React.FC<{
  readonly children: React.ReactNode;
  /** Scale of the 1080 × 1920 film inside the frame. */
  readonly scale?: number;
  /** The height in the film that sits at the centre of the frame. */
  readonly focus?: number;
}> = ({ children, scale = 0.82, focus = 900 }) => (
  <AbsoluteFill style={{ backgroundColor: THEME.black, overflow: "hidden" }}>
    <div
      style={{
        position: "absolute",
        width: FILM.w,
        height: FILM.h,
        left: "50%",
        top: "50%",
        transform: `translate(-50%, -${focus}px) scale(${scale})`,
        transformOrigin: `50% ${focus}px`,
      }}
    >
      {children}
    </div>
  </AbsoluteFill>
);
