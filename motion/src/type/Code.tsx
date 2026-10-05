import React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { THEME } from "../theme";

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const MONO = '"SF Mono", ui-monospace, Menlo, monospace';

/** Colours of the code, taken from Yumi's light. */
const INK = {
  keyword: "#9B7BFF",
  number: "#F58AD9",
  string: "#5FF0C8",
  comment: "#5A5F74",
  name: "#F4F5F8",
  punct: "#8D92A8",
};

const TOKENS = /(\/\/.*$)|("[^"]*")|(\b(?:function|const|return|let)\b)|(\b\d+(?:\.\d+)?\b)|([A-Za-z_][\w.]*)|(\s+)|(.)/g;

const colour = (m: RegExpExecArray) =>
  m[1] ? INK.comment : m[2] ? INK.string : m[3] ? INK.keyword : m[4] ? INK.number : m[5] ? INK.name : INK.punct;

/** One line, coloured, cut after `chars` characters. */
const Line: React.FC<{ readonly text: string; readonly chars: number }> = ({ text, chars }) => {
  const parts: React.ReactNode[] = [];
  let used = 0;
  TOKENS.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = TOKENS.exec(text)) && used < chars) {
    const piece = m[0].slice(0, chars - used);
    used += piece.length;
    parts.push(
      <span key={m.index} style={{ color: colour(m) }}>
        {piece}
      </span>,
    );
  }
  return <>{parts}</>;
};

/**
 * Code that types itself: `lines` appear character by character from `start` (seconds), at
 * `speed` characters a second, with a caret at the end. A line can be a function of time,
 * for values that change while you watch (a live number, a word being retyped).
 */
export const Code: React.FC<{
  readonly lines: readonly (string | ((t: number) => string))[];
  readonly start: number;
  readonly speed?: number;
  /** When the whole block leaves. */
  readonly exit?: number;
  readonly size?: number;
  readonly style?: React.CSSProperties;
}> = ({ lines, start, speed = 46, exit, size = 30, style }) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  const texts = lines.map((l) => (typeof l === "function" ? l(t) : l));
  // Typing time is counted on the text as first written, so a live value does not shift what follows
  const firsts = lines.map((l) => (typeof l === "function" ? l(start) : l));
  let budget = Math.max(0, (t - start) * speed);
  const caretBlink = Math.floor(t * 2.2) % 2 === 0;
  let caretLine = -1;
  const shown = texts.map((text, i) => {
    const n = Math.min(firsts[i].length, budget);
    budget -= firsts[i].length + 4; // a short pause at the end of each line
    if (n > 0 && n < firsts[i].length + 1) caretLine = i;
    return n >= firsts[i].length ? text.length : Math.floor(n);
  });
  if (caretLine < 0) caretLine = shown.findIndex((n) => n === 0) - 1;
  if (caretLine < -1) caretLine = texts.length - 1;

  return (
    <div
      style={{
        fontFamily: MONO,
        fontSize: size,
        lineHeight: 1.62,
        whiteSpace: "pre",
        // Nothing before the first character, not even the line numbers
        opacity: (t < start ? 0 : 1) * (exit === undefined ? 1 : interpolate(t, [exit, exit + 0.35], [1, 0], CLAMP)),
        translate: exit === undefined ? undefined : `0 ${interpolate(t, [exit, exit + 0.35], [0, -24], CLAMP)}px`,
        ...style,
      }}
    >
      {texts.map((text, i) => (
        <div key={i} style={{ display: "flex", opacity: shown[i] > 0 || i === 0 ? 1 : 0 }}>
          <span style={{ width: "2.4em", color: THEME.faint, textAlign: "right", marginRight: "1.1em", flexShrink: 0 }}>
            {i + 1}
          </span>
          <span>
            <Line text={text} chars={shown[i]} />
            {i === caretLine && caretBlink ? <span style={{ color: THEME.fg }}>▍</span> : null}
          </span>
        </div>
      ))}
    </div>
  );
};
