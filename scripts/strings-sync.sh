#!/bin/zsh
# Builds Yumi and YumiAppStore, then adds to the String Catalog every string the code shows
# (SwiftUI texts and String(localized:)). The English is then written in the catalog; the
# test StringCatalogTests fails while one is missing.
set -e
cd "$(dirname "$0")/../Yumi"
xcodegen -q
for scheme in Yumi YumiAppStore; do
  xcodebuild -scheme $scheme -configuration Debug build -quiet >/dev/null
done
objroot=$(xcodebuild -scheme Yumi -configuration Debug -showBuildSettings 2>/dev/null | awk '/ OBJROOT /{print $3}')
files=(${(f)"$(find "$objroot" -name '*.stringsdata' -path '*Debug*' | grep -v '/YumiTests.build/')"})
xcrun xcstringstool sync Sources/App/Localization/Localizable.xcstrings --stringsdata $files
echo "$(xcrun xcstringstool print Sources/App/Localization/Localizable.xcstrings | grep -c '^Key') keys"
