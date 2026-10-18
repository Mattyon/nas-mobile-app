#!/bin/bash
# Build the Android app bundle on the NAS -- no desktop machine needed (the work Mac must
# not build or hold app secrets). Flutter comes from $FLUTTER_SDK (as for the web build),
# JDK 21 from a small builder image, the Android SDK and Gradle caches from persistent
# folders on the NVMe, so only the first run downloads them.
#
#   scripts/build_android.sh            test + build
#   scripts/build_android.sh --no-test  build only
#
# The version comes from VERSION (x.y.z+N). Signing uses android/key.properties and
# android/upload-keystore.jks (both gitignored); missing ones are copied from the masters
# in /boot/config/app-secrets (root-only). The bundle is checked to be signed, and a copy
# is kept in $OUT/<version>/. Publish it with scripts/play_publish.py upload.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
FLUTTER_SDK=${FLUTTER_SDK:-/mnt/cache/appdata/flutter-sdk/flutter}
PUB_CACHE_DIR=${PUB_CACHE_DIR:-/mnt/cache/appdata/flutter-sdk/pub-cache}
ANDROID_SDK=${ANDROID_SDK:-/mnt/cache/appdata/android-sdk}
GRADLE_HOME=${GRADLE_HOME:-/mnt/cache/appdata/gradle-home}
SECRETS=${SECRETS:-/boot/config/app-secrets}
OUT=${OUT:-/mnt/cache/appdata/app-builds}
IMAGE=${IMAGE:-nas-app-builder:jdk21}
CMDLINE_TOOLS=${CMDLINE_TOOLS:-https://dl.google.com/android/repository/commandlinetools-linux-9862592_latest.zip}
RUN_TESTS=1; [ "${1:-}" = "--no-test" ] && RUN_TESTS=0

VERSION=$(tr -d ' \t\r\n' < "$REPO/VERSION")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]] || { echo "bad VERSION: '$VERSION'"; exit 1; }
[ -x "$FLUTTER_SDK/bin/flutter" ] || { echo "no Flutter SDK at $FLUTTER_SDK"; exit 1; }
for f in key.properties upload-keystore.jks; do
    [ -f "$REPO/android/$f" ] || install -m 600 "$SECRETS/$f" "$REPO/android/$f"
done
mkdir -p "$ANDROID_SDK" "$GRADLE_HOME" "$PUB_CACHE_DIR" "$OUT"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker build -q -t "$IMAGE" - <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openjdk-21-jdk-headless git curl unzip xz-utils ca-certificates libglu1-mesa fontconfig \
      fonts-dejavu-core && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi

echo "building $VERSION ..."
docker run --rm -i \
    -v "$REPO:/src" -v "$FLUTTER_SDK:/opt/flutter" -v "$PUB_CACHE_DIR:/pub-cache" \
    -v "$ANDROID_SDK:/opt/android-sdk" -v "$GRADLE_HOME:/root/.gradle" \
    -e ANDROID_HOME=/opt/android-sdk -e ANDROID_SDK_ROOT=/opt/android-sdk \
    -e PUB_CACHE=/pub-cache -e CI=true -e VERSION="$VERSION" -e RUN_TESTS="$RUN_TESTS" \
    -e CMDLINE_TOOLS="$CMDLINE_TOOLS" -w /src "$IMAGE" bash -s <<'IN_CONTAINER'
set -euo pipefail
mkdir -p /src/build
git config --global --add safe.directory '*'
export PATH=/opt/flutter/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "first run: installing the Android command-line tools"
    curl -fsSL -o /tmp/clt.zip "$CMDLINE_TOOLS"
    rm -rf /tmp/clt && unzip -q /tmp/clt.zip -d /tmp/clt
    mkdir -p "$ANDROID_HOME/cmdline-tools" && rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv /tmp/clt/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest"
fi
# Gradle installs the platform, build-tools and NDK the project asks for, once licensed.
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager --install platform-tools >/dev/null
flutter config --no-analytics --android-sdk "$ANDROID_HOME" >/dev/null 2>&1 || true
flutter --version | head -1
flutter pub get >/dev/null
if [ "$RUN_TESTS" = 1 ]; then flutter test 2>&1 | tail -1; fi
if ! flutter build appbundle --release --build-name="${VERSION%+*}" --build-number="${VERSION#*+}" \
        --dart-define=APP_VERSION="${VERSION%+*}" > /src/build/flutter-build.log 2>&1; then
    grep -E "What went wrong|error:|Error:|FAILURE|> " /src/build/flutter-build.log | head -40
    echo "--- last lines of build/flutter-build.log:"; tail -40 /src/build/flutter-build.log
    exit 1
fi
tail -2 /src/build/flutter-build.log
AAB=build/app/outputs/bundle/release/app-release.aab
jarsigner -verify "$AAB" >/dev/null 2>&1 && echo "signature: verified" || { echo "signature: NOT verified"; exit 1; }
keytool -printcert -jarfile "$AAB" 2>/dev/null | grep -m1 "Owner:" || true
chown -R "$(stat -c %u:%g /src)" /src/build /src/.dart_tool 2>/dev/null || true
IN_CONTAINER

AAB="$REPO/build/app/outputs/bundle/release/app-release.aab"
mkdir -p "$OUT/$VERSION" && cp -f "$AAB" "$OUT/$VERSION/"
echo "built $VERSION: $AAB ($(du -h "$AAB" | cut -f1)); copy in $OUT/$VERSION/"
