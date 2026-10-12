#!/usr/bin/env bash
# Импорт новых ресурсов (glb, png) без редактора: создаёт ordo/.godot/imported.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
"$GODOT" --headless --path "$ROOT" --import 2>&1 | grep -vE "ALSA|audio|^\s*$|at: " || true
