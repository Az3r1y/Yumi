import React from "react";
import { CURVES, curve } from "./motion";

// Skins: things Yumi can wear. Original drawings for him, in the same 100 × 84 box as the
// rest of the character (the top of his head is at y 8 when he stands at rest). Each one
// sits where it belongs: on the head, on the face, or on the front of the body, so it
// follows him when he squashes, leans or jumps.

export type SkinName = "pousse" | "bonnet" | "casquette" | "noeud" | "aureole" | "cornes" | "lunettes" | "moustache";

export const SKINS: readonly { readonly name: SkinName; readonly label: string }[] = [
  { name: "pousse", label: "La pousse" },
  { name: "bonnet", label: "Le bonnet" },
  { name: "casquette", label: "La casquette" },
  { name: "noeud", label: "Le nœud pap'" },
  { name: "aureole", label: "L'auréole" },
  { name: "cornes", label: "Les cornes" },
  { name: "lunettes", label: "Les lunettes" },
  { name: "moustache", label: "La moustache" },
];

/** Where each skin lives on him. */
export const SKIN_PLACE: Record<SkinName, "head" | "face" | "body"> = {
  pousse: "head", bonnet: "head", casquette: "head", aureole: "head", cornes: "head",
  lunettes: "face", moustache: "face", noeud: "body",
};

/** The point a skin grows from when it is put on. */
const ANCHOR: Record<SkinName, [number, number]> = {
  pousse: [50, 8], bonnet: [50, 14], casquette: [50, 14], aureole: [50, -6], cornes: [50, 14],
  lunettes: [50, 45], moustache: [50, 58], noeud: [50, 66],
};

/** A skin, drawn at `t` seconds after it was put on: it pops on with a little overshoot. */
export const Skin: React.FC<{ readonly name: SkinName; readonly t: number; readonly time: number }> = ({ name, t, time }) => {
  const k = curve(CURVES.spring, Math.min(1, t / 0.4));
  if (k <= 0.001) return null;
  const [ax, ay] = ANCHOR[name];
  return (
    <g transform={`translate(${ax} ${ay}) scale(${0.4 + 0.6 * k}) translate(${-ax} ${-ay})`} opacity={Math.min(1, t / 0.12)}>
      <SkinArt name={name} time={time} />
    </g>
  );
};

const SkinArt: React.FC<{ readonly name: SkinName; readonly time: number }> = ({ name, time }) => {
  switch (name) {
    case "pousse":
      // A sprout: it sways a little, as if it were alive too
      return (
        <g transform={`rotate(${4 * Math.sin(time * 2.1)} 50 9)`}>
          <path d="M50 9C50 4 49 0 51 -4" stroke="rgb(46,170,120)" strokeWidth={1.8} strokeLinecap="round" fill="none" />
          <ellipse cx={44.5} cy={-4.5} rx={6.2} ry={3} fill="rgb(61,220,151)" transform="rotate(-28 44.5 -4.5)" />
          <ellipse cx={57} cy={-6.5} rx={7.2} ry={3.4} fill="rgb(92,236,170)" transform="rotate(24 57 -6.5)" />
          <path d="M40.5 -2.5L48 -6.5M52.5 -5L61.5 -8" stroke="rgb(46,170,120)" strokeWidth={0.7} strokeLinecap="round" />
        </g>
      );
    case "bonnet":
      return (
        <g>
          <path d="M22 23C22 6 34 -1 50 -1C66 -1 78 6 78 23Z" fill="rgb(58,62,128)" />
          {/* knit ribs */}
          {[30, 38, 46, 54, 62, 70].map((x) => (
            <path key={x} d={`M${x} 21C${x} 12 ${x + (50 - x) * 0.2} 4 ${50 + (x - 50) * 0.7} 1`} stroke="rgb(78,84,160)" strokeWidth={1.2} fill="none" />
          ))}
          <rect x={20} y={17} width={60} height={8.5} rx={4.2} fill="rgb(91,140,255)" />
          <circle cx={50} cy={-3.5} r={5.2} fill="rgb(240,241,250)" />
        </g>
      );
    case "casquette":
      // Worn the right way, the visor to his right
      return (
        <g>
          <path d="M66 19C80 16 92 17 97 21.5C90 24.5 78 24 66 23Z" fill="rgb(200,60,78)" />
          <path d="M24 22C24 8 35 2 50 2C65 2 76 8 76 22Z" fill="rgb(255,93,108)" />
          <path d="M50 2C46 8 45 15 45.5 22M50 2C54 8 55 15 54.5 22" stroke="rgb(214,70,88)" strokeWidth={0.9} fill="none" />
          <circle cx={50} cy={2.6} r={1.8} fill="rgb(214,70,88)" />
        </g>
      );
    case "aureole":
      // It floats over him and breathes
      return (
        <g transform={`translate(0 ${1.2 * Math.sin(time * 2)})`}>
          <ellipse cx={50} cy={-6} rx={17} ry={4.4} fill="none" stroke="rgb(255,211,122)" strokeWidth={4.5} opacity={0.25} />
          <ellipse cx={50} cy={-6} rx={17} ry={4.4} fill="none" stroke="rgb(255,226,160)" strokeWidth={2} />
        </g>
      );
    case "cornes":
      return (
        <g fill="rgb(255,77,94)">
          <path d="M31 17C27 11 27 5 30 1C31.5 6 35 10 38.5 12.5Z" />
          <path d="M69 17C73 11 73 5 70 1C68.5 6 65 10 61.5 12.5Z" />
        </g>
      );
    case "lunettes":
      // Round, thin, a little studious
      return (
        <g fill="none" stroke="rgb(236,236,246)" strokeWidth={1.7}>
          <circle cx={37} cy={45} r={11.5} />
          <circle cx={63} cy={45} r={11.5} />
          <path d="M48.5 44Q50 42 51.5 44" />
          <path d="M25.5 43L16 40M74.5 43L84 40" strokeLinecap="round" />
        </g>
      );
    case "moustache":
      return (
        <path
          d="M50 57C46 54 40 54 36 57C33 59.5 30 59 28.5 56.5C29 61.5 33 64 38 62.5C42 61.5 46 59.5 50 59.5C54 59.5 58 61.5 62 62.5C67 64 71 61.5 71.5 56.5C70 59 67 59.5 64 57C60 54 54 54 50 57Z"
          fill="rgb(238,238,246)"
        />
      );
    case "noeud":
      // On the front of the body, under the face
      return (
        <g>
          <path d="M50 66L39 60.5Q37.5 66 39 71.5Z" fill="rgb(245,138,217)" />
          <path d="M50 66L61 60.5Q62.5 66 61 71.5Z" fill="rgb(245,138,217)" />
          <rect x={47.2} y={63.4} width={5.6} height={5.2} rx={1.6} fill="rgb(255,179,230)" />
        </g>
      );
  }
};
