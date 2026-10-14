#!/usr/bin/env bash
# Кадр сцены в PNG (Linux — без монитора; Windows — видеокартой ПК, на миг откроется окно игры).
#   tools/shot.sh res://scenes/slice.tscn out.png [--at=6] [--cam=CamCamp] [--size=1920x1080] [--quality=low]
# Время сцены идёт ровно 1/30 с за кадр (--fixed-fps 30), поэтому кадр повторяем.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# кадры проверки не импортируются в проект
mkdir -p "$ROOT/renders" && touch "$ROOT/renders/.gdignore"
SCENE="$1"; OUT="$(realpath -m "$2")"; shift 2
# Windows (Git Bash): Godot ждёт путь вида C:/…, а не /c/…
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) OUT="$(cygpath -m "$OUT")" ;; esac
SIZE=1920x1080; EXTRA=()
for a in "$@"; do
  case "$a" in
    --size=*) SIZE="${a#--size=}" ;;
    *) EXTRA+=("$a") ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
XVFB_SIZE="${SIZE}x24" timeout "${SHOT_TIMEOUT:-900}" "$ROOT/tools/godot.sh" --path "$ROOT" --resolution "$SIZE" \
  --audio-driver Dummy --fixed-fps 30 "$SCENE" -- --shot="$OUT" "${EXTRA[@]}" 2>&1 | grep --line-buffered -vE "ALSA|audio driver|audio_server|alsa|^\s*$" || true
[ -f "$OUT" ] && echo "OK $OUT" || { echo "НЕТ КАДРА $OUT"; exit 1; }
