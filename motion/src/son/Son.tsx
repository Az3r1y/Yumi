import React from "react";
import { Audio } from "@remotion/media";
import { staticFile, useVideoConfig } from "remotion";

/** The names of Yumi's sounds (outils/sons.py, the same as in the app). */
export type SonName =
  | "peek" | "open" | "close" | "hover" | "blip" | "tick" | "pop" | "send" | "attach" | "gulp" | "approve"
  | "work" | "think" | "search" | "approval" | "question" | "error" | "finish" | "rate" | "sleep" | "dizzy"
  | "greet" | "slap" | "annoyed" | "love" | "proud" | "wink" | "yawn";

/** One of his sounds, `at` seconds into the scene. */
export const Son: React.FC<{ readonly name: SonName; readonly at: number; readonly volume?: number }> = ({
  name,
  at,
  volume = 0.8,
}) => {
  const { fps } = useVideoConfig();
  return <Audio src={staticFile(`sons/${name}.wav`)} from={Math.round(at * fps)} premountFor={fps} volume={volume} />;
};
