import { Easing } from "remotion";

// Colours and type of the island (`IslandTheme` in the app, `:root` in the mock-up).
export const THEME = {
  /** The island and Yumi's body are pure black: unlit, he disappears into the frame. */
  black: "#000",
  fg: "#F4F5F8",
  muted: "#8D92A8",
  faint: "#5A5F74",
  /** The system face of the app (SF Pro on a Mac, where the film is rendered). */
  text: '-apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, "Helvetica Neue", sans-serif',
} as const;

export const EASE = {
  /** Arrives fast, settles long: entrances. */
  out: Easing.bezier(0.16, 1, 0.3, 1),
  /** Leaves slowly, goes fast: exits. */
  in: Easing.bezier(0.7, 0, 0.84, 0),
  /** `--spring` of the mock-up: a little overshoot, then rest. */
  spring: Easing.bezier(0.32, 1.22, 0.42, 1),
  /** Camera moves: controlled acceleration on both ends. */
  camera: Easing.bezier(0.6, 0, 0.2, 1),
} as const;
