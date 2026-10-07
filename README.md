<p align="center">
  <img src="docs/yumi.png" alt="Yumi" width="280">
</p>

<h1 align="center">Yumi</h1>

<p align="center">
  A small companion that lives in the notch of your Mac.<br>
  He shows what your AI agents are doing, asks before anything changes on your Mac, and keeps you company the rest of the day.
</p>

<p align="center">
  <a href="https://github.com/estebanbaigts/Yumi/actions/workflows/build.yml"><img src="https://github.com/estebanbaigts/Yumi/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black" alt="macOS 15 or later">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/status-alpha-yellow" alt="Alpha">
  <img src="https://img.shields.io/badge/code-MIT-blue" alt="Code under MIT">
</p>

<p align="center">
  <a href="https://github.com/estebanbaigts/Yumi/releases"><b>⬇ Download the free alpha</b></a>
  ·
  <a href="https://estebanbaigts.github.io/Yumi/">Website</a>
  ·
  <a href="https://tally.so/r/Me9lvA">Give feedback</a> (no account needed)
</p>

<p align="center">
  <img src="docs/demo.gif" alt="A Claude Code session asks to run npm test; the user approves it from the notch" width="420">
</p>

---

## At a glance

| | |
|---|---|
| **What** | A native macOS companion in the notch: Claude Code sessions live, approvals from the notch, small actions on request, your day at a glance. |
| **Status** | Public alpha, **0.1.0-alpha.6**. Free and open source. |
| **Requires** | macOS 15 or later. A Mac with a notch is recommended (see [Known limitations](#known-limitations)). |
| **Languages** | English and French, following your Mac (Settings › General › Language). |
| **Privacy** | No account, no telemetry, no server of ours. Nothing changes on your Mac without your click. |
| **Built with** | Swift 6, SwiftUI and AppKit. No third-party dependency. About 28,700 lines of Swift and 820 unit tests. The character is drawn in code. |

## Install

1. Download `Yumi-<version>.zip` from the [latest release](https://github.com/estebanbaigts/Yumi/releases).
2. Unzip it and drag **Yumi.app** into **Applications**.
3. Open it. The alpha is **not notarized by Apple yet**, so the first time macOS blocks it: open **System Settings › Privacy & Security** and click **Open Anyway**.
4. Yumi appears in the notch. Right-click him for the settings.

Optional: in **Settings › Claude Code**, install the hooks so Yumi can follow your sessions. Yumi offers it himself when Claude Code is installed.

**Check the download.** Every release is built by GitHub Actions from the public code, not on a personal machine. The release page lists `SHA256SUMS.txt` and a build provenance attestation:

```bash
shasum -a 256 Yumi-0.1.0-alpha.6.zip
```

```bash
gh attestation verify Yumi-0.1.0-alpha.6.zip --repo estebanbaigts/Yumi
```

Yumi tells you when a new version is out, at most once a day. He never downloads or installs anything by himself.

## What he does

### He follows Claude Code

Every session, in every terminal and editor, appears in the notch with **what it is working on**: your request, the current task of Claude's todo list and its progress (« 3/7 »), the action in progress (« Edits IslandModel.swift », « Runs swift test »), the last files and commands, and a short summary when a turn ends. Click a session to unfold it, or to open its terminal.

When Claude Code asks for a permission, the island opens and you answer **Allow**, **Always** or **Deny** without leaving what you are doing. If you do not answer, the question goes back to Claude Code as usual.

All of this comes from Claude Code's hooks and, for Claude's last message, from the session transcript on your Mac. None of it is sent anywhere. Keys and tokens that appear in commands are masked.

### You ask, he acts, after your click

In the chat you talk to the engine of your choice (see [Engines](#engines)). When you ask for an action, Yumi's own agent prepares a plan, **shows you exactly what will change** (the file and its content, the reminder, the event), waits for your click, does it, then **checks it is really done**. Today he can:

| Action | Example | Asks first |
|---|---|---|
| Create a text file (Downloads, or Desktop, or Documents if you say so; never replaces a file) | « Create todo.md with two tasks » | Yes |
| Add a line at the end of a file he created | « Add "buy bread" to my todo » | Yes |
| Add a reminder | « Remind me to call the dentist tomorrow at 10 » | Yes |
| Add an event to your own calendar, never with guests | « Block Thursday 2 pm, client meeting » | Yes |
| Add a task to Notion | « Add "call Paul" to my Notion tasks » | Yes, every time (high risk: it leaves your Mac) |
| Start a Focus session | « I'm working for 45 minutes » | No, nothing leaves the Mac |
| Sum up a day and your free time, up to two weeks ahead | « How much free time do I have tomorrow? » | No, read only |

He **never** deletes, moves, sends a message or an email, runs a command, or edits a file he did not create. A request he cannot do is refused, and he says why.

### He keeps you company

- **One thing at a time.** Folded, the island shows what matters now: the music playing, the session at work, the next meeting. Open, a rail of icons lets you move between modules.
- **He remembers** what you tell him, in a plain text file on your Mac that you can read, edit or erase. He leaves secrets out.
- **He speaks first**, sometimes: two hours without a break, a meeting coming, an agent waiting. A setting makes him more or less discreet.
- **He is alive**: a soft body, eyes that follow the pointer, a rim of light that shows his state, small habits (coffee, matcha) while an agent works, and a little scene for GitHub events.

<p align="center">
  <img src="docs/musique.png" alt="The music module in the island" width="720">
</p>

## Modules

You choose which modules appear and in which order: drag and drop in **Settings › Modules**, or right in the island with **Edit**.

| Module | What it shows | What it needs |
|---|---|---|
| **Claude Code** | Every session, live: request, task progress, current action, approvals | Yumi's hooks (offered in the island) and `python3` |
| **GitHub** | Activity on all your repositories, grouped by repository: pushes with their exact commits, commits today and this week, pull requests and their checks, stars, forks, releases | A read-only personal access token |
| **Notion** | Today's and late tasks from the databases you choose: title, database, a date pill, late ones first. Click to open the page; tick the circle to mark it done in Notion (asked every time) | An internal integration key, and the databases shared with it |
| **Agenda** | Your next event of the day | Calendar access |
| **Notes** | Today's reminders, ticked from the notch | Reminders access |
| **Focus** | A work timer and its breaks | Nothing |
| **Music** | The track playing, pause, next, previous | Automation, for Music or Spotify |
| **Weather** | The sky where you are | Location, or a city typed by hand |

## Getting around

| | |
|---|---|
| **Right-click Yumi** or the island | Settings, Send feedback, Quit |
| **⌘,** / **⌘Q** | Settings / Quit, when the island is active |
| **Triple Shift** | Opens or folds the island (needs Accessibility outside the island) |
| **Click outside** | Folds the open island, unless an approval is waiting or the chat has unsent text |
| **Drag a file or a window onto Yumi** | Ask about it in the chat |

## Engines

The engine talks with you in the chat and proposes plans for actions. Whichever you use, **every plan is checked by Yumi** (known tools only, valid arguments, risk set by Yumi's code, not by the model), **every change asks you first**, and **the result is verified**. In the chat, no engine has a tool that changes your Mac.

**Automatic** takes the first engine that is ready, in this order. **Settings › Engines** lets you pick one, change the order, enter keys and models, and test each one.

| Engine | What you need | What leaves your Mac, and who bills it |
|---|---|---|
| **Claude Code** | Installed and logged in. Yumi runs it with no tool, shell, file, web, MCP server, settings or hooks. | Your messages go to Anthropic through your Claude Code account. Counted in your plan. |
| **Anthropic API** | A key | Your messages go to Anthropic. Billed per use. |
| **OpenAI API** | A key (default model `gpt-4o-mini`) | Your messages go to OpenAI. Billed per use. |
| **Google Gemini API** | A key (default model `gemini-2.5-flash`) | Your messages go to Google. Free tier to try, then billed. |
| **Ollama** | Ollama running on your Mac, with a model | Nothing leaves your Mac. Free. |

Keys are stored in the macOS Keychain. Yumi does not use other command-line agents (Codex, Gemini CLI): it cannot prove they run without tools.

## How the safety model works

```
Your request → engine proposes a plan → Yumi validates it → Permission gate → tool runs → Yumi verifies → result
```

- **The model only proposes.** A plan is accepted only if every step uses a known tool with valid arguments.
- **The risk comes from the code.** Each tool describes what it really does (read, create, modify); the risk level is computed from that, with fixed floors. The model cannot lower it.
- **Leaving the Mac is high.** Any change to an outside account or site (a Notion database, for instance) is at least high risk, whatever the tool says: it is asked every time, an "allow" rule turns into a question, and it cannot be remembered.
- **One gate.** Every step goes through a single permission manager: allowed (safe and local), asked, or refused (secrets, system folders, payments, `sudo`).
- **Approvals are precise and short-lived.** A request shows exactly what will change, expires after a minute on screen, and answers once.
- **Verification is a step.** If the file, reminder or event is not really there afterwards, the run fails and says so.
- **A history** of every decision stays on your Mac (Settings › Permissions): which tool, which file or site, what was decided. Never the content.

## Privacy

- No telemetry, no account, no server of ours.
- The memory never leaves your Mac. Calendar, reminders and Notion tasks are read on your Mac; the engine only receives Yumi's own one or two sentences about your day, which then stay in the conversation.
- When you open the chat, **the name of the app in front, its window title and the site's domain** are attached to your first message and shown in the notch (« With … »). **One click removes them.** The content of your screen is never sent. Only an explicit gesture (« Summarize », a window dragged onto Yumi, a dropped file) sends the full address or the file.
- A plan request sends your words, the last few messages, today's date and time, the list of Yumi's tools and the names of the files he created.
- Network calls go only to the services behind the modules you turned on (Open-Meteo, api.github.com, api.notion.com) and to the engine you use. GitHub is read-only; Notion reads only the databases you tick, and writes there only after you approve (adding a task, ticking one done).
- **« Always »** on a Claude Code permission writes a permanent rule in your Claude Code settings. Remove it with `/permissions` in Claude Code.
- Tokens and keys are stored in the macOS Keychain, never on disk and never in git.

### Permissions

Yumi works without any of these. Each one unlocks a feature and is asked for when you first use it.

| Permission | What it is for |
|---|---|
| Calendar | Your next event, the events you ask for |
| Reminders | Today's reminders, the ones you ask for |
| Location | The weather where you are |
| Automation | Pause and next track, the address of the page you show him |
| Accessibility | The window you show him, the Escape key, triple Shift |
| Downloads, Desktop, Documents | The files you ask him to create, and add to |
| Login item | Launching at startup, if you turn it on |

## Known limitations

This is an alpha. Here is what we know is missing or rough today.

- **Not notarized by Apple.** The first launch needs « Open Anyway ». Notarization needs a paid Apple Developer account, not set up yet. Builds are signed with a local certificate so that macOS keeps your permissions across updates.
- **Macs without a notch** are not tested yet. The island falls back to a fixed size at the top of the screen.
- **Read then act is not there yet.** The agent can read (your day) or act (create, add), but not read and then act on what it read in one request, like « prepare my day ».
- **Notion** lists twelve tasks at most in the island. Ticking needs a "done" property (checkbox or status) chosen in the settings, and is only offered in the direct build.
- **GitHub** commits are listed flat, not foldable. Counts cover what GitHub's activity feed returns (90 days, 300 events).
- **Gemini's free tier** can run out quickly; Yumi tells you which limit was hit and when it resets.
- **CPU**: about 10 % while an animated habit plays during an agent run, much less at rest.
- **The App Store build** is not shipped and cannot use Claude Code or the hooks.
- **Windows and Linux**: not planned for now. If you want them, [say so](https://tally.so/r/Me9lvA).

## Roadmap

- **Read then act**: « prepare my day », with a preview of the whole plan before the first question.
- **External modules**: described in a file instead of written in the code, always behind the same permission gate.
- Foldable GitHub commits.
- **Notarized releases**, once the Apple Developer account exists.
- **Macs without a notch**, tested and polished.
- More connected modules from your feedback.

What comes next depends on feedback: [tell us](https://tally.so/r/Me9lvA) what is missing.

## Build from source

You need macOS 15 or later, a recent Xcode (Xcode 26 or later), [XcodeGen](https://github.com/yonaskolb/XcodeGen), and `python3` for the hook script (Homebrew's, python.org's, or Apple's after `xcode-select --install`).

```bash
brew install xcodegen
```

```bash
git clone https://github.com/estebanbaigts/Yumi.git
```

```bash
cd Yumi/Yumi && xcodegen && open Yumi.xcodeproj
```

Then ⌘R in Xcode. The Xcode project and the `Info.plist` files are generated from [Yumi/project.yml](Yumi/project.yml) and are not in git.

Tests run without launching the app:

```bash
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO
```

Continuous integration builds and tests every push. Pushing a tag `v<version>` builds, signs, zips and attests a release draft ([.github/workflows/release.yml](.github/workflows/release.yml)).

## Repository

```
Yumi/                  the app (Sources/App, Tests, Resources, project.yml)
release/               the install guides shipped in the zip
design/yumi/           character sheet, voice (French and English), mockups, video plan
motion/                the presentation films, made with Remotion
site/                  the website
docs/                  images, post-alpha status, backlog
```

- [YUMI.md](YUMI.md): decisions and work plan (in French).
- [docs/POST_ALPHA_STATUS.md](docs/POST_ALPHA_STATUS.md): an honest audit of where Yumi stands.
- [CONTRIBUTING.md](CONTRIBUTING.md): how to build, test and propose a change.

## Credits and license

Yumi started from the source code of [Coucou](https://github.com/Louis-CFM/coucou) by Louis Raillé, used under the MIT License; about 6 % of today's Swift code is unchanged from it. Yumi is an independent project, not affiliated with or endorsed by the author of Coucou. [ATTRIBUTION.md](ATTRIBUTION.md) lists what comes from Coucou and what does not.

The code is under the [MIT License](LICENSE). The Yumi name, the character, the icons, the sounds and the films in `motion/` are not: see [LICENSE-ASSETS.md](LICENSE-ASSETS.md) and [motion/LICENSE.md](motion/LICENSE.md).
