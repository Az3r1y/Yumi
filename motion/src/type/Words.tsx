import React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { EASE, THEME } from "../theme";

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/**
 * A headline that arrives word by word from behind a mask, tightens its tracking as it
 * settles, and leaves upwards the same way. One line per entry of `lines`. Times in seconds.
 */
export const Words: React.FC<{
  readonly lines: readonly string[];
  /** When the first word starts to rise. */
  readonly enter: number;
  /** When the first word starts to leave. Omit to stay. */
  readonly exit?: number;
  readonly size: number;
  readonly stagger?: number;
  /** A name can arrive letter by letter; a sentence arrives word by word. */
  readonly by?: "word" | "letter";
  readonly style?: React.CSSProperties;
}> = ({ lines, enter, exit, size, by = "word", stagger = by === "word" ? 0.1 : 0.05, style }) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  let index = 0;
  return (
    <div
      style={{
        fontFamily: THEME.text,
        fontSize: size,
        fontWeight: 600,
        lineHeight: 1.08,
        color: THEME.fg,
        textAlign: "center",
        letterSpacing: `${interpolate(t, [enter, enter + 1.2], [0.012, -0.028], { ...CLAMP, easing: EASE.out })}em`,
        ...style,
      }}
    >
      {lines.map((line) => (
        <div key={line}>
          {line.split(by === "word" ? " " : "").map((word) => {
            const i = index++;
            const rise = interpolate(t, [enter + i * stagger, enter + i * stagger + 0.6], [108, 0], { ...CLAMP, easing: EASE.out });
            const leave = exit === undefined
              ? 0
              : interpolate(t, [exit + i * 0.066, exit + i * 0.066 + 0.33], [0, -108], { ...CLAMP, easing: EASE.in });
            return (
              // The mask: taller than the line so descenders are not cut
              <span
                key={i}
                style={{
                  display: "inline-block",
                  overflow: "hidden",
                  padding: by === "word" ? "0.12em 0.14em" : "0.12em 0",
                  margin: "-0.12em 0",
                  whiteSpace: "pre",
                }}
              >
                <span style={{ display: "inline-block", translate: `0 ${rise + leave}%` }}>{word}</span>
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};
