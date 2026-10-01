# Contributing to Yumi

Thanks for your interest. Yumi is a small project and still in the middle of a migration, so please open an issue before starting anything large.

## Before you start

Read these two files first:

- [YUMI.md](YUMI.md): the decisions already taken (names, identifiers, character design). It wins over any other document.
- [ARCHITECTURE.md](ARCHITECTURE.md): how the code works, system by system, with the risks of each one. It describes the original Coucou code: paths written `NotchBuddy/...` are `Yumi/...` here.

## Setup

You need macOS 15 or later, Xcode 16 or later and XcodeGen.

```bash
brew install xcodegen
```

```bash
cd Yumi && xcodegen && open Yumi.xcodeproj
```

The Xcode project and the `Info.plist` files are generated and ignored by git. To change a build setting, a target or a permission text, edit `Yumi/project.yml` and run `xcodegen` again. Never edit the generated files.

## Build and test

Run both before every commit:

```bash
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build
```

```bash
cd Yumi && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO
```

Continuous integration runs the same commands on every push, and also compiles the `YumiAppStore` target. That target is not shipped yet, but its `#if APPSTORE` blocks must keep compiling.

The Debug build has 17 known warnings, all about concurrency and deprecated APIs. Do not add any.

## Writing tests

Tests live in `Yumi/Tests/` and use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).

The test bundle is not hosted by the app. A file under test is compiled straight into the bundle, which is why running the tests never opens the island, never starts the hook server and never touches the Keychain. To test a new file:

1. Check that it depends on nothing else in the app (no `AppState`, no singleton).
2. Add its path to the `sources` of the `YumiTests` target in `Yumi/project.yml`.
3. Run `xcodegen`, then write the tests.

Most of the code reads and writes `AppState.shared` directly and cannot be tested this way yet. Pulling a pure piece of logic out of a large file so that it can be tested is a welcome contribution.

Timers: set a delay to a few hundredths of a second when the transition must happen, and to a very long value when it must not. See `IslandStateMachineTests.swift`.

## Rules

- Swift 6 with strict concurrency. SwiftUI and AppKit.
- No third-party dependency unless there is truly no other way.
- The character is drawn in code. It is drawn by three separate renderers (`BotEngine`, `GreetingCanvasView`, `UploadCanvasView`): a change of appearance must be made in all three.
- Never copy an icon, a sound, an image or the Mochi character design from Coucou. This repository is public and those are not under the MIT license.
- Secrets go in the Keychain. Never write a key to disk, to a log or to git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app does not answer, the hook must exit at once.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, preview, and write only after the user confirms.
- Never send an email or approve a Claude Code permission without an explicit click.
- Do not fix an odd behaviour in passing. `ARCHITECTURE.md` lists several gaps between what the settings promise and what the code does. Each one deserves its own change, with its own description.

## Proposing a change

1. Create a branch from `main`. Nobody pushes to `main` directly.
2. Keep the change focused: one subject per pull request.
3. Build and run the tests.
4. If the change is visible, try it by hand. The checklist in step 0 of the migration plan in `ARCHITECTURE.md` lists what to go through: greeting, hover, click, hooks, approvals, file drop, chat, sounds, shortcut.
5. Open a pull request that says what changes for the user and how you checked it.

## Reporting a bug

Open an issue with your macOS version, your Mac model (with or without a notch), what you did, what you expected and what happened. For a problem with Claude Code, the log in `~/Library/Logs/Yumi/` helps. Check that it holds nothing private before attaching it.

Please do not report a security problem in a public issue. Write to the maintainer first.

## Releases

Releases are made by the maintainer with `scripts/release.sh`, which needs the Developer ID certificate. Do not run it in a pull request or in continuous integration.

## License

By contributing, you agree that your contribution is published under the [MIT License](LICENSE). The Yumi name, character, icons and sounds are not covered by that license.
