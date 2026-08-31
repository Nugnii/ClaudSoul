#!/usr/bin/env bash
# test_attack_r2_quote_erases_own.sh — АТАКА: две процитированных строки стирают
# собственную коррекцию собеседника, стоящую ВНЕ цитаты.
#
# `user_own_speech` копит свои строки в keep[], но в END делает
# `if (doc || quoted >= 2) exit 0` — и молча выбрасывает ВСЁ накопленное, включая
# строки, которые сама же признала собственной речью. Документация функции обещает
# другое: «Печатает ПУСТО, если turn ЦЕЛИКОМ — вставленный документ». Здесь turn не
# целиком документ: цитата — чужая, а последняя строка — прямая речь собеседника.
#
# Порог стоит на счётчике 2, поэтому вердикт переворачивается от ОДНОЙ лишней строки
# цитаты: соседний test_hook_input_lib.sh закрепляет, что при одной строке `>` своя
# речь остаётся («mixed: direct part kept»). Дописать вторую строку цитаты —
# самая обычная форма ответа на пересланный текст.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$HOOKS_DIR/hook-input-lib.sh"
HOOK="$HOOKS_DIR/reformulation-tracker.sh"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
# shellcheck source=/dev/null
source "$LIB"

PASS=0
FAIL=0
TMP=$(mktemp -d)
mkdir -p "$TMP/state"

ONE="ты процитировал отчёт:

> шаг один выполнен

я имел в виду совсем другое, переделай"
TWO="ты процитировал отчёт:

> шаг один выполнен
> шаг два выполнен

я имел в виду совсем другое, переделай"

# t1 — контроль: с ОДНОЙ строкой цитаты своя речь сохраняется
own=$(user_own_speech "$ONE")
if grep -qF "я имел в виду" <<< "$own"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [t1 контроль: одна строка цитаты не должна стирать свою речь]"; fi

# t2 — АТАКА: со ВТОРОЙ строкой цитаты своя речь исчезает целиком
own=$(user_own_speech "$TWO")
if grep -qF "я имел в виду" <<< "$own"; then PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo "FAIL [t2 своя коррекция вне цитаты стёрта]: две строки '>' обнулили вывод, получено: '${own}'"
fi

# t3 — чужая цитата при этом обязана быть отброшена (граница не должна уехать в другую сторону)
own=$(user_own_speech "$TWO")
if grep -qF "шаг один выполнен" <<< "$own"; then
    FAIL=$((FAIL + 1)); echo "FAIL [t3 тело цитаты обязано отбрасываться]"
else PASS=$((PASS + 1)); fi

# t4 — сквозной: reformulation-tracker теряет BACKWARD на настоящей коррекции
if command -v jq >/dev/null 2>&1; then
    out=$(jq -n --arg s "r2q" --arg p "$TWO" '{session_id:$s,prompt:$p,transcript_path:""}' \
        | STATE_DIR="$TMP/state" bash "$HOOK" 2>&1)
    if grep -qF "BACKWARD" <<< "$out"; then PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        echo "FAIL [t4 сквозной: настоящая коррекция не породила BACKWARD]: вывод хука пуст"
    fi
else
    echo "SKIP t4: jq недоступен"
fi

echo ""
echo "attack r2 quote-erases-own: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
