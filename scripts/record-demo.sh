#!/bin/bash
# Records the sample-data demo tour (UITests/DemoTourUITests.swift) from a booted simulator.
# Usage: scripts/record-demo.sh <simulator-udid> [output.mp4]
# Needs XcodeGen and ffmpeg. Uses sample data only (-seedSamples).
set -euo pipefail
UDID="${1:?simulator UDID (xcrun simctl list devices)}"
OUT="${2:-docs/demo.mp4}"
RAW="$(mktemp -d)/raw.mov"

xcodegen generate -q
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3

# Build first so the recording holds only the tour.
xcodebuild build-for-testing -project AiHeart.xcodeproj -scheme AiHeart \
  -destination "id=$UDID" -derivedDataPath build/demo -quiet

xcrun simctl terminate "$UDID" local.aiheart.app 2>/dev/null || true
xcodebuild test-without-building -project AiHeart.xcodeproj -scheme AiHeart \
  -destination "id=$UDID" -derivedDataPath build/demo \
  -only-testing:AiHeartUITests/DemoTourUITests -quiet &
TEST=$!
# Start recording when the app process appears, so the video opens on the app, not the home screen.
until pgrep -f 'AiHeart.app/AiHeart' >/dev/null; do sleep 0.2; done
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RAW" &
REC=$!
wait "$TEST" || true
sleep 1
kill -INT "$REC"; wait "$REC" || true

# Half-size H.264, no audio, small enough for a README.
# Skip the first 8 s (blank launch frames).
ffmpeg -y -loglevel error -ss 8 -i "$RAW" -vf "scale=trunc(iw/4)*2:-2,fps=30" -c:v libx264 -crf 28 \
  -preset slow -pix_fmt yuv420p -an -movflags +faststart "$OUT"
echo "Wrote $OUT"
