#!/usr/bin/env bash
# Запуск Godot из скриптов проекта.
#   tools/godot.sh --path . res://scenes/slice.tscn
# Linux без монитора (сервер, облако, CI): виртуальный экран Xvfb и программный Vulkan (lavapipe).
# Windows (Git Bash, как у Claude Code на ПК автора): обычный Godot с видеокартой, без Xvfb;
# Godot ищется в $GODOT, иначе самый новый по имени файла Godot*.exe из C:\Godot и C:\
# (как C:\Godot_v4.7.2-stable_win64.exe); консольный …_console.exe — в первую очередь, как в shot.ps1.
# Без Git Bash — tools\shot.cmd (PowerShell).
#   tools/godot.sh --which — только напечатать путь к Godot (tests/run_all.sh, skirmish_headless.sh, build_windows.sh
#   запускают его сами, без Xvfb: им хватает --headless)
set -euo pipefail
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    if [ -z "${GODOT:-}" ]; then
      # find без C:\Godot кончается ошибкой — «|| true», иначе set -e молча обрывает скрипт
      CANDS="$( { find /c/Godot -maxdepth 2 -iname 'Godot*.exe'; find /c/ -maxdepth 1 -iname 'Godot*.exe'; } 2>/dev/null || true)"
      # сортировка по имени файла, а не по пути: иначе любой Godot из C:\ обгонял бы более новый в C:\Godot
      pick() { grep -i "$1" <<<"$CANDS" | awk -F/ '{print $NF "\t" $0}' | sort | tail -n1 | cut -f2- || true; }
      GODOT="$(pick '_console\.exe$')"
      [ -n "$GODOT" ] || GODOT="$(pick '\.exe$')"
    fi
    [ -n "${GODOT:-}" ] || { echo "Godot не найден: положите его в C:\\Godot (или файлом прямо в C:\\) или задайте GODOT=путь" >&2; exit 1; }
    if [ "${1:-}" = "--which" ]; then echo "$GODOT"; exit 0; fi
    exec "$GODOT" "$@"
    ;;
esac
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
if [ "${1:-}" = "--which" ]; then echo "$GODOT"; exit 0; fi
if [ -f /usr/share/vulkan/icd.d/lvp_icd.json ] && [ -z "${VK_ICD_FILENAMES:-}" ]; then
  export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
fi
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  exec xvfb-run -a -s "-screen 0 ${XVFB_SIZE:-1920x1080x24}" "$GODOT" "$@"
fi
exec "$GODOT" "$@"
