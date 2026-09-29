# Yumi

**Yumi — your native Mac companion for AI agents and creative workflows.**

Native macOS app (Swift 6, SwiftUI + AppKit, zero third-party dependencies).
This repository currently contains **step 1 of the migration from Coucou**:
a clean, compilable socle — notch window, app lifecycle, menu bar, state
machine, and a technical placeholder character. No feature is implemented yet.

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
├── App/          # entry point, app delegate, menu bar
├── Core/         # events, state, sessions, agents (empty — step 2)
├── UI/           # Notch (window + FSM), Character (engine + sprite), Settings
├── Agents/       # ClaudeCode connector (empty — step 3)
├── Platform/     # keychain, permissions, sounds, logging (empty)
├── Legacy/       # code ported from Coucou + ATTRIBUTION.md
└── Resources/    # Info.plist (generated), future assets
```

Rules: new Yumi code stays out of `Legacy/`; ported Coucou files are listed in
[Legacy/ATTRIBUTION.md](Legacy/ATTRIBUTION.md). No Coucou brand, assets, sounds
or character is reused.
