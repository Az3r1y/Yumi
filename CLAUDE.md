# Yumi: guide for AI coding agents

Yumi is a native macOS app: a small animated character living in the MacBook notch that shows Claude Code sessions and a few integrations, and lets the user approve, answer, chat and drop files from the notch. It is built on the MIT source code of Coucou (see `ATTRIBUTION.md`).

## Read first
- `YUMI.md`: decisions, identity values, character design brief, file ownership per work session. It wins over any other document.
- `ARCHITECTURE.md`: analysis of the 18 systems of the original code, with refactor risks. Paths written `NotchBuddy/...` are `Yumi/...` here.

## Where things are
- `Yumi/Sources/App/`: all Swift code. `Yumi/Resources/sounds/`: the WAV sounds. `Yumi/project.yml`: XcodeGen project.
- `design/yumi/`: character concept sheet (concept 4, left half).
- `Yumi/Tests/`: unit tests (Swift Testing). The bundle is not hosted by the app: a file under test is listed in the `YumiTests` target of `project.yml` and must have no dependency on the rest of the app.
- `scripts/release.sh`: signed and notarized build. Never run it unless the user asks: with `--publish` it pushes a tag and creates a GitHub release.
- `.github/workflows/build.yml`: build and tests on every push.
- Branch `legacy-v0`: the first Yumi attempt (typed event engine, multi-session store, tests). Reference only.

## Build and test
```
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build
cd Yumi && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO
```
Build in Debug before every commit. The build has 17 known warnings (concurrency and deprecated APIs): do not add any.

## Rules
- Swift 6, SwiftUI + AppKit. No third-party dependencies unless truly unavoidable. The character is drawn in code (`Canvas` + `TimelineView`).
- The `.xcodeproj` and the `Info.plist` files are generated: change `project.yml`, never edit them.
- Never copy an icon, sound, image or the Mochi character design from Coucou. This repository is public.
- Secrets live in the Keychain, never on disk or in git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app doesn't answer, the hook exits immediately.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, show the diff, write only after the user confirms.
- Never send an email or approve a Claude Code permission without an explicit click.
- Keep `LICENSE` with the original copyright notice.
- Contributor rules and the review checklist are in `CONTRIBUTING.md`.
