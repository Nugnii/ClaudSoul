#!/usr/bin/env bash
# СУДИТ: hooks/publish-guard.sh
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
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"публикуй"}]}}\n' > "$_f"
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
run_sub() {  # run_sub <команда> <расшифровка СУБАГЕНТА> <расшифровка родителя>
    # Раскладка путей взята из мира: `<проект>/<session_id>/subagents/agent-<id>.jsonl`.
    local sid="s$RANDOM"; local proj="$TMP/proj-$sid"
    mkdir -p "$proj/$sid/subagents"
    cp "$3" "$proj/$sid.jsonl"
    local ag="$proj/$sid/subagents/agent-$sid.jsonl"; cp "$2" "$ag"
    jq -cn --arg c "$1" --arg p "$proj/$sid.jsonl" --arg a "$ag" --arg s "$sid" \
        '{tool_name:"Bash", tool_input:{command:$c}, transcript_path:$p, session_id:$s, agent_id:$s, agent_transcript_path:$a}' \
      | bash "$HOOK" 2>&1
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

# --- D426: у признака ОДИН исполнитель, и он судит исполняемую часть ----------------------
# Повод, 17 сентября 2026. PUB_RE был объявлен строкой и применён ДВУМЯ способами с разной
# семантикой: grep <<< судит ПОСТРОЧНО, jq test() без multiline — всю строку целиком. Один
# объявленный признак судил по двум правилам (R1), и оба конца брали СЫРОЙ текст (R3).
# Замер по корпусу (331 команда с упоминанием скрипта): на сыром тексте признак срабатывал 88
# раз, на исполняемой части 75; расхождение 13, и ВСЕ ТРИНАДЦАТЬ без отправки — то есть все
# накручивали счётчик сухих прогонов и СНИМАЛИ отказ с настоящей публикации.

# T-D426a: СНЯТИЕ ОТКАЗА. Упоминание запуска в кавычках эха сухим прогоном не считается.
TD1=$(mk_tr td1 'echo "порядок: ; bash scripts/publish-public.sh затем push"')
OUT=$(run "$PUSH" "$TD1")
if denied "$OUT"; then ok; else bad "D426a" "упоминание в кавычках засчитано сухим прогоном — публикация прошла без предъявления"; fi

# T-D426b: ЛОЖНЫЙ ОТКАЗ. Имя в теле ЧУЖОГО heredoc запуском не является.
HD='cat > notes.md <<EOF
scripts/publish-public.sh --push делает отправку
EOF'
OUT=$(run "$HD" "$(mk_tr td2)")
if denied "$OUT"; then bad "D426b" "запись файла с именем в теле heredoc принята за публикацию"; else ok; fi

# T-D426c: ОТЗЫВ. Настоящий сухой прогон в ходе по-прежнему снимает отказ.
OUT=$(run "$PUSH" "$(mk_tr td3 "$DRY")")
if denied "$OUT"; then bad "D426c" "сужение съело отзыв: настоящий сухой прогон не засчитан"; else ok; fi

# T-D426d: КОНТРАСТ. Без сухого прогона отказ обязан остаться.
OUT=$(run "$PUSH" "$(mk_tr td4)")
if denied "$OUT"; then ok; else bad "D426d" "отказ пропал там, где сухого прогона не было"; fi

# T-D426e/f: РАЗЛИЧАЮЩАЯ СПОСОБНОСТЬ — мутантами, каждый за СВОЮ половину.
# Половины отвечают за разное: сужение области держит случай «в кавычках», единый исполнитель —
# согласие двух концов. Требовать от обеих одного значит не проверить ни одну.
_pg_mutant() {   # _pg_mutant <sed-выражение> <команда> <расшифровка> → сколько раз отказал
    local _t; _t=$(mktemp -d) || { echo "-1"; return; }
    mkdir -p "$_t/hooks"
    sed "$1" "$HOOK" > "$_t/hooks/publish-guard.sh"
    cp "$ROOT/hooks/command-scope-lib.sh" "$_t/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_publish_guard.sh:$LINENO" >&2; exit 1; }
    cp "$ROOT/hooks/hook-input-lib.sh" "$_t/hooks/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_publish_guard.sh:$LINENO" >&2; exit 1; }   # граница хода — `turn_user` оттуда (D1153)
    printf '{"tool_name":"Bash","tool_input":{"command":%s},"transcript_path":"%s"}' \
        "$(jq -Rn --arg c "$2" '$c')" "$3" \
      | bash "$_t/hooks/publish-guard.sh" 2>/dev/null | grep -c deny
    rm -rf "$_t"
}

# e — ОБЛАСТЬ: пусть исполнитель судит сырой текст, случай «в кавычках» обязан снять отказ.
_M=$(_pg_mutant 's|_t=$(executable_part "$_t" 2>/dev/null)|_t="$_t"|' "$PUSH" "$TD1")
[ "$_M" = "0" ] && ok || bad "D426e" "с несуженной областью отказ всё равно стоит (получено '$_M') — ОБЛАСТЬ ничем не доказана"

# f — ЕДИНЫЙ ИСПОЛНИТЕЛЬ: заклиним его в «всегда запуск», и запись файла получит ложный отказ.
_M=$(_pg_mutant 's|^    grep -qE "$PUB_RE" <<< "$_t"$|    return 0|' "$HD" "$(mk_tr td5)")
[ "$_M" != "0" ] && ok || bad "D426f" "с заклиненным исполнителем ложного отказа нет (получено '$_M') — ТОЧНОСТЬ ничем не доказана"


# --- D455: свидетельство сухого прогона ищется в расшифровке АКТОРА ---
# Текст субагента в родительскую расшифровку не попадает вовсе (замер: 0 записей
# `isSidechain` в трёх родительских расшифровках на 526, 885 и 1778 строк), поэтому
# субагент, честно сделавший сухой прогон, предъявить его не мог и получал ОТКАЗ уровня 4.
D455_PAR=$(mk_tr d455par "echo не про публикацию")
D455_AG=$(mk_tr d455ag "$DRY" "$PUSH")
OUT=$(run_sub "$PUSH" "$D455_AG" "$D455_PAR")
if denied "$OUT"; then bad "D455a" "сухой прогон субагента в ЕГО расшифровке не зачтён — ложный отказ уровня 4"
else ok; fi
# Положительный контроль: без сухого прогона нигде отказ обязан остаться.
D455_AG2=$(mk_tr d455ag2 "$PUSH")
OUT=$(run_sub "$PUSH" "$D455_AG2" "$D455_PAR")
if denied "$OUT"; then ok; else bad "D455b" "субагент без сухого прогона отказа не получил — страж ослаб"; fi
# Второй контроль: сухой прогон РОДИТЕЛЯ субагенту не засчитывается (чужое предъявление).
D455_PAR2=$(mk_tr d455par2 "$DRY")
D455_AG3=$(mk_tr d455ag3 "$PUSH")
OUT=$(run_sub "$PUSH" "$D455_AG3" "$D455_PAR2")
if denied "$OUT"; then ok; else bad "D455c" "субагенту зачтён сухой прогон РОДИТЕЛЯ"; fi

echo "publish guard: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
