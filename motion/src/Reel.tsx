import React from "react";
import { Audio } from "@remotion/media";
import { Series, staticFile, useVideoConfig } from "remotion";
import { Accroche } from "./scenes/Accroche";
import { Fin } from "./scenes/Fin";
import { Fonctions } from "./scenes/Fonctions";
import { Humeurs } from "./scenes/Humeurs";
import { Pov } from "./scenes/Pov";

/**
 * The whole film: the hook, what he does, his moods, the end.
 * The two hooks last the same, so everything after them, and the music, is shared.
 */
export const Reel: React.FC<{
  /** "noir": him alone in the dark, and the film loops on its first image (Instagram).
   *  "pov": he wakes up in the notch of the real screen (TikTok). */
  readonly accroche: "noir" | "pov";
}> = ({ accroche }) => {
  const { fps } = useVideoConfig();
  return (
    <>
      {/* Under his sounds, never over them (outils/musique.py) */}
      <Audio src={staticFile("musique/ambiance.wav")} volume={0.5} />
      <Series>
        <Series.Sequence name="Accroche" durationInFrames={300} premountFor={fps}>
          {accroche === "pov" ? <Pov /> : <Accroche />}
        </Series.Sequence>
        <Series.Sequence name="Fonctions" durationInFrames={954} premountFor={fps}>
          <Fonctions arrive={accroche !== "pov"} />
        </Series.Sequence>
        <Series.Sequence name="Humeurs" durationInFrames={204} premountFor={fps}>
          <Humeurs />
        </Series.Sequence>
        <Series.Sequence name="Fin" durationInFrames={198} premountFor={fps}>
          <Fin />
        </Series.Sequence>
      </Series>
    </>
  );
};
