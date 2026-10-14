#!/usr/bin/env bash
# Импорт новых ресурсов (glb, png) без редактора: создаёт ordo/.godot/imported.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Godot ищет tools/godot.sh (Linux и Windows)
"$ROOT/tools/godot.sh" --headless --path "$ROOT" --import 2>&1 | grep -vE "ALSA|audio|^\s*$|at: " || true
