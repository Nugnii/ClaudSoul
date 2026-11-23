#!/usr/bin/env bash
# СУДИТ: scripts/statusline-claudsoul.sh
# test_statusline_claudsoul.sh — «Проверка результата» statusline-claudsoul.sh меряет объявленный результат.
#
# Результат: строка статуса, собранная из stdin-JSON, несёт модель и каталог; при активной фазе
#            ablation — сегмент с фазой и счётом очереди, совпадающими с `phase.sh status` по тому же
#            маркеру и журналу; без маркера, с пустой фазой и с пустым stdin сегмента нет.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Тринадцать тестов упоминают инструмент, ни один его не гоняет —
# все зелены под заглушкой (`pattern-marker-matches-form-not-role`). Маркер и журнал подкладываются
# через HOME, `phase.sh` читает их же через ABLATION_DIR. Команда БЕРЁТСЯ из шапки инструмента; её
# хвост «печатает фазу…» — пояснение, а не аргументы, и отсекается вместе с «даёт 0»/«—».
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/statusline-claudsoul.sh"
PHASE="$REPO/scripts/ablation/phase.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—|печатает).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *statusline-claudsoul.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }
hasnt() { grep -Fq -- "$2" <<< "$OUT" && bad "$1" "лишняя строка «$2»" || ok; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; A="$H/.claude/ablation"
IN='{"model":{"display_name":"Fable"},"workspace":{"current_dir":"/x/y/proj"}}'

run_tool() {   # $1 — stdin
    OUT=$(cd "$REPO" && printf '%s' "$1" | HOME="$H" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: маркера нет — модель и каталог, без сегмента фазы -------------------------------------
rm -rf "$H"; mkdir -p "$H"; run_tool "$IN"
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
[ "$OUT" = "Fable · proj" ] && ok || bad T1 "ожидалось «Fable · proj», получено «${OUT}»"

# --- T2: активная фаза — сегмент с фазой и счётом очереди ----------------------------------------
mkdir -p "$A"; printf '{"phase":"phase-2","since":"2026-09-01T09:00:00Z"}\n' > "$A/active-phase.json"
printf '{"e":"queue","ts":"2026-09-01T10:00:00Z"}\n{"e":"queue","ts":"2026-09-02T10:00:00Z"}\n{"e":"pair_done","ts":"2026-09-03T10:00:00Z"}\n{"e":"queue","ts":"2026-09-04T10:00:00Z"}\n' > "$A/journal.jsonl"
run_tool "$IN"
[ "$OUT" = "Fable · proj · 🧪 ablation phase-2 · очередь 3/20" ] && ok || bad T2 "получено «${OUT}»"

# --- T3: фаза и счёт совпадают с phase.sh status по тем же маркеру и журналу ------------------
if [ -f "$PHASE" ]; then
    st=$(ABLATION_DIR="$A" bash "$PHASE" status 2>&1)
    ph=$(printf '%s\n' "$st" | jq -r '.phase // empty' 2>/dev/null | head -1)
    qn=$(printf '%s\n' "$st" | jq -r '.queued // empty' 2>/dev/null | head -1)
    [ -n "$ph" ] && [ -n "$qn" ] && ok || bad T3 "phase.sh status не дал фазу и очередь: $st"
    has T3 "ablation ${ph:-?} · очередь ${qn:-?}/20"
else
    echo "T3 пропущена: нет $PHASE"
fi

# --- T4: маркер есть, фаза пуста — сегмента нет ------------------------------------------------
printf '{"phase":""}\n' > "$A/active-phase.json"; run_tool "$IN"
[ "$OUT" = "Fable · proj" ] && ok || bad T4 "получено «${OUT}»"
hasnt T4 '🧪'

# --- T5: пустой stdin — модель по умолчанию, без падения ----------------------------------------
rm -rf "$A"; run_tool ""
[ "$RC" -eq 0 ] && ok || bad T5 "rc=$RC — $OUT"
[ "$OUT" = "Claude" ] && ok || bad T5 "получено «${OUT}»"

echo ""
echo "statusline-claudsoul tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
