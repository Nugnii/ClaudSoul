#!/usr/bin/env bash
# test_correction_triggers_analysis.sh — поправка о поведении требует разбора причин.
#
# Результат: сигнал поправки собеседника доходит до гейта разбора и требует цепочки
# Проверка результата: bash hooks/tests/test_correction_triggers_analysis.sh даёт 0
#
# Повод, измеренный 29 августа 2026 на самом агенте. Гейт разбора слушал два сигнала —
# переделку файла и полосу упавших команд, — то есть предмет разбора был задан АРТЕФАКТОМ
# (файл, команда). Поведение агента артефактом не является и в предмет не попадало.
#
# Продюсер сигнала при этом существовал и работал: `user-correction-guard` пишет
# `correction-fired-<SID>.jsonl`, таких файлов в состоянии было 27. Между контуром
# поведения и контуром разбора дефектов не было моста.
#
# Цена: собеседник дважды поправил поведение агента («перестал сам коммитить»), и оба раза
# разбор не запустился — поправка была принята к сведению и закрыта текстовым правилом.
# Тот же класс, что записан знанием `case-2026-08-29-fix-addressed-to-artifact-not-subject`:
# действие задано артефактом находки, а не её предметом.
#
# КОНТРПРИМЕР: сессия без файла поправки требовать цепочку по этому поводу не должна —
# иначе гейт станет фоном, а не сигналом.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$HOOKS/five-whys-gate.sh"
[ -f "$GATE" ] || { echo "FAIL: нет $GATE"; exit 1; }

PASS=0; FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

run_gate() {
    STATE_DIR="$TMP" CLAUDE_CODE_SESSION_ID="$1" bash "$GATE" <<PAYLOAD
{"tool_name":"Edit","tool_input":{"file_path":"$TMP/x.sh"},"session_id":"$1"}
PAYLOAD
}

# --- T1: поправка есть → гейт требует разбора и называет повод ---
SID="with-correction"
printf '{"date":"2026-08-29T11:50:00Z","kind":"behavior"}\n' > "$TMP/correction-fired-${SID}.jsonl"
OUT=$(run_gate "$SID")
if grep -q 'поправка собеседника' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1]: поправка не названа поводом разбора: $OUT"; fi
if grep -q 'ВШИРЬ ПО ПРОЯВЛЕНИЯМ' <<< "$OUT"; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T1b]: порядок разбора не потребован"; fi

# --- T2: КОНТРПРИМЕР — без поправки этого повода нет ---
SID2="clean"
OUT2=$(run_gate "$SID2")
if grep -q 'поправка собеседника' <<< "$OUT2"; then
    FAIL=$((FAIL+1)); echo "FAIL [T2]: повод назван без сигнала поправки — гейт станет фоном"
else PASS=$((PASS+1)); fi

# --- T3: продюсер и потребитель сходятся на ОДНОМ имени файла ---
# Предмет проверки — согласие имён, а не их внутренности: разойдутся молча, как уже
# разошлись `CLAUDE_STATE_DIR` и `STATE_DIR` в counter-bump тем же днём.
PROD=$(grep -oE 'correction-fired-\$\{?[A-Za-z_]+\}?\.jsonl' "$HOOKS/user-correction-guard.sh" | head -1 | sed 's/\$[{]*[A-Za-z_]*[}]*/SID/')
CONS=$(grep -oE 'correction-fired-\$\{?[A-Za-z_]+\}?\.jsonl' "$GATE" | head -1 | sed 's/\$[{]*[A-Za-z_]*[}]*/SID/')
if [ -n "$PROD" ] && [ "$PROD" = "$CONS" ]; then PASS=$((PASS+1))
else FAIL=$((FAIL+1)); echo "FAIL [T3]: продюсер пишет '$PROD', гейт читает '$CONS'"; fi

echo "correction triggers analysis: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
