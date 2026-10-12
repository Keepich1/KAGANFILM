#!/usr/bin/env bash
# Видео сцены: кадры PNG через --write-movie, затем MP4 (H.264) через ffmpeg.
#   tools/movie.sh res://scenes/slice.tscn out.mp4 [секунды=20] [--size=1280x720] [--cam=...]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# кадры проверки не импортируются в проект
mkdir -p "$ROOT/renders" && touch "$ROOT/renders/.gdignore"
SCENE="$1"; OUT="$(realpath -m "$2")"; SECS="${3:-20}"; shift 3 || shift $#
SIZE=1280x720; EXTRA=()
for a in "$@"; do
  case "$a" in
    --size=*) SIZE="${a#--size=}" ;;
    *) EXTRA+=("$a") ;;
  esac
done
TMP="$(mktemp -d)"
FRAMES=$((SECS * 30))
XVFB_SIZE="${SIZE}x24" "$ROOT/tools/godot.sh" --path "$ROOT" --resolution "$SIZE" --write-movie "$TMP/f.png" \
  --audio-driver Dummy --fixed-fps 30 --quit-after "$FRAMES" "$SCENE" -- "${EXTRA[@]}" 2>&1 | grep -vE "ALSA|audio|^\s*$" | tail -5 || true
# кадры пишутся в размер окна проекта — приводим к заказанному размеру
ffmpeg -y -loglevel error -framerate 30 -i "$TMP/f%08d.png" -vf "scale=${SIZE/x/:}:flags=lanczos" \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -preset slow -an "$OUT"
rm -rf "$TMP"
echo "OK $OUT"
