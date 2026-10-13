#!/usr/bin/env bash
# Сборка «Ордо» для Windows: Ordo.exe + Ordo.pck, переносной zip и установщик.
#   tools/build_windows.sh [версия]        → ../build/windows/
# Нужны: Godot 4.7.2 с шаблонами экспорта, makensis (NSIS 3), zip.
# Проверка содержимого: та же сборка под Linux запускается здесь без монитора (--check).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="${1:-0.1.0}"
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
OUT="$ROOT/../build/windows"
rm -rf "$OUT/Ordo" && mkdir -p "$OUT/Ordo"

# номер сборки — в project.godot (application/config/version: подпись внизу главного меню) на время экспорта
cp "$ROOT/project.godot" "$OUT/.project.godot.bak"
trap 'cp "$OUT/.project.godot.bak" "$ROOT/project.godot"; rm -f "$OUT/.project.godot.bak"' EXIT
sed -i "s|^config/name=\(.*\)$|config/name=\1\nconfig/version=\"$VER\"|" "$ROOT/project.godot"

"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT" --export-release "Windows Desktop" "$OUT/Ordo/Ordo.exe" 2>&1 \
  | grep -vE "ALSA|audio|^\s*$" | grep -iE "error|warn|export" || true
[ -f "$OUT/Ordo/Ordo.exe" ] && [ -f "$OUT/Ordo/Ordo.pck" ] || { echo "Экспорт не удался"; exit 1; }

# ПРОЧТИ.txt — UTF-8 с BOM и переводами строк Windows, чтобы Блокнот показал кириллицу
printf '\xEF\xBB\xBF' > "$OUT/Ordo/ПРОЧТИ.txt"
sed 's/$/\r/' "$ROOT/tools/installer/ПРОЧТИ.txt" >> "$OUT/Ordo/ПРОЧТИ.txt"

(cd "$OUT" && rm -f "Ordo-$VER-windows.zip" && zip -q -r -9 "Ordo-$VER-windows.zip" Ordo)

# Установщик: скрипт, значок и файлы игры — в одной папке. makensis нужна UTF-8 локаль,
# иначе на кириллице в путях он падает (makensis 3.09 под Linux)
STAGE="$OUT/.stage" && rm -rf "$STAGE" && mkdir -p "$STAGE"
cp "$OUT/Ordo/"* "$ROOT/tools/installer/ordo.nsi" "$ROOT/tools/installer/ordo.ico" "$STAGE/"
(cd "$STAGE" && LANG=C.UTF-8 LC_ALL=C.UTF-8 makensis -V2 -DVERSION="$VER" -DOUT="$OUT/Ordo-Setup-$VER.exe" ordo.nsi)
rm -rf "$STAGE"
ls -la "$OUT"
