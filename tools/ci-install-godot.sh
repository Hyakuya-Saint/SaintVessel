#!/usr/bin/env bash
# Downloads the Godot editor + export templates (Linux, headless use).
set -euo pipefail

V="${GODOT_VERSION:-4.3}"
R="${GODOT_RELEASE:-stable}"
BASE="https://github.com/godotengine/godot/releases/download/${V}-${R}"

mkdir -p "$HOME/godot"
curl -fL --retry 3 -o /tmp/godot.zip "$BASE/Godot_v${V}-${R}_linux.x86_64.zip"
unzip -q -o /tmp/godot.zip -d "$HOME/godot"
mv "$HOME/godot/Godot_v${V}-${R}_linux.x86_64" "$HOME/godot/godot"
chmod +x "$HOME/godot/godot"

curl -fL --retry 3 -o /tmp/templates.tpz "$BASE/Godot_v${V}-${R}_export_templates.tpz"
mkdir -p /tmp/tpl "$HOME/.local/share/godot/export_templates/${V}.${R}"
unzip -q -o /tmp/templates.tpz -d /tmp/tpl
cp -r /tmp/tpl/templates/* "$HOME/.local/share/godot/export_templates/${V}.${R}/"

if [ -n "${GITHUB_PATH:-}" ]; then echo "$HOME/godot" >> "$GITHUB_PATH"; fi
"$HOME/godot/godot" --version || true
