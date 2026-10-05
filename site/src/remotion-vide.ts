// Stand-ins for the two Remotion hooks that motion/src/yumi/Yumi.tsx imports for its film
// wrapper. The page only uses YumiFigure, which needs neither.
export const useCurrentFrame = () => 0;
export const useVideoConfig = () => ({ fps: 60, width: 0, height: 0, durationInFrames: 1 });
