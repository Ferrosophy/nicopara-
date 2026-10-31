#!/bin/bash
# Builds an unsigned Release IPA with xtool and names it after the app
# version, e.g. xtool/NicoPlayer-0.0.1-1.ipa. Run from Linux or WSL:
#
#     bash scripts/build_ipa.sh
set -euo pipefail

cd "$(dirname "$0")/.."
SWIFTLY_ENV="${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
if [ -f "$SWIFTLY_ENV" ]; then . "$SWIFTLY_ENV"; fi
export PATH="$HOME/.local/bin:$PATH"

read -r VERSION BUILD < <(python3 -c '
import plistlib
info = plistlib.load(open("NicoPlayer/Resources/xtool-Info.plist", "rb"))
print(info["CFBundleShortVersionString"], info["CFBundleVersion"])
')

xtool dev build --ipa -c release
OUTPUT="xtool/NicoPlayer-$VERSION-$BUILD.ipa"
mv -f xtool/NicoPlayer.ipa "$OUTPUT"
echo "Wrote $OUTPUT"
