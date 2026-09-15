#!/usr/bin/env bash
# test_publish_guard.sh — необратимая публикация без предъявленного сухого прогона отклоняется.
#
# Результат: отправка снимка наружу не выполняется, пока в том же ходе не показано, что уйдёт
# Проверка результата: bash hooks/tests/test_publish_guard.sh даёт 0
#
# Повод — решение владельца 7 сентября 2026 по пункту D330. Знание
# pattern-publication-carrier-mismatch («личное сидит не в том носителе, в который смотрит
# очистка») имело уровень 3 — подсказку. Замер: 34 срабатывания на 21 658 вызовов Bash,
# ложных 0, частота 0,157%; оба контрпримера подтверждены МОЛЧАНИЕМ признака — 38 сухих
# прогонов в корпусе не пойманы, упоминание имени скрипта в тексте тоже. Последствие одно
# и необратимо: снимок ушёл наружу.
#
# ПРИЗНАК СНЯТИЯ ОТКАЗА — ДЕЙСТВИЕ, А НЕ РЕЧЬ: сухой прогон того же скрипта в этом же ходе.
# Обещание «я проверил» словами не считается: за сессию 7 сентября 2026 трижды измерено,
# что признак, снятый с текста, даёт правдоподобное и ложное показание.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="${PUBLISH_GUARD:-$ROOT/hooks/publish-guard.sh}"
[ -f "$HOOK" ] || { echo "SKIP: нет $HOOK"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# tr <файл> <команды...> — расшифровка, где ход состоит из этих Bash-вызовов
mk_tr() {
    _f="$TMP/$1.jsonl"; shift
    printf '{"message":{"role":"user","content":[{"type":"text","text":"публикуй"}]}}\n' > "$_f"
    for c in "$@"; do
        printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' \
            "$(jq -Rn --arg c "$c" '$c')" >> "$_f"
    done
    printf '%s' "$_f"
}
run() {  # run <команда> [расшифровка]
    printf '{"tool_name":"Bash","tool_input":{"command":%s},"transcript_path":"%s"}' \
        "$(jq -Rn --arg c "$1" '$c')" "${2:-}" | bash "$HOOK" 2>&1
}
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }

PUSH='bash scripts/publish-public.sh --push'
DRY='bash scripts/publish-public.sh'

# T1: отправка без сухого прогона — ОТКАЗ
T1=$(mk_tr t1 "$PUSH")
OUT=$(run "$PUSH" "$T1")
if denied "$OUT"; then ok; else bad "T1" "отправка без сухого прогона не отклонена: $(printf '%s' "$OUT" | head -c 90)"; fi

# T1b: отказ НАЗЫВАЕТ, что делать
# Ищем КОМАНДУ, которой отказ снимается, а не падеж слова: 7 сентября 2026 нога уже
# краснела на «знание» против «знания» — признак, снятый с формы слова, ловит форму.
# И синтаксис РАСШИРЕННЫЙ (-E): BSD grep не понимает `\|` в базовых регулярках, а машина
# этого набора именно BSD — вторая редакция ноги краснела ровно поэтому.
REASON=$(jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$OUT")
if grep -qE 'publish-public\.sh([^-]|$)' <<< "$REASON"; then ok
else bad "T1b" "в отказе не назван способ снять его"; fi

# T2: та же отправка ПОСЛЕ сухого прогона в том же ходе — пропуск
T2=$(mk_tr t2 "$DRY" "$PUSH")
OUT=$(run "$PUSH" "$T2")
if denied "$OUT"; then bad "T2" "отправка после сухого прогона отклонена"; else ok; fi

# T3: сам сухой прогон — пропуск
T3=$(mk_tr t3 "$DRY")
OUT=$(run "$DRY" "$T3")
if denied "$OUT"; then bad "T3" "сухой прогон отклонён"; else ok; fi

# T4: КОНТРПРИМЕР — имя скрипта УПОМЯНУТО, а не запущено
T4=$(mk_tr t4 "grep -n publish-public README.md")
OUT=$(run "grep -n publish-public README.md" "$T4")
if denied "$OUT"; then bad "T4" "упоминание имени скрипта принято за запуск"; else ok; fi

# T5: посторонняя команда — пропуск
T5=$(mk_tr t5 "git status")
OUT=$(run "git status" "$T5")
if denied "$OUT"; then bad "T5" "посторонняя команда отклонена"; else ok; fi

# T6: КОНТРПРИМЕР — расшифровки нет: молчать нельзя, но и падать нельзя.
# Без хода нечем подтвердить сухой прогон, значит отправка отклоняется — это безопасная
# сторона: пропустить необратимое из-за отсутствия данных хуже, чем переспросить.
OUT=$(run "$PUSH" "$TMP/нет-такого.jsonl")
if denied "$OUT"; then ok; else bad "T6" "без расшифровки необратимая отправка пропущена: '$OUT'"; fi

# T7: сухой прогон, которого в ходе ЕЩЁ НЕТ (он и есть первый вызов) — пропуск.
# Без этой ноги мутация «отправка не отличается от прогона» проходила насквозь: в T3
# расшифровка уже содержала прогон, и снятие проверки --push оставалось незаметным.
T7=$(mk_tr t7 "git status")
OUT=$(run "$DRY" "$T7")
if denied "$OUT"; then bad "T7" "первый сухой прогон отклонён — проверять нечего, он и есть проверка"; else ok; fi

# T8: КОНТРПРИМЕР — имя И флаг УПОМЯНУТЫ в тексте, а не запущены. Без этой ноги мутация
# «имя ловится не в позиции команды» проходила насквозь: в T4 флага --push не было.
# Флаг стоит СВОБОДНО, а не перед закрывающей кавычкой: первая редакция ноги прятала
# --push внутри кавычек, признак его не видел, и мутация проходила насквозь.
MENTION='echo подсказка: bash scripts/publish-public.sh --push'
T8=$(mk_tr t8 "$MENTION")
OUT=$(run "$MENTION" "$T8")
if denied "$OUT"; then bad "T8" "упоминание команды в тексте принято за запуск: $(printf '%s' "$OUT" | head -c 70)"; else ok; fi

echo "publish guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
