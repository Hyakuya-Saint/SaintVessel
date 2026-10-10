#!/usr/bin/env bash
# Builds the Android plugin AAR and installs it where Godot expects it.
# Needs: JDK 17, Android SDK (platform 34), and Gradle 8.5+ on PATH (CI installs it).
# Run tools/fetch-models.sh first so the .task models are bundled.
set -euo pipefail

cd "$(dirname "$0")/../plugin"
gradle assembleRelease --no-daemon

OUT="../android/plugins"
mkdir -p "$OUT"
AAR="$(ls build/outputs/aar/*-release.aar | head -n 1)"
cp "$AAR" "$OUT/SaintTracking.release.aar"
cp "$AAR" "$OUT/SaintTracking.debug.aar"
ls -lh "$OUT"
