#!/usr/bin/env bash
# Все безголовые тесты «Ордо» (ARCHITECTURE §15): tests/test_*.gd по очереди.
#   tests/run_all.sh            — все
#   tests/run_all.sh econ nav   — только те, в имени которых есть «econ» или «nav»
# Тест прошёл, если вышел с кодом 0, напечатал «ИТОГ: ВСЁ ПРОШЛО» и в выводе нет SCRIPT ERROR / ERROR
# (ошибка разбора скрипта вешает SceneTree — её ловит предел времени TEST_TIMEOUT, по умолчанию 900 с).
# Журналы — в renders/tests/<имя>.log (в git не идут).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /opt/godot/godot)}"
LOGS="$ROOT/renders/tests"
mkdir -p "$LOGS" && touch "$ROOT/renders/.gdignore"

tests=()
for f in "$ROOT"/tests/test_*.gd; do
  name="$(basename "$f" .gd)"
  if [ $# -gt 0 ]; then
    keep=0
    for pat in "$@"; do [[ "$name" == *"$pat"* ]] && keep=1; done
    [ $keep -eq 1 ] || continue
  fi
  tests+=("$name")
done

fails=()
for name in "${tests[@]}"; do
  log="$LOGS/$name.log"
  start=$(date +%s)
  timeout "${TEST_TIMEOUT:-900}" "$GODOT" --headless --path "$ROOT" --script "res://tests/$name.gd" > "$log" 2>&1
  code=$?
  secs=$(( $(date +%s) - start ))
  if [ $code -eq 0 ] && grep -q "ИТОГ: ВСЁ ПРОШЛО" "$log" && ! grep -qE "^(SCRIPT )?ERROR" "$log"; then
    printf "  ok    %-28s %4d с\n" "$name" "$secs"
  else
    printf "  FAIL  %-28s %4d с  (код %d, журнал %s)\n" "$name" "$secs" "$code" "$log"
    grep -E "FAIL|ERROR" "$log" | head -8 | sed 's/^/          /'
    fails+=("$name")
  fi
done

echo
if [ ${#fails[@]} -eq 0 ]; then
  echo "ИТОГ: ВСЕ ТЕСТЫ ПРОШЛИ (${#tests[@]})"
else
  echo "ИТОГ: ПРОВАЛЕНО ${#fails[@]} из ${#tests[@]}: ${fails[*]}"
  exit 1
fi
