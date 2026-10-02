import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Bord, Ecran, arrivee } from "./Fonctions";

// The hook for TikTok (design/yumi/video.md): the most surprising shot first, on the real
// screen. A drop swells under the notch, two eyes open in it and look around, the island
// opens, his light comes on, he waves. « POV : ton Mac a un colocataire. »
//
// The camera starts close on the notch, where nothing should be alive, and pulls back as the
// island opens. It ends on the window as the next scene needs it, so the two join without a cut.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const ramp = (t: number, from: number, to: number) =>
  interpolate(t, [from, to], [0, 1], { ...CLAMP, easing: EASE.camera });

export const Pov: React.FC<{
  /** The headline. An empty list leaves the launch on its own. */
  readonly lines?: readonly string[];
}> = ({ lines = ["POV : ton Mac", "a un colocataire."] }) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black, perspective: 1800 }}>
      <AbsoluteFill style={arrivee(t)}>
        {/* A little faster than life, so his light comes on at 2 s, with the music */}
        <Ecran
          take="lancement"
          source={0.72}
          rate={1.1}
          focus={[500, 0]}
          scale={2.3 - 0.4 * ramp(t, 1.45, 2.1) - 0.9 * ramp(t, 3.95, 4.8)}
        />
        <Bord />
      </AbsoluteFill>

      <AbsoluteFill style={{ top: 1170 }}>
        <Words lines={lines} enter={0.35} exit={4.15} size={100} />
      </AbsoluteFill>

      <Son name="pop" at={0.05} />
      <Son name="blip" at={0.62} volume={0.5} />
      <Son name="open" at={1.5} volume={0.6} />
      <Son name="greet" at={2.0} />
      <Son name="wink" at={3.35} />
      <Son name="close" at={4.05} volume={0.6} />
    </AbsoluteFill>
  );
};
