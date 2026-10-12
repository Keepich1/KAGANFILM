#!/usr/bin/env bash
# Кадр сцены в PNG без монитора.
#   tools/shot.sh res://scenes/slice.tscn out.png [--at=6] [--cam=CamCamp] [--size=1920x1080] [--quality=low]
# Время сцены идёт ровно 1/30 с за кадр (--fixed-fps 30), поэтому кадр повторяем.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCENE="$1"; OUT="$(realpath -m "$2")"; shift 2
SIZE=1920x1080; EXTRA=()
for a in "$@"; do
  case "$a" in
    --size=*) SIZE="${a#--size=}" ;;
    *) EXTRA+=("$a") ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
XVFB_SIZE="${SIZE}x24" timeout "${SHOT_TIMEOUT:-900}" "$ROOT/tools/godot.sh" --path "$ROOT" --resolution "$SIZE" \
  --fixed-fps 30 "$SCENE" -- --shot="$OUT" "${EXTRA[@]}" 2>&1 | grep -vE "ALSA|audio driver|audio_server|alsa|^\s*$" || true
[ -f "$OUT" ] && echo "OK $OUT" || { echo "НЕТ КАДРА $OUT"; exit 1; }
