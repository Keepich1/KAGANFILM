#!/usr/bin/env bash
# Запуск Godot без монитора (сервер, облако, CI): виртуальный экран Xvfb
# и программный Vulkan (lavapipe). На обычном ПК просто откройте проект в Godot.
#   tools/godot.sh --path . res://scenes/slice.tscn
set -euo pipefail
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
if [ -f /usr/share/vulkan/icd.d/lvp_icd.json ] && [ -z "${VK_ICD_FILENAMES:-}" ]; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
fi
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  exec xvfb-run -a -s "-screen 0 ${XVFB_SIZE:-1920x1080x24}" "$GODOT" "$@"
fi
exec "$GODOT" "$@"
