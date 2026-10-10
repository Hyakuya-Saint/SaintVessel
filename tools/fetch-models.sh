#!/usr/bin/env bash
# Downloads the MediaPipe Tasks models into the plugin's assets (they get bundled into the plugin AAR).
#   POSE_VARIANT=lite|full|heavy   (default: lite -> fastest, fine for mid-range phones)
set -euo pipefail

cd "$(dirname "$0")/.."
DEST="plugin/src/main/assets"
POSE_VARIANT="${POSE_VARIANT:-lite}"
BASE="https://storage.googleapis.com/mediapipe-models"
mkdir -p "$DEST"

echo "Fetching pose_landmarker_${POSE_VARIANT} ..."
curl -fL --retry 3 -o "$DEST/pose_landmarker.task" \
  "$BASE/pose_landmarker/pose_landmarker_${POSE_VARIANT}/float16/latest/pose_landmarker_${POSE_VARIANT}.task"

echo "Fetching face_landmarker ..."
curl -fL --retry 3 -o "$DEST/face_landmarker.task" \
  "$BASE/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"

ls -lh "$DEST"
