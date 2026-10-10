#!/usr/bin/env bash
# Prepares Godot's Android gradle export: build template, signing keystore, editor settings.
# Optional repo secrets for a stable signing key (so updates install over older builds):
#   ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_USER, ANDROID_KEYSTORE_PASSWORD
set -euo pipefail

V="${GODOT_VERSION:-4.3}"
R="${GODOT_RELEASE:-stable}"
cd "$(dirname "$0")/.."

# ---- gradle build template (what "Project > Install Android Build Template" does)
mkdir -p android/build
unzip -q -o "$HOME/.local/share/godot/export_templates/${V}.${R}/android_source.zip" -d android/build
echo "${V}.${R}" > android/.build_version
touch android/build/.gdignore

# ---- signing key
KS="$RUNNER_TEMP/saintvessel.keystore"
if [ -n "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$KS"
  KUSER="${ANDROID_KEYSTORE_USER:-saintvessel}"
  KPASS="${ANDROID_KEYSTORE_PASSWORD:?ANDROID_KEYSTORE_PASSWORD is required with ANDROID_KEYSTORE_BASE64}"
else
  KUSER="saintvessel"
  KPASS="saintvessel-ci"
  keytool -genkeypair -v -keystore "$KS" -alias "$KUSER" -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass "$KPASS" -keypass "$KPASS" -dname "CN=Saint Vessel, O=SaintVessel, C=US" >/dev/null 2>&1
  echo "No keystore secret set: using a throw-away key (each build gets a new signature)."
fi
{
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$KS"
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_USER=$KUSER"
  echo "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$KPASS"
  echo "GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$KS"
  echo "GODOT_ANDROID_KEYSTORE_DEBUG_USER=$KUSER"
  echo "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=$KPASS"
} >> "$GITHUB_ENV"

# ---- editor settings (SDK + JDK locations)
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:?ANDROID_HOME not set}}"
mkdir -p "$HOME/.config/godot"
for f in "editor_settings-${V}.tres" "editor_settings-4.tres"; do
  cat > "$HOME/.config/godot/$f" <<EOT
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA_HOME"
EOT
done
echo "Android export configured."
