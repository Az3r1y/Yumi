# Yumi

[![Build](https://github.com/estebanbaigts/Yumi/actions/workflows/build.yml/badge.svg)](https://github.com/estebanbaigts/Yumi/actions/workflows/build.yml)

A small companion that lives in your MacBook's notch and keeps an eye on your Claude Code sessions.

Yumi is a native macOS app: Swift 6, SwiftUI and AppKit, no third-party dependencies. The character is drawn in code.

**Status: work in progress.** The app builds and runs with its own character, six working modules and a chat driven by Claude Code. The interface is being redesigned and the sounds are placeholders. There is no packaged release: build it from source.

## What it does

- **Follows Claude Code.** Yumi shows what the session is doing (thinking, running a tool, finished, failed) from the notch, through Claude Code hooks.
- **Approvals from the notch.** When Claude Code asks for a permission, the island opens and you answer Allow, Always or Deny without switching windows. If you do not answer, the question goes back to Claude Code as usual.
- **Chat and file drop.** Ask a question from the notch, or drop a file on the character and ask about it. This uses your own Anthropic API key.
- **Window context.** Drag the character onto a window to attach its title, and the address of the page if it is a browser, to your next prompt.
- **Integrations.** Optional status pills for Stripe, n8n, GitHub, Vercel, Resend, Notion and Cal.com, each with your own key.
- **Stays out of the way.** The island is hidden until something happens or you hover the notch.

Current limits, inherited from the original code base:

- Only Claude Code sessions running in VS Code are followed.
- One session at a time: two simultaneous sessions overwrite each other in the display.
- Built for a Mac with a notch. On other screens the island falls back to a fixed size at the top of the screen.

## Requirements

- macOS 15 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- `python3` on your `PATH`, for the Claude Code hook script

## Build

```bash
brew install xcodegen
```

```bash
git clone https://github.com/estebanbaigts/Yumi.git
```

```bash
cd Yumi/Yumi && xcodegen && open Yumi.xcodeproj
```

Then press ⌘R in Xcode. From the command line:

```bash
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build
```

The Xcode project and the `Info.plist` files are generated from [Yumi/project.yml](Yumi/project.yml). They are not in git: change `project.yml` and run `xcodegen` again.

The Debug build is not signed. macOS therefore asks again for the permissions below after each rebuild, and may ask to confirm Keychain access.

## Test

```bash
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO
```

The tests cover `IslandStateMachine`, the automaton that decides when the island is hidden, compact, expanded or greeting. They run without launching the app. Continuous integration runs the build and the tests on every push.

## Set up Claude Code

Open Yumi's settings from the menu bar icon and choose to install the hooks. Yumi shows the exact change before writing anything, saves a dated backup of `~/.claude/settings.json`, and merges its entries with yours. The same screen removes them.

Installing Yumi's hooks also removes the hooks left by Coucou or NotchBuddy, if any: Yumi replaces them and does not run side by side with them.

The hook is a small script that forwards each event to the app over a local Unix socket. If Yumi is not running, the script exits at once and Claude Code carries on.

## Permissions

Yumi works without any of these. Each one unlocks a feature.

| Permission | What it is for |
|---|---|
| Accessibility | Reading the title of the frontmost window as context, the Escape key, the global shortcut |
| Automation (Apple Events) | Reading the address of the active browser tab, sending an email through Mail when you confirm it |
| Login item | Launching Yumi at startup, if you turn it on |

## Privacy

- No telemetry, no account, no server of ours.
- Network calls go only to the services you configured, with your own keys.
- Keys are stored in the macOS Keychain, never on disk and never in git.
- Yumi never sends an email and never approves a Claude Code permission without an explicit click.

## Repository layout

```
Yumi/
├── project.yml          XcodeGen project, source of truth for the build
├── Sources/App/         all Swift code, one module
├── Tests/               unit tests (Swift Testing)
├── Assets.xcassets/     app icon
└── Resources/           entitlements, sounds
scripts/release.sh       signed and notarized build
design/yumi/             character concept sheet
.github/workflows/       continuous integration
```

## Release

[scripts/release.sh](scripts/release.sh) builds the Release configuration, signs it with a Developer ID certificate, has it notarized by Apple and staples the result. It needs an Apple Developer team, which has not been set up for Yumi yet, so no release has been published. The header of the script documents its options.

## Documents

- [YUMI.md](YUMI.md): decisions, character design brief, work plan.
- [ARCHITECTURE.md](ARCHITECTURE.md): analysis of the original code base, system by system.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to build, test and propose a change.
- [ATTRIBUTION.md](ATTRIBUTION.md): what comes from Coucou and what does not.

## Credits and license

Yumi is built on the source code of [Coucou](https://github.com/Louis-CFM/coucou) by Louis Raillé, used under the MIT License. Yumi is an independent project, not affiliated with or endorsed by the author of Coucou. See [ATTRIBUTION.md](ATTRIBUTION.md).

Code: [MIT](LICENSE). The Yumi name, character, icons and sounds are not covered by the MIT license.
