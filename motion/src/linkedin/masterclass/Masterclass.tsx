import React from "react";
import { Audio } from "@remotion/media";
import { AbsoluteFill, Series, interpolate, staticFile, useVideoConfig } from "remotion";
import { THEME } from "../../theme";
import { ACCROCHE, ACTIONS, ACTIVITES, Accroche, Actions, Activites, CONFIANCE, Confiance, MEMOIRE, Memoire, PRESENTATION, Presentation, SESSIONS, Sessions } from "./ScenesDebut";
import {
  APPEL,
  Appel,
  ETAPE1,
  ETAPE2,
  ETAPE3,
  ETAPE4,
  ETAPE5,
  Etape1,
  Etape2,
  Etape3,
  Etape4,
  Etape5,
  INSTALLER,
  Installer,
  PREREQUIS,
  Prerequis,
} from "./ScenesInstallation";

// The LinkedIn masterclass, now that the alpha is out: understand what Yumi is, then install
// it without getting lost. The same scenes draw themselves for 16:9 and for 9:16.

const SCENES = [
  { name: "Accroche", length: ACCROCHE, C: Accroche },
  { name: "Présentation", length: PRESENTATION, C: Presentation },
  { name: "Sessions et permissions", length: SESSIONS, C: Sessions },
  { name: "Il agit", length: ACTIONS, C: Actions },
  { name: "Une activité à la fois", length: ACTIVITES, C: Activites },
  { name: "Il parle, il retient", length: MEMOIRE, C: Memoire },
  { name: "Confiance", length: CONFIANCE, C: Confiance },
  { name: "Installer", length: INSTALLER, C: Installer },
  { name: "Étape 1 : télécharger", length: ETAPE1, C: Etape1 },
  { name: "Étape 2 : Applications", length: ETAPE2, C: Etape2 },
  { name: "Étape 3 : Ouvrir quand même", length: ETAPE3, C: Etape3 },
  { name: "Étape 4 : la notch", length: ETAPE4, C: Etape4 },
  { name: "Étape 5 : les hooks", length: ETAPE5, C: Etape5 },
  { name: "Ce qu'il te faut", length: PREREQUIS, C: Prerequis },
  { name: "Appel", length: APPEL, C: Appel },
] as const;

export const MASTERCLASS_LENGTH = SCENES.reduce((s, x) => s + x.length, 0);

/** The calm middle of the reel's music (2.5 s to 24 s), laid end to end, quietly, with crossfades. */
const PART = { from: 2.5, length: 21.5, fade: 1.5 };
const Musique: React.FC = () => {
  const { fps } = useVideoConfig();
  const step = PART.length - PART.fade;
  const count = Math.ceil(MASTERCLASS_LENGTH / step);
  return (
    <>
      {Array.from({ length: count }, (_, i) => (
        <Audio
          key={i}
          src={staticFile("musique/ambiance.wav")}
          from={Math.round(i * step * fps)}
          trimBefore={Math.round(PART.from * fps)}
          durationInFrames={Math.round(PART.length * fps)}
          volume={(f) => {
            const s = f / fps;
            const end = Math.min(PART.length, MASTERCLASS_LENGTH - i * step);
            return 0.2 * interpolate(s, [0, i === 0 ? 0.01 : PART.fade, end - PART.fade, end], [i === 0 ? 1 : 0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
          }}
        />
      ))}
    </>
  );
};

export const Masterclass: React.FC = () => {
  const { fps } = useVideoConfig();
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <Musique />
      <Series>
        {SCENES.map(({ name, length, C }) => (
          <Series.Sequence key={name} name={name} durationInFrames={Math.round(length * fps)} premountFor={fps}>
            <C />
          </Series.Sequence>
        ))}
      </Series>
    </AbsoluteFill>
  );
};
