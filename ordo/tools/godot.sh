#!/usr/bin/env bash
# Запуск Godot из скриптов проекта.
#   tools/godot.sh --path . res://scenes/slice.tscn
# Linux без монитора (сервер, облако, CI): виртуальный экран Xvfb и программный Vulkan (lavapipe).
# Windows (Git Bash, как у Claude Code на ПК автора): обычный Godot с видеокартой, без Xvfb;
# Godot ищется в $GODOT или в C:\Godot (лучше консольный Godot_v4.7.2-stable_win64_console.exe).
set -euo pipefail
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    if [ -z "${GODOT:-}" ]; then
      GODOT="$(find /c/Godot -maxdepth 2 -iname 'Godot*_console.exe' 2>/dev/null | sort | tail -n1)"
      [ -n "$GODOT" ] || GODOT="$(find /c/Godot -maxdepth 2 -iname 'Godot*.exe' 2>/dev/null | sort | tail -n1)"
    fi
    [ -n "${GODOT:-}" ] || { echo "Godot не найден: положите его в C:\\Godot или задайте GODOT=путь" >&2; exit 1; }
    exec "$GODOT" "$@"
    ;;
esac
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
if [ -f /usr/share/vulkan/icd.d/lvp_icd.json ] && [ -z "${VK_ICD_FILENAMES:-}" ]; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
fi
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  exec xvfb-run -a -s "-screen 0 ${XVFB_SIZE:-1920x1080x24}" "$GODOT" "$@"
fi
exec "$GODOT" "$@"
