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
| `Demo-9x16` | Short demo for TikTok, Reels and Shorts around a **real screen recording**: hook, take, zoom on the strong moment, proof, end card. Props in `src/demo/Demo.tsx` | clip + 2.6 s |
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

## Making a demo

1. Record the real app with ⌘⇧5, full screen, English interface. One take, no cut at the important moment.
2. Put the file in `public/demo/` (for instance `public/demo/rappel.mov`).
3. In the studio (`npm run dev`), open `Demo-9x16` and set its props: `clip`, `clipStart`, `clipLength`, the `crop` (the part of the screen to keep), the `highlight` (zoom on the approval card), the `proof` and the `captions`.
4. Render: `npx remotion render Demo-9x16 out/demo.mp4 --props=props.json`.

Never stage the take: the demo must show the real app doing the real thing. The social preview is rendered with `npx remotion still Og ../site/media/og.jpg --image-format=jpeg`.
