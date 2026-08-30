#!/usr/bin/env bash
# test_output_language_detect.sh — валидность детектора смешения алфавитов.
#
# Зачем: детектор считал нарушением любой токен с двумя азбуками, включая обычные
# русские дефисные композиты («dev-БД», «API-роут»). На живых данных это 2524 из
# 2689 срабатываний — 94% шума. Метрика, построенная на нём, врала в 34 раза, а
# сам класс событий был непригоден как измерение поведения.
# Тест фиксирует границу: дефис разделяет слово, апостроф — нет.
set -uo pipefail

LIB="$(cd "$(dirname "$0")/.." && pwd)/lib/output-language-detect.py"
[ -f "$LIB" ] || { echo "FAIL: $LIB not found"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

PASS=0
FAIL=0

# $1 — текст на вход, $2 — ожидаемый вывод (через запятую, пусто = ничего), $3 — метка
assert_detect() {
    local text="$1" expected="$2" label="$3" actual
    actual=$(printf '%s\n' "$text" | python3 "$LIB" | tr '\n' ',' | sed 's/,$//')
    if [ "$actual" = "$expected" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: ожидалось '$expected', получено '$actual'"; fi
}

# === Нарушения — смешение внутри одного слова ===
assert_detect "в trёх местах"            "trёх"    "T1: латиница внутри русского слова"
assert_detect "сделал коммit вчера"      "коммit"  "T2: латинский хвост у русского слова"
assert_detect "проверил синтаксis"       "синтаксis" "T3: то же, другой хвост"
assert_detect "правил fix'ом"            "fix'ом"  "T4: апостроф НЕ разделяет слово"
assert_detect "много лookup'ов"          "лookup'ов" "T5: исходный кейс правила"

# === Не нарушения — дефисные композиты (94% прежних ложных срабатываний) ===
assert_detect "поднял dev-БД локально"   ""  "T6: dev-БД"
assert_detect "новый API-роут"           ""  "T7: API-роут"
assert_detect "написал Telegram-бот"     ""  "T8: Telegram-бот"
assert_detect "это MCP-сервер"           ""  "T9: MCP-сервер"
assert_detect "смотри CI-пайплайн"       ""  "T10: CI-пайплайн"

# === Границы ===
assert_detect "dev-БД и коммit рядом"    "коммit"  "T11: композит пропущен, нарушение поймано"
assert_detect "dev-БД-lookup'ов"         "dev-БД-lookup'ов" "T12: нарушение в третьей части композита"
assert_detect "обычный русский текст"    ""  "T13: чистая кириллица"
assert_detect "plain english text"       ""  "T14: чистая латиница"
assert_detect '`коммit` в коде'          ""  "T15: инлайн-код исключён (прежнее поведение)"
# Docstring обещает исключение путей, но `/` просто не входит в токен, поэтому
# сегменты пути проверяются как обычные слова. Поведение прежнее, фиксируем как есть.
assert_detect "путь /tmp/коммit тут"     "коммit"  "T16: сегменты пути проверяются как слова"

# === Дедуп сохранён ===
assert_detect "коммit и снова коммit"    "коммit"  "T17: повтор токена не дублируется"

echo ""
echo "output-language-detect tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
