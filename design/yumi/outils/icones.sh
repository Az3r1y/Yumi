#!/bin/sh
# Renders the app icon and the menu bar icon from the drawing code of the app itself:
# the block between the "YumiSkin" markers of BotEngine.swift is compiled with icones.swift.
#
#   design/yumi/outils/icones.sh
#
# Writes Yumi/Assets.xcassets/AppIcon.appiconset and MenuBarIcon.imageset.
set -e
cd "$(dirname "$0")/../../.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

{
    echo "import CoreGraphics"
    echo "import Foundation"
    sed -n '/^\/\/ >>> YumiSkin/,/^\/\/ <<< YumiSkin/p' Yumi/Sources/App/BotEngine.swift
} > "$tmp/YumiSkin.swift"

swiftc -O "$tmp/YumiSkin.swift" design/yumi/outils/icones.swift -o "$tmp/icones"
"$tmp/icones" Yumi/Assets.xcassets
