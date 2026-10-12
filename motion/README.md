# Yumi motion

The presentation film of Yumi: the reel for Instagram and TikTok, five stories and the cover. Everything is drawn in code with [Remotion](https://www.remotion.dev), in portrait, 1080 by 1920, 60 frames a second.

## Commands

Install the dependencies:

```console
npm i --loglevel=error
```

Open the studio to preview and scrub:

```console
npm run dev
```

Render one composition into `out/` (ignored by git):

```console
npx remotion render Reel-Instagram out/reel-instagram.mp4
```

Check the code:

```console
npm run lint
```

## Compositions

| Id | What it is | Length |
| --- | --- | --- |
| `Reel-Instagram` | The film, opening on the dark | 27.6 s |
| `Reel-TikTok` | The same film, opening on the point of view hook | 27.6 s |
| `Couverture` | The cover, a still image | |
| `Story1-Yeux` to `Story5-Salut` | The five stories | 4 to 6 s each |
| `Accroche`, `Pov`, `Fonctions`, `Humeurs`, `Fin` | The shots of the film, one by one | |
| `Short-01`, `Short-02`… | The shorts for TikTok, Reels and Shorts, built from real captures (see below) | 18 s or less |
| `Og` | Social preview of the site and the repository, 1200 × 630. Render it to `site/media/og.jpg` | |
| `Planche` | Reference sheet of the character, landscape | 8 s |

## Layout

- `src/yumi/`: the character. Soft body, eyes, faces and motion.
- `src/scenes/`: the shots of the film. `src/Reel.tsx` puts them in order.
- `src/stories/`: the five stories.
- `src/son/`, `src/type/`, `src/theme.ts`: sound, text and colours.
- `public/prises/`: screen footage of the app, shot with its filming mode (`YUMI_STUDIO=1`, see `design/yumi/video.md`). It shows demo data only.
- `public/sons/`, `public/musique/`: the sounds and the music.
- `outils/`: the Python programs that synthesise the sounds and the music. They need `numpy`.
- `publication/legendes.md`: the captions, ready to paste.
- `CLAUDE.md`: the motion design rules of Yumi.

To regenerate the audio:

```console
python3 outils/sons.py public/sons
python3 outils/musique.py public/musique/ambiance.wav
```

## License

All rights reserved, see [LICENSE.md](LICENSE.md). This folder is not covered by the MIT License of the app. Remotion has its own terms: a company license is needed for some entities, [read them here](https://github.com/remotion-dev/remotion/blob/main/LICENSE.md).

## Shorts: the content machine

Vertical videos (1080 × 1920, 60 fps, like every film here) for TikTok, Instagram Reels and YouTube Shorts. Each short is **data**: a list of beats with their texts, lengths and captures. The scenes draw them.

```
src/shorts/
  system.ts        types (Episode, Beat, Capture), frame size, safe zones
  scenes.tsx       HookScene, CaptureScene (with camera, click and proof), EndCardScene, SafeZones
  Episode.tsx      plays the beats in order, one transition for every cut, sounds and music
  episodes/        one file per short, and index.ts that lists them
public/shorts/<nn>/  the real recordings of each short
```

Reused from the films: Yumi (`src/yumi`), the theme and easings (`src/theme.ts`), his sounds (`src/son/Son.tsx`, `public/sons`), the click ring (`Clic` in `src/linkedin/masterclass/kit.tsx`).

### Run it

```console
npm i --loglevel=error
npm run dev
```

The studio lists the shorts in the **Shorts** folder. Turn on the `safeZones` prop to see, in red, what TikTok and Instagram cover with their buttons and captions.

### Beats

| Kind | What it draws |
| --- | --- |
| `hook` | The words, readable from the first frame, and Yumi under a notch. No logo, no intro. |
| `capture` | A real recording, cropped, framed, with a `title` at the top, an optional `caption` under it, a `camera` move (keys: time, point of the crop, zoom), a `click` (ring and a small push), and `proof: true` for the result seen in the real app (green tick and frame). |
| `end` | The line to remember, then the name and the tagline. |

### Add a new short

1. Copy `src/shorts/episodes/01-asks-before-it-acts.ts` to `02-<name>.ts`, change `id` (`Short-02`), the title and the beats.
2. Add it to `EPISODES` in `src/shorts/episodes/index.ts`. It appears in the studio.
3. Put its recordings in `public/shorts/02/`.

**Texts** are the `text`, `title`, `caption`, `line` and `tagline` fields. **Timings**: each beat has a `length`; inside a beat, `camera`, `click` and the capture's `start` are in seconds. Sounds (`sounds`) are in seconds of the whole short, and `music` is optional: every short must read without sound.

### Filming a capture

- ⌘⇧5, **full screen**, the real app, **English interface**, one take with no cut at the important moment.
- On a 14-inch MacBook Pro at its default size the file is 3024 × 1964; set `source` to the real size of yours.
- Show the pointer. Nothing private on screen (other apps, notifications, names).
- Save as `public/shorts/<nn>/<name>.mov`. Before committing, compress it to H.264 `.mp4` so the repository stays light, and update `file`.
- Each capture of an episode lists what it must show in `required`. While the file is missing, the short renders a striped **PROOF_ASSET_REQUIRED** panel with that list, never a mock.

### Render

```console
npx remotion render Short-01 out/short-01.mp4
```

One frame, to check: `npx remotion still Short-01 out/check.jpg --frame=120 --props='{"safeZones":true}'`.

### Video principles

- Show the product within 2 seconds.
- Real product proof beats animation.
- One idea per video.
- No fake product results.
- Hook first.
- Keep videos short.
- Every video should have a reason to watch until the end.

And for Yumi:

- Remotion stages, zooms, cuts and writes; the proof is always a real recording of Yumi or macOS.
- Texts stay inside the safe zones; one line at the top, at most one under the capture.
- One transition for every cut. No logo intro, no « hey guys ».
- Never film the cigarette habit.

The social preview is rendered with `npx remotion still Og ../site/media/og.jpg --image-format=jpeg`.
