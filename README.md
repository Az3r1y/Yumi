# Yumi

A small companion that lives in your MacBook's notch and keeps an eye on your Claude Code sessions.

Native macOS app: Swift 6, SwiftUI + AppKit, no third-party dependencies.

**Status: work in progress.** The app builds and runs, but the migration from its Coucou base is under way: the character is being redrawn, and the icons and sounds are not there yet.

## Build

Requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd Yumi
xcodegen
open Yumi.xcodeproj   # then ⌘R
```

## Documents

- [YUMI.md](YUMI.md): decisions, character design brief, work plan.
- [ARCHITECTURE.md](ARCHITECTURE.md): analysis of the original code base.
- [ATTRIBUTION.md](ATTRIBUTION.md): what comes from Coucou and what does not.

## License

Code: [MIT](LICENSE). Yumi is built on the source code of [Coucou](https://github.com/Louis-CFM/coucou) by Louis Raillé. The Yumi name, character, icons and sounds are not covered by the MIT license.
