# Attribution

Yumi is built on the source code of [Coucou](https://github.com/Louis-CFM/coucou) by Louis Raillé, used under the MIT License (see `LICENSE`).

What was taken from Coucou: the Swift source code of the macOS app (`Yumi/Sources/App/`), imported from commit `5ae7bd9`, and the project configuration it needs to build.

What remains of it today: the structure of the app (app delegate, island window and panel, hook server and its Python relay, file drop, window capture, keychain helpers, sound engine, part of the island state machine and of the first CoreGraphics drawing). It has been largely rewritten since. The six service integrations of Coucou (Resend, n8n, Vercel, Stripe, Cal.com, Notion), the structured search and the integration pills were removed from Yumi in October 2026. Yumi still removes Coucou's and NotchBuddy's Claude Code hooks when it installs its own, so that people who used Coucou are not left with two relays.

What was not taken: the names "Coucou" and "Mochi", the Mochi character design, the app and menu bar icons, the sounds, the images and videos, the design prototypes and the website. These remain the property of Louis Raillé and are not part of this repository. Yumi ships its own name, character, icons and sounds.

Yumi is an independent project. It is not affiliated with or endorsed by the author of Coucou.
