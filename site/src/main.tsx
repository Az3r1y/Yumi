import { render } from "preact";
import { YumiFigure } from "../../motion/src/yumi/Yumi";
import { LiveYumi } from "../../motion/src/yumi/engine";

// The living Yumi at the top of the page, and the download link.
//
// He is drawn by the film's own engine and renderer (motion/src/yumi): the same soft body,
// the same eyes, the same light. Here nothing is scripted: he wakes up in the dark when the
// page opens, then breathes, blinks, follows the pointer, and bounces when you touch him.
// With reduced motion he stays still, awake and lit.

const stage = document.getElementById("yumi");
const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

if (stage) {
  const yumi = new LiveYumi(7);
  const draw = () => {
    const size = Math.round(stage.clientWidth);
    render(<YumiFigure frame={yumi.frame()} size={size} />, stage);
  };

  if (reduce) {
    yumi.command({ mood: "happy", rim: "calm" });
    yumi.advance(2);
    draw();
    window.addEventListener("resize", draw);
  } else {
    // He wakes up as the app does: eyes in the dark, then the light
    yumi.command({ lit: false, mood: "asleep" });
    const wake: [number, () => void][] = [
      [0.6, () => yumi.command({ mood: "surprised", pose: "pop" })],
      [1.0, () => yumi.command({ gaze: [-1, 0] })],
      [1.35, () => yumi.command({ gaze: [1, 0] })],
      [1.8, () => yumi.command({ lit: true, mood: "happy", rim: "joy", pose: "boing" })],
      [2.6, () => yumi.command({ pose: "wave" })],
      [4.3, () => yumi.command({ mood: "neutral", rim: "calm" })],
    ];
    let clock = 0;
    let awake = false;

    // He looks where the pointer is, and back at you when it rests
    let lastMove = -10;
    let gaze: [number, number] | null = null;
    window.addEventListener(
      "pointermove",
      (e) => {
        if (!awake) return;
        const r = stage.getBoundingClientRect();
        const cx = r.left + r.width / 2;
        const cy = r.top + r.height * 0.45;
        const x = Math.max(-1, Math.min(1, (e.clientX - cx) / (window.innerWidth * 0.45)));
        const y = Math.max(-1, Math.min(1, (e.clientY - cy) / (window.innerHeight * 0.45)));
        if (!gaze || Math.abs(gaze[0] - x) + Math.abs(gaze[1] - y) > 0.03) {
          gaze = [x, y];
          yumi.command({ gaze });
        }
        lastMove = clock;
      },
      { passive: true },
    );

    // Touch him: he bounces. Three times in a row and he gets dizzy, as in the app
    let taps: number[] = [];
    const poke = () => {
      if (!awake) return;
      taps = [...taps.filter((t) => clock - t < 1.7), clock];
      if (taps.length >= 3) {
        taps = [];
        yumi.command({ mood: "surprised", rim: "joy", pose: "shake" });
        later.push([clock + 1.4, () => yumi.command({ mood: "neutral", rim: "calm" })]);
      } else {
        yumi.command({ mood: "annoyed", pose: "boing" });
        later.push([clock + 0.8, () => yumi.command({ mood: "neutral" })]);
      }
    };
    const button = stage.closest("button");
    button?.addEventListener("click", poke);

    const later: [number, () => void][] = [];
    let nextBlink = 3;
    let visible = true;
    new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
    }).observe(stage);

    let last = performance.now();
    const loop = (now: number) => {
      const dt = (now - last) / 1000;
      last = now;
      clock += Math.min(dt, 0.25);
      for (const list of [wake, later]) {
        for (let i = list.length - 1; i >= 0; i--) {
          if (clock >= list[i][0]) {
            list[i][1]();
            list.splice(i, 1);
          }
        }
      }
      if (!awake && wake.length === 0) awake = true;
      if (awake && clock >= nextBlink) {
        yumi.command({ blink: true });
        nextBlink = clock + 3 + Math.random() * 3.5;
      }
      if (awake && gaze && clock - lastMove > 5) {
        gaze = null;
        yumi.command({ gaze: null });
      }
      yumi.advance(dt);
      // Nothing to draw while he is off screen: the page costs nothing then
      if (visible) draw();
      requestAnimationFrame(loop);
    };
    draw();
    requestAnimationFrame(loop);
  }
}

// The download button goes to the newest release. A pre-release is not "latest" for GitHub,
// so the list is asked for its first entry; without an answer, the link stays on the page
// that lists every release.
const download = document.querySelectorAll<HTMLAnchorElement>("[data-release]");
const versionLabel = document.querySelectorAll<HTMLElement>("[data-version]");
fetch("https://api.github.com/repos/estebanbaigts/Yumi/releases?per_page=1", { headers: { Accept: "application/vnd.github+json" } })
  .then((r) => (r.ok ? r.json() : []))
  .then((list: { html_url?: string; tag_name?: string }[]) => {
    const latest = list[0];
    if (!latest?.html_url) return;
    download.forEach((a) => (a.href = latest.html_url!));
    if (latest.tag_name) versionLabel.forEach((v) => (v.textContent = latest.tag_name!.replace(/^v/, "")));
  })
  .catch(() => {});
