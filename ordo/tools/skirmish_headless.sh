#!/usr/bin/env bash
# Автобои «Города» без графики (ТЗ 14; ARCHITECTURE §15): N матчей ИИ против ИИ на карте «Долина»,
# каждый — с проверкой детерминизма повтором (контрольные суммы раз в 30 тактов) и записью повтора
# в renders/skirmish/match_NN_seedS.ordorep.
#   tools/skirmish_headless.sh                 — 2 матча по 15 мин
#   tools/skirmish_headless.sh 10 --minutes=25 --seed=100 --difficulty=1
#   tools/skirmish_headless.sh 1 --stub        — на заглушках договора, даже если пакеты уже слиты
# Журнал — renders/skirmish/skirmish.log. Код выхода 1 — повтор разошёлся с матчем.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
N="${1:-2}"
if [[ "$N" =~ ^[0-9]+$ ]]; then shift || true; else N=2; fi
OUT="$ROOT/renders/skirmish"
mkdir -p "$OUT" && touch "$ROOT/renders/.gdignore"
LOG="$OUT/skirmish.log"
timeout "${SKIRMISH_TIMEOUT:-3600}" "$GODOT" --headless --path "$ROOT" --script res://tools/skirmish_headless.gd -- \
  --n="$N" "$@" 2>&1 | grep -vE "^Godot Engine|^$" | tee "$LOG"
code=${PIPESTATUS[0]}
grep -q "ИТОГ: ВСЁ ПРОШЛО" "$LOG" && [ "$code" -eq 0 ] && exit 0
exit 1
