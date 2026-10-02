import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { EASE, THEME } from "../theme";
import { Son } from "../son/Son";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { NOTCH, SIZE, YUMI_AT } from "./stage";

// His moods (design/yumi/video.md, 18 to 20 s): coffee, cloud, sunglasses, sleep.
//
// Four Yumis stand in a row and the camera steps from one to the next. Each one takes his
// mood as the camera reaches him, so every stop has its own small event: the caffeine
// kicks in, the cloud gathers, the glasses drop onto his nose, he melts into sleep.
// « Et il a son caractère. »

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Distance between two neighbours: the next one shows at the edge of the frame. */
const SPACING = 720;
/** When the camera leaves for the next one, in seconds. Each move lasts `MOVE`. */
const LEAVES = [0.7, 1.45, 2.2] as const;
const MOVE = 0.45;

const COFFEE: YumiScript = { seed: 11, lead: 3.95, cues: [{ at: 0, habit: "coffee" }] };
const CLOUD: YumiScript = { seed: 12, cues: [{ at: 0.85, habit: "cloud" }] };
const SUNGLASSES: YumiScript = { seed: 13, cues: [{ at: 1.7, habit: "sunglasses", pose: "pop" }] };
const SLEEP: YumiScript = { seed: 14, cues: [{ at: 2.45, habit: "sleep" }] };

/** One Yumi of the row: full size in front of the camera, smaller and dimmer beside it. */
const Seat: React.FC<{ readonly script: YumiScript; readonly index: number; readonly camera: number }> = ({
  script,
  index,
  camera,
}) => (
  <AbsoluteFill
    style={{
      translate: `${(index - camera) * SPACING}px 0`,
      scale: interpolate(Math.abs(index - camera), [0, 1], [1, 0.8], CLAMP),
      opacity: interpolate(Math.abs(index - camera), [0, 1], [1, 0.28], CLAMP),
      transformOrigin: "540px 1060px",
    }}
    from={-7}
  >
    <Yumi script={script} size={SIZE} style={YUMI_AT} />
  </AbsoluteFill>
);

export const Humeurs: React.FC = () => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  // Which Yumi the camera is on: 0 to 3, a step with a little overshoot at each move
  const camera =
    interpolate(t, [LEAVES[0], LEAVES[0] + MOVE], [0, 1], { ...CLAMP, easing: EASE.spring }) +
    interpolate(t, [LEAVES[1], LEAVES[1] + MOVE], [0, 1], { ...CLAMP, easing: EASE.spring }) +
    interpolate(t, [LEAVES[2], LEAVES[2] + MOVE], [0, 1], { ...CLAMP, easing: EASE.spring });

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {/* The way in: he drops out of the notch, where the scene before left him */}
      <AbsoluteFill
        style={{
          transformOrigin: `${NOTCH.x}px ${NOTCH.y}px`,
          scale: interpolate(t, [0, 0.5], [0.08, 1], { ...CLAMP, easing: EASE.spring }),
          opacity: interpolate(t, [0, 0.12], [0, 1], CLAMP),
        }}
      >
        <Seat script={COFFEE} index={0} camera={camera} />
        <Seat script={CLOUD} index={1} camera={camera} />
        <Seat script={SUNGLASSES} index={2} camera={camera} />
        <Seat script={SLEEP} index={3} camera={camera} />
      </AbsoluteFill>
      <AbsoluteFill style={{ top: 1270 }}>
        <Words lines={["Et il a", "son caractère."]} enter={0.3} size={118} />
      </AbsoluteFill>

      {/* One sound for each mood, as he takes it */}
      <Son name="pop" at={0.45} />
      <Son name="rate" at={0.9} volume={0.6} />
      <Son name="wink" at={1.85} />
      <Son name="sleep" at={2.5} />
    </AbsoluteFill>
  );
};
