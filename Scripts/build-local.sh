#!/bin/bash
# Reproducible local build only; does not install, quit apps, or change permissions.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${ICE_DERIVED_DATA:-$ROOT/build/local}"
if ! xcrun --find xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    if [ -d /Applications/Xcode.app/Contents/Developer ]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
        echo "Full Xcode is required; Command Line Tools alone cannot build this project." >&2
        exit 1
    fi
fi

# Prefer the existing local development certificate so updates retain the same
# designated requirement. Set ICE_CODE_SIGN_IDENTITY=- for an ad-hoc build.
IDENTITY="${ICE_CODE_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
fi
TEAM="${DEVELOPMENT_TEAM:-}"
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != - ] && [ -z "$TEAM" ]; then
    TEAM="$(security find-certificate -c 'Apple Development' -p 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null \
        | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
fi
IDENTITY="${IDENTITY:--}"

xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
    PROVISIONING_PROFILE_SPECIFIER= ENABLE_HARDENED_RUNTIME=NO build

APP="$DERIVED/Build/Products/Release/Ice.app"
codesign --verify --deep --strict "$APP"
echo "Built and verified: $APP"
