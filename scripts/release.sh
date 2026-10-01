#!/usr/bin/env bash
# Builds, signs, notarizes and staples Yumi.app, then zips it.
#
# Usage:
#   YUMI_TEAM_ID=XXXXXXXXXX ./scripts/release.sh <version> [--publish]
#
# Without --publish the script stops once the notarized zip is ready: nothing is
# tagged, pushed or uploaded. With --publish it also pushes the tag v<version>
# and creates the GitHub release.
#
# Environment:
#   YUMI_TEAM_ID         Apple Developer team ID (10 characters). Required.
#   YUMI_NOTARY_PROFILE  notarytool keychain profile. Default: yumi-notary.
#                        Create it once with:
#                          xcrun notarytool store-credentials yumi-notary \
#                            --apple-id <apple id> --team-id <team id>
#   YUMI_REPO            GitHub repository for --publish. Default: estebanbaigts/Yumi.
#
# Requires a "Developer ID Application" certificate for that team in the keychain.
set -euo pipefail

VERSION=""
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown option $arg" >&2; exit 2 ;;
    *)  VERSION="$arg" ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

[ -n "$VERSION" ] || die "usage: YUMI_TEAM_ID=XXXXXXXXXX $0 <version> [--publish]"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 1.2.3, got '$VERSION'"

TEAM_ID="${YUMI_TEAM_ID:-}"
NOTARY_PROFILE="${YUMI_NOTARY_PROFILE:-yumi-notary}"
REPO="${YUMI_REPO:-estebanbaigts/Yumi}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release-$VERSION"
APP="$BUILD_DIR/Yumi.app"
ZIP="$BUILD_DIR/Yumi-$VERSION.zip"
TAG="v$VERSION"

# ── 1. Preflight ──────────────────────────────────────────────────────────────
[ -n "$TEAM_ID" ] || die "YUMI_TEAM_ID is not set. The signing team has to be provided before the first release (see YUMI.md)."
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "YUMI_TEAM_ID must be the 10-character team ID, got '$TEAM_ID'"

for tool in xcodegen xcodebuild xcrun codesign ditto; do
  command -v "$tool" >/dev/null || die "$tool not found"
done

cd "$REPO_ROOT"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean. Commit or discard your changes first."

if [ "$PUBLISH" -eq 1 ]; then
  command -v gh >/dev/null || die "gh not found (needed for --publish)"
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "--publish only runs from main"
  git fetch --quiet origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main is not in sync with origin/main"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
fi

IDENTITY=$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*('"$TEAM_ID"')\)".*/\1/p' | head -1 || true)
[ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate for team $TEAM_ID in the keychain. Install it from Xcode, Settings, Accounts."
echo "Signing with: $IDENTITY"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$NOTARY_PROFILE' not found or not valid. See the header of this script."

if ! ls "$REPO_ROOT"/Yumi/Resources/sounds/*.wav >/dev/null 2>&1; then
  echo "warning: Yumi/Resources/sounds has no WAV file, this build will be silent." >&2
fi
if ! ls "$REPO_ROOT"/Yumi/Assets.xcassets/AppIcon.appiconset/*.png >/dev/null 2>&1; then
  echo "warning: the app icon set has no PNG, this build will have no icon." >&2
fi

# ── 2. Generate the project and check the version ─────────────────────────────
cd "$REPO_ROOT/Yumi"
xcodegen generate

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
[ "$PLIST_VERSION" = "$VERSION" ] \
  || die "project.yml says version $PLIST_VERSION, you asked for $VERSION. Update CFBundleShortVersionString (and CFBundleVersion) in Yumi/project.yml, commit, then retry."

# ── 3. Release build, signed with the Developer ID ────────────────────────────
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps get-task-allow out of the
# signature: notarization rejects it.
xcodebuild \
  -project Yumi.xcodeproj \
  -scheme Yumi \
  -configuration Release \
  build \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR"

[ -d "$APP" ] || die "build finished but $APP is missing"

# ── 4. Check the signature before sending anything to Apple ───────────────────
codesign --verify --deep --strict --verbose=2 "$APP"

SIGN_INFO=$(codesign -d --verbose=4 "$APP" 2>&1)
echo "$SIGN_INFO" | grep -q "TeamIdentifier=$TEAM_ID" || die "the app is not signed by team $TEAM_ID"
echo "$SIGN_INFO" | grep -Eq "flags=.*runtime"         || die "the hardened runtime is not enabled"
echo "$SIGN_INFO" | grep -q "^Timestamp="              || die "the signature has no secure timestamp"

ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
echo "$ENTITLEMENTS" | grep -q "com.apple.security.automation.apple-events" \
  || die "the apple-events entitlement is missing from the signature"
if echo "$ENTITLEMENTS" | grep -q "get-task-allow"; then
  die "the signature carries get-task-allow, notarization would reject it"
fi

# ── 5. Zip and notarize ───────────────────────────────────────────────────────
ditto -c -k --keepParent "$APP" "$ZIP"

SUBMISSION=$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
SUBMISSION_ID=$(echo "$SUBMISSION" | plutil -extract id raw -o - - 2>/dev/null || true)
STATUS=$(echo "$SUBMISSION" | plutil -extract status raw -o - - 2>/dev/null || true)
echo "Notarization: ${STATUS:-unknown} (${SUBMISSION_ID:-no id})"

if [ "$STATUS" != "Accepted" ]; then
  if [ -n "$SUBMISSION_ID" ]; then
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fi
  die "notarization failed"
fi

# ── 6. Staple and verify ──────────────────────────────────────────────────────
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"

# ── 7. Zip again, with the stapled app ────────────────────────────────────────
rm "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release zip ready: $ZIP"
shasum -a 256 "$ZIP"

# ── 8. Tag and GitHub release (only with --publish) ───────────────────────────
if [ "$PUBLISH" -ne 1 ]; then
  echo
  echo "Nothing was tagged or published. To publish this build, run again with --publish."
  exit 0
fi

cd "$REPO_ROOT"
git tag "$TAG"
git push origin "$TAG"

gh release create "$TAG" "$ZIP" \
  --repo "$REPO" \
  --title "Yumi $VERSION" \
  --notes "$(cat <<NOTES
## Install

Download **Yumi-$VERSION.zip**, unzip it and move **Yumi.app** to \`/Applications\`. The build is signed and notarized.

Requires macOS 15 or later, on a Mac with a notch.

## Build from source

\`\`\`bash
brew install xcodegen
git clone https://github.com/$REPO.git
cd Yumi/Yumi && xcodegen && open Yumi.xcodeproj
\`\`\`
NOTES
)"

echo "$TAG released: https://github.com/$REPO/releases/tag/$TAG"
