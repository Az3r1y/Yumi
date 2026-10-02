// Yumi stands at the same place and the same size in every shot where he is alone,
// so a cut from one to the next is a match cut: only he changes.

/** Width of Yumi's 100-unit box. */
export const SIZE = 760;
/** Where his eyes sit in the 1080 × 1920 frame. */
export const EYES = { x: 540, y: 860 };
/** Scale of the camera when it is close on the eyes, in the dark. */
export const CLOSE = 1.4;

export const YUMI_AT = {
  position: "absolute",
  left: EYES.x - SIZE / 2,
  top: EYES.y - SIZE * 0.45,
} as const;

/** Where the notch is in the scene filmed on the screen: he goes there and comes back from there. */
export const NOTCH = { x: 540, y: 340 };
