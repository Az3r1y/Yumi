# Yumi

**Yumi — your native Mac companion for AI agents and creative workflows.**

Native macOS app (Swift 6, SwiftUI + AppKit, zero third-party dependencies).
This repository currently contains **steps 1 and 2 of the migration from Coucou**:
a clean, compilable socle, notch window, app lifecycle, menu bar, state
machine, a technical placeholder character, and the Core event engine
(typed events, sessions, presentation state) with unit tests.

## Build

Requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd yumi
xcodegen
open Yumi.xcodeproj   # then ⌘R
```

## Layout

```
Yumi/
├── App/          # entry point, composition root, menu bar (+ Simulate menu)
├── Core/         # event engine: IDs, Agent, YumiEvent, EventEngine, SessionStore
├── CoreTests/    # unit tests for the Core (Swift Testing)
├── UI/           # Notch (window + FSM), Character (sprite), Settings
├── Agents/       # ClaudeCode connector (empty — step 3)
├── Platform/     # keychain, permissions, sounds, logging (empty)
├── Legacy/       # code ported from Coucou + ATTRIBUTION.md
└── Resources/    # Info.plist (generated), future assets
```

Rules: new Yumi code stays out of `Legacy/`; ported Coucou files are listed in
[Legacy/ATTRIBUTION.md](Legacy/ATTRIBUTION.md). No Coucou brand, assets, sounds
or character is reused.

## Tests

```bash
cd yumi
test=$(xcodebuild -project Yumi.xcodeproj -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO 2>&1)
echo "$test" | grep -E "(passed|failed)"
```

26 tests cover the Core: event engine (publish/subscribe/unsubscribe/shutdown),
session reducer (every event kind, multi-session), presentation state, and IDs
(uniqueness, hashing, Codable).
