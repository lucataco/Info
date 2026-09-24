#!/bin/bash
#
# Cuts a new Info release and publishes it to the Homebrew tap.
#
# Steps:
#   1. Build a Release Info.app (via `make build`).
#   2. Zip it as build/Info-<version>.zip (ditto, preserves the bundle).
#   3. Create/upload a GitHub release tagged v<version> with the zip.
#   4. Bump version + sha256 in the tap cask, then commit & push the tap.
#
# Usage:
#   tools/release.sh [version]
#
# If [version] is omitted, MARKETING_VERSION from project.yml is used.
#
# Environment overrides:
#   TAP_DIR    Path to the homebrew-tap checkout
#              (default: probes ../homebrew-tap then ../../homebrew-tap)
#   APP_REPO   owner/name of the app repo (default: lucataco/Info)
#   SKIP_TAP=1 Build + publish the release but do not touch the tap.
#
# Requirements: gh (authenticated), xcodegen, xcodebuild, ditto, git.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Info"
APP_REPO="${APP_REPO:-lucataco/Info}"
if [ -z "${TAP_DIR:-}" ]; then
  if [ -d "$REPO_ROOT/../homebrew-tap" ]; then
    TAP_DIR="$REPO_ROOT/../homebrew-tap"
  else
    TAP_DIR="$REPO_ROOT/../../homebrew-tap"
  fi
fi
CASK_FILE_NAME="info.rb"

err() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

command -v gh >/dev/null 2>&1 || err "gh (GitHub CLI) is required: https://cli.github.com"
gh auth status >/dev/null 2>&1 || err "gh is not authenticated; run: gh auth login"

# --- Resolve version -------------------------------------------------------
VERSION="${1:-}"
PROJECT_VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[ -n "$VERSION" ] || VERSION="$PROJECT_VERSION"
[ -n "$VERSION" ] || err "could not determine version (pass it as an argument)"
VERSION="${VERSION#v}"   # tolerate a leading v
[ "$VERSION" = "$PROJECT_VERSION" ] || err "version $VERSION does not match project.yml ($PROJECT_VERSION)"
TAG="v$VERSION"
SOURCE_COMMIT="$(git rev-parse HEAD)"
note "Releasing $APP_NAME $TAG from $SOURCE_COMMIT"

# Refuse to overwrite an existing tag/release silently.
if gh api "repos/$APP_REPO/git/ref/tags/$TAG" >/dev/null 2>&1; then
  err "tag $TAG already exists on $APP_REPO (bump MARKETING_VERSION first)"
fi
if gh release view "$TAG" --repo "$APP_REPO" >/dev/null 2>&1; then
  err "release $TAG already exists on $APP_REPO (bump MARKETING_VERSION first)"
fi

# Working tree should be clean so the release matches what's committed.
if [ -n "$(git status --porcelain)" ]; then
  err "working tree has uncommitted changes; commit or stash before releasing"
fi
git fetch --quiet origin
git merge-base --is-ancestor "$SOURCE_COMMIT" origin/HEAD \
  || err "source commit $SOURCE_COMMIT is not reachable from origin/HEAD"

if [ "${RELEASE_ALLOW_ADHOC:-0}" != "1" ]; then
  case "${CODE_SIGN_IDENTITY:-}" in
    "Developer ID Application:"*) ;;
    *) err "public releases require a Developer ID Application identity" ;;
  esac
  [ -n "${DEVELOPMENT_TEAM:-}" ] || err "public releases require DEVELOPMENT_TEAM"
  [ -n "${NOTARY_PROFILE:-}" ] || err "public releases require NOTARY_PROFILE"
fi

CASK_FILE="$TAP_DIR/Casks/$CASK_FILE_NAME"
if [ "${SKIP_TAP:-0}" != "1" ]; then
  [ -d "$TAP_DIR" ] || err "tap checkout not found at $TAP_DIR"
  [ -f "$CASK_FILE" ] || err "cask not found at $CASK_FILE (create it once, then re-run)"
  if [ -n "$(git -C "$TAP_DIR" status --porcelain)" ]; then
    err "tap working tree has uncommitted changes; commit or stash before releasing"
  fi
  git -C "$TAP_DIR" fetch --quiet origin
  TAP_UPSTREAM="$(git -C "$TAP_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  [ -n "$TAP_UPSTREAM" ] || err "tap branch has no upstream; configure it before releasing"
  read -r TAP_BEHIND TAP_AHEAD < <(git -C "$TAP_DIR" rev-list --left-right --count "HEAD...$TAP_UPSTREAM")
  [ "$TAP_BEHIND" -eq 0 ] && [ "$TAP_AHEAD" -eq 0 ] \
    || err "tap must be synchronized with $TAP_UPSTREAM before releasing"
fi

note "Running lint and unit tests"
make lint
make CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test-unit
note "Building test bundles"
make CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build-for-testing

# --- Build -----------------------------------------------------------------
note "Building Release $APP_NAME.app"
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" make build
else
  make build
fi

APP_PATH="build/DerivedData/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || err "built app not found at $APP_PATH"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
[ "$BUILT_VERSION" = "$VERSION" ] || err "built app version $BUILT_VERSION does not match release version $VERSION"
codesign --verify --deep --strict "$APP_PATH"
if [ "${RELEASE_ALLOW_ADHOC:-0}" != "1" ]; then
  SIGNING_DETAILS="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)"
  [[ "$SIGNING_DETAILS" == *"Authority=Developer ID Application"* ]] \
    || err "built app is not signed by a Developer ID Application authority"
  [[ "$SIGNING_DETAILS" == *"TeamIdentifier=$DEVELOPMENT_TEAM"* ]] \
    || err "built app team does not match DEVELOPMENT_TEAM"
fi

# --- Zip -------------------------------------------------------------------
ZIP="build/$APP_NAME-$VERSION.zip"
note "Zipping -> $ZIP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
note "pre-notarization sha256: $SHA256"

if [ "${RELEASE_ALLOW_ADHOC:-0}" != "1" ]; then
  note "Submitting $ZIP to notarization"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$ZIP"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP"
fi
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
note "sha256: $SHA256"

# --- GitHub release --------------------------------------------------------
note "Creating GitHub release $TAG on $APP_REPO"
gh release create "$TAG" "$ZIP" \
  --repo "$APP_REPO" \
  --target "$SOURCE_COMMIT" \
  --title "$APP_NAME $VERSION" \
  --generate-notes

DOWNLOAD_URL="https://github.com/$APP_REPO/releases/download/$TAG/$APP_NAME-$VERSION.zip"
note "Asset: $DOWNLOAD_URL"

# --- Update the tap --------------------------------------------------------
if [ "${SKIP_TAP:-0}" = "1" ]; then
  note "SKIP_TAP=1 set; not updating the tap."
  note "Done. sha256=$SHA256"
  exit 0
fi

note "Updating cask $CASK_FILE"
# Replace the version "..." and sha256 "..." lines in place.
/usr/bin/sed -i '' \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 \".*\"/  sha256 \"$SHA256\"/" \
  "$CASK_FILE"

# Sanity check the edit landed.
grep -q "version \"$VERSION\"" "$CASK_FILE" || err "failed to update version in cask"
grep -q "sha256 \"$SHA256\"" "$CASK_FILE" || err "failed to update sha256 in cask"

note "Committing and pushing tap"
git -C "$TAP_DIR" add "Casks/$CASK_FILE_NAME"
git -C "$TAP_DIR" commit -m "Update $APP_NAME to $TAG"
git -C "$TAP_DIR" push

note "Released $APP_NAME $TAG and updated the tap."
echo
echo "Verify with:"
echo "  brew update && brew upgrade --cask lucataco/tap/info"
echo "  # or fresh: brew install --cask lucataco/tap/info"
