/** `bodyPath(h, w, L)` of the mock-up: h is the height, w the width, L the lean of the top. */
export const bodyPath = (h: number, w: number, L: number): string => {
  const by = 76;
  const ty = by - 68 * h;
  const tx = 50 + L;
  const sy = by - 14 * Math.pow(h, 0.7);
  const wb = 1 + (w - 1) * 0.55;
  const lx = 50 - 42 * w + L * 0.12;
  const rx = 50 + 42 * w + L * 0.12;
  const cy = sy - 31 * h;
  const my = sy + (by - sy) * 0.71;
  return [
    `M${lx} ${sy}`,
    `C${lx} ${cy} ${tx - 23 * w} ${ty} ${tx} ${ty}`,
    `C${tx + 23 * w} ${ty} ${rx} ${cy} ${rx} ${sy}`,
    `C${rx} ${my} ${50 + 32 * wb} ${by} 50 ${by}`,
    `C${50 - 32 * wb} ${by} ${lx} ${my} ${lx} ${sy}`,
    "Z",
  ].join("");
};

/** The outline for a height alone: the width follows from it, as for Yumi's own body. */
export const bodyPathFor = (h: number, lean: number) =>
  bodyPath(h, Math.max(0.68, Math.min(1.55, 1 / Math.pow(h, 0.62))), lean);

export type Point = readonly [number, number];

/**
 * The same outline as `bodyPath`, as its anchors and the control points of its four Bézier
 * curves, for drawing it as a blueprint. `curves[i]` goes from `anchors[i]` to `anchors[i + 1]`.
 */
export const bodyPoints = (h: number, w: number, L: number) => {
  const by = 76;
  const ty = by - 68 * h;
  const tx = 50 + L;
  const sy = by - 14 * Math.pow(h, 0.7);
  const wb = 1 + (w - 1) * 0.55;
  const lx = 50 - 42 * w + L * 0.12;
  const rx = 50 + 42 * w + L * 0.12;
  const cy = sy - 31 * h;
  const my = sy + (by - sy) * 0.71;
  const anchors: Point[] = [[lx, sy], [tx, ty], [rx, sy], [50, by]];
  const controls: [Point, Point][] = [
    [[lx, cy], [tx - 23 * w, ty]],
    [[tx + 23 * w, ty], [rx, cy]],
    [[rx, my], [50 + 32 * wb, by]],
    [[50 - 32 * wb, by], [lx, my]],
  ];
  return { anchors, controls };
};

/** The width that goes with a height, as for Yumi's own body. */
export const widthFor = (h: number) => Math.max(0.68, Math.min(1.55, 1 / Math.pow(h, 0.62)));
