# How Yumi is built

Yumi is one native macOS app (Swift 6, SwiftUI and AppKit, no third-party dependency). This page is the map: where each part lives, what it may depend on, and how a request travels through the app.

## The repository

```
Yumi/                     the app
  project.yml             XcodeGen project (the .xcodeproj and Info.plist are generated)
  Sources/App/            all the Swift code, one folder per part (below)
  Tests/                  Swift Testing, same folders as the sources
  Resources/              sounds, entitlements, plists
  Assets.xcassets         icons
docs/                     this map, the journal of decisions, backlog, distribution, images
  archive/                documents kept for history only
design/                   the character reference (maquette/reference.html), voice, video plan, tools
motion/                   the presentation films (Remotion)
site/                     the website
release/                  the install guides shipped in the zip
scripts/                  release and translation helpers
.github/                  CI (build, tests, signed release drafts) and issue forms
```

## The code, part by part

`Yumi/Sources/App/`

| Folder | What it does | May depend on |
|---|---|---|
| `App/` | Start-up and wiring: `YumiApp`, `AppDelegate` (creates everything and registers the tools), `AppState`, `AppIdentity`, the approval bridge, the window capture for file drops, the global shortcut, the sound engine | everything |
| `Hooks/` | `HookServer`: the local socket the Claude Code hooks talk to. It never blocks Claude Code | Core, Modules |
| `Island/` | The notch window and everything drawn in it: window controller, state machine (hidden, compact, open, greeting), the open island in cards and bento tabs, the chat view, settings in the island, the filming mode (`IslandStudio`) | Contracts, Core, Character, Modules (through snapshots) |
| `Character/` | Yumi himself: soft body, face, poses, habits, scenes, costumes, all drawn in code by `YumiRenderer` from `design/maquette/reference.html` | Contracts only |
| `AgentRuntime/` | The agent: request, planner, policy, executor, verifier. `Tools/` holds one file per action; `Providers/` the language models; `QuickTask/` the ⌥ Space capture | Permissions, Context, Memory |
| `Permissions/` | The checkpoint every action goes through: risk, approval, what the person allowed before | nothing above it |
| `Engines/` | Choosing and configuring the engine (Claude Code, Anthropic, OpenAI, Gemini, Ollama) | AgentRuntime/Providers |
| `Context/` | What is in front of the person (app, window, page), only when they allow it | nothing above it |
| `Memory/` | What Yumi remembers about the person, readable and erasable | Contracts |
| `Initiative/` | When Yumi speaks first, and how rarely | Contracts, Memory |
| `Modules/` | One folder per module (Claude Code, GitHub, Notion, Mail, Agenda, Notes, Focus, Music, Weather). Each produces a `ModuleSnapshot` and is filed under a tab (`ModuleCategory`). | Contracts, Core |
| `Core/` | Typed events, session store, chat plumbing, hook settings, studio mode | Contracts |
| `Contracts/` | Plain types shared between parts (snapshots, character commands, island look). No logic, no views | nothing |
| `Settings/` | The settings window | everything it configures |
| `Localization/` | `Localizable.xcstrings`: French source, English translation for every string | nothing |
| `Debug/` | Panels that trace the agent and the context, in debug builds | AgentRuntime, Context |

Two rules keep this readable:

- **Modules and Core never use a view, `AppState`, the hook server or a sound.** They produce data; the island shows it.
- **Only the folders the tests compile may be imported by them.** `App/`, `Island/`, `Hooks/`, `Settings/` and `Debug/` are app-only: keep testable logic in the other folders (the `YumiTests` target in `project.yml` lists them).
- **Nothing acts without `Permissions`.** A tool describes what it touches, the permission manager decides, the person approves, the verifier checks.

## A request, end to end

```
You type in the island (or ⌥ Space)
  → AgentRuntime: planner proposes a plan with tools
  → Permissions: risk of each step, approval card in the island when needed
  → Tool.execute, then Tool.verify looks again
  → the island shows the result; Character plays the matching pose and sound
```

## A Claude Code event, end to end

```
Claude Code hook (python relay installed by Yumi)
  → Hooks/HookServer (local socket, never blocks Claude Code)
  → ClaudeSessionJournal → ModuleSnapshot
  → the island: session pills, approval card, question, finished or error
  → your answer goes back through the socket to Claude Code
```

## Where to start

- A new action for the agent: `AgentRuntime/Tools/`, see [CONTRIBUTING.md](../CONTRIBUTING.md#teaching-yumi-a-new-trick).
- A new module: a folder in `Modules/`, a `ModuleSnapshot`, a `category`, then its card in `Island/`.
- The look of Yumi: `Character/`, checked against `design/maquette/reference.html`.
- Why something is the way it is: [journal.md](journal.md) (in French).
