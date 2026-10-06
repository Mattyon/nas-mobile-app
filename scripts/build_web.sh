#!/bin/bash
# Build the web version of the app on the NAS and publish it at https://<gateway>/app/.
#
# The web build is how the app reaches an iPhone without an Apple developer account:
# open the URL in Safari -> Share -> Add to Home Screen. The NAS gateway serves it
# (ai-gateway/app/webapp.py) from config/webapp, same origin as the API.
#
# Runs Flutter in a throwaway Ubuntu container with the SDK from $FLUTTER_SDK (the
# version this repo builds with), so nothing is installed on the host and nothing
# depends on a desktop machine. Usage, from the repo root on the NAS:
#
#   scripts/build_web.sh            analyze + test + build + publish
#   scripts/build_web.sh --no-test  skip analyze/test (e.g. a docs-only change)
#
# Publishing is a directory swap, so a failed build never leaves half an app online.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
FLUTTER_SDK=${FLUTTER_SDK:-/mnt/cache/appdata/flutter-sdk/flutter}
PUB_CACHE_DIR=${PUB_CACHE_DIR:-/mnt/cache/appdata/flutter-sdk/pub-cache}
DEST=${DEST:-/mnt/cache/appdata/nas-stack/config/webapp}
# Ubuntu 24.04, not Debian 12: on bookworm flutter_tester segfaults at random (always
# at the same address), killing test files mid-run; on noble the suite passes cleanly.
IMAGE=${IMAGE:-ubuntu:24.04}
RUN_TESTS=1; [ "${1:-}" = "--no-test" ] && RUN_TESTS=0

[ -x "$FLUTTER_SDK/bin/flutter" ] || { echo "no Flutter SDK at $FLUTTER_SDK"; exit 1; }
mkdir -p "$PUB_CACHE_DIR"

docker run --rm -i \
    -v "$REPO:/src" -v "$FLUTTER_SDK:/opt/flutter" -v "$PUB_CACHE_DIR:/pub-cache" \
    -e PUB_CACHE=/pub-cache -e RUN_TESTS="$RUN_TESTS" -e CI=true -w /src "$IMAGE" bash -s <<'IN_CONTAINER'
set -euo pipefail
# flutter_tester crashes on load without fonts and a GL library (every test file failed).
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq git curl unzip xz-utils ca-certificates \
    libglu1-mesa fontconfig fonts-dejavu-core >/dev/null 2>&1
git config --global --add safe.directory '*'
export PATH=/opt/flutter/bin:$PATH
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version | head -1
flutter pub get >/dev/null
if [ "$RUN_TESTS" = 1 ]; then
    flutter analyze --no-fatal-infos --no-fatal-warnings lib test | tail -3
    flutter test 2>&1 | tail -2
fi
flutter build web --release --base-href /app/ 2>&1 | tail -2
chown -R "$(stat -c %u:%g /src)" /src/build /src/.dart_tool 2>/dev/null || true
IN_CONTAINER

[ -f "$REPO/build/web/index.html" ] || { echo "build produced no index.html"; exit 1; }
rm -rf "$DEST.new"; cp -a "$REPO/build/web" "$DEST.new"
rm -rf "$DEST.old"; [ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$DEST.new" "$DEST" && rm -rf "$DEST.old"
echo "published: $(du -sh "$DEST" | cut -f1) at $DEST ($(grep -o '"version":"[^"]*"' "$DEST/version.json" 2>/dev/null))"
