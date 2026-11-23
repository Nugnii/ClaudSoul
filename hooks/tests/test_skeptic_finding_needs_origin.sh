#!/usr/bin/env bash
# СУДИТ: hooks/backlog-open-write-guard.sh hooks/lib/skeptic_origin.py
# test_skeptic_finding_needs_origin.sh — находка скептика H/M закрывается только со сверенным происхождением (D1305).
#
# Повод: из 123 закрытий, называющих находки H/M, слово о происхождении есть у 18 — проверки судили запись «Скептик.»,
# а не разбор. Решение владельца 16 ноября 2026: отказ, всё перепроверяется. Одна и та же правка ◐ → ☑ пункта со строкой
# «Скептик.» opus, называющей находку, отбивается или проходит по одному свойству — строке «Происхождение.», которую мир
# подтверждает: git — что коммит в истории названной строки, повтор поиска — что братьев столько, сколько записано.
# O1  — строки нет: отказ с именем пункта и находки, журнал `noorigin`;
# O2  — строка верна: тишина (положительный контроль);
# O3  — коммит не менял названную строку: отказ;
# O4  — поиск братьев дал меньше записанного, O13 — больше: отказ;
# O5  — «не подтвердилась: <довод>»: тишина, журнал `disowned`; O10 — без двоеточия: отказ;
# O6  — «находки H/M — нет»: тишина;
# O7  — пункт уже был ☑, правится текст: не судится;
# O8  — диапазон «M1–M3» при строках на M1 и M3: отказ называет M2 (внутренность диапазона);
# O9  — находка только на строке продолжения абзаца «Скептик.»: отказ (12 из 30 закрытий держатся на продолжении);
# O11 — поиск братьев дольше срока: отказ;
# O12 — две строки на одну находку, верная первой: тишина (лучший исход, а не последний);
# O14 — путь «.» вместо файла: отказ (скептик D1305, H1);
# O15 — кириллическая «Н4» под заголовком «Скептик по … (opus).»: отказ (скептик D1305, H2);
# O16 — «пунктом D<N>»: есть пункт с корнем — тишина, нет — отказ (скептик D1305, L3);
# O17 — помощник упал: отказ с кодом, а не тишина (скептик D1305, M2).
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/backlog-open-write-guard.sh"
[ -f "$HOOK" ] && [ -f "$HOOKS_DIR/lib/skeptic_origin.py" ] || { echo "FAIL: нет стража или hooks/lib/skeptic_origin.py"; exit 1; }
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
    || { echo "SKIP: нет jq, git или python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
P="$TMP/p"; ST="$TMP/state"; mkdir -p "$P/hooks" "$ST"
_g() { git -C "$P" -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }
printf 'a\nb\n' > "$P/hooks/x-guard.sh"; echo b > "$P/other.txt"
printf '%s\n' '# BACKLOG' '' '- ☐ **D7** пункт долга с корнем' '  **Корень.** R5 — объявление без проверки.' > "$P/BACKLOG-archive.md"
_g init -q && _g add . && _g commit -qm c1 || { echo "подготовка мира не удалась: hooks/tests/test_skeptic_finding_needs_origin.sh:$LINENO" >&2; exit 1; }
C1=$(git -C "$P" rev-parse --short HEAD)
echo c > "$P/other.txt"; _g commit -qam c2 || { echo "подготовка мира не удалась: hooks/tests/test_skeptic_finding_needs_origin.sh:$LINENO" >&2; exit 1; }
C2=$(git -C "$P" rev-parse --short HEAD)
SIB="братьев 2: \`printf 'a\\nb\\n'\`"
GOOD="$C1 hooks/x-guard.sh:1; $SIB"
item() {  # item <метка> [строки после показания…] — блок пункта защитного слоя
    local m="$1"; shift
    printf '%s\n' "- $m **S1** дефект" '  **Повод.** `hooks/x-guard.sh:1` пропускает запись.' '  **Корень.** R5 — объявление без проверки.' '  **Проверка.** `true` → 0'
    case "$m" in ☑) printf '%s\n' '  **Показание.** «Проверка» 0 (до — 1).' "$@" ;; *) printf '%s\n' '  **Проверка возврата:** решение — пункт описывает наличный дефект.' ;; esac
}
close() {  # close <прежняя метка> <строки закрытого блока…> → вывод стража на правке; HOOK_UNDER — другой страж
    local from="$1"; shift
    local old; old=$(if [ "$from" = ☑ ]; then item ☑ "$@"; else item ◐; fi)
    { printf '%s\n\n' '# BACKLOG'; printf '%s\n' "$old"; } > "$P/BACKLOG.md"
    jq -cn --arg f "$P/BACKLOG.md" --arg o "$old" --arg n "$(item ☑ "$@" ${EXTRA:+"$EXTRA"})" \
        '{session_id:"so", tool_name:"Edit", tool_input:{file_path:$f, old_string:$o, new_string:$n}}' \
    | STATE_DIR="$ST" bash "${HOOK_UNDER:-$HOOK}" 2>/dev/null
}
denied() { grep -q '"permissionDecision":"deny"' <<< "${1:-}"; }
silent() { if [ -z "${1:-}" ]; then ok; else bad "$2" "ожидалась тишина, получено: ${1:0:300}"; fi; }
SK='  **Скептик.** opus по '"$C1"': H1 (дыра в страже) починена.'

OUT=$(close ◐ "$SK")
denied "$OUT" && grep -q 'S1' <<< "$OUT" && grep -q 'H1' <<< "$OUT" && grep -q 'происхождени' <<< "$OUT" && ok \
    || bad O1 "закрытие с находкой H1 без строки «Происхождение» прошло или не названо: ${OUT:0:300}"
grep -q '"item":"S1","kind":"noorigin"' "$ST"/backlog-open-write-fired-so.jsonl 2>/dev/null && ok || bad O1a "отказ не записан видом noorigin"

OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $GOOD")
silent "$OUT" "O2 сверенное происхождение отбито"

OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $C2 hooks/x-guard.sh:1; $SIB")
denied "$OUT" && grep -q 'не менял' <<< "$OUT" && ok || bad O3 "коммит, не менявший строку, принят: ${OUT:0:300}"

OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $C1 hooks/x-guard.sh:1; братьев 3: \`printf 'a\\nb\\n'\`")
denied "$OUT" && grep -q 'дал 2' <<< "$OUT" && ok || bad O4 "число братьев больше найденного принято: ${OUT:0:300}"
OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $C1 hooks/x-guard.sh:1; братьев 1: \`printf 'a\\nb\\n'\`")
denied "$OUT" && grep -q 'дал 2' <<< "$OUT" && ok || bad O13 "число братьев меньше найденного принято: ${OUT:0:300}"

OUT=$(close ◐ "$SK" '  **Происхождение.** H1 — не подтвердилась: воспроизведение скептика шло на старом дереве')
silent "$OUT" "O5 неподтвердившаяся находка с доводом отбита"
grep -q '"item":"S1","kind":"disowned"' "$ST"/backlog-open-write-fired-so.jsonl 2>/dev/null && ok || bad O5a "«не подтвердилась» не записано видом disowned"
OUT=$(close ◐ "$SK" '  **Происхождение.** H1 — не подтвердилась вовсе никак')
denied "$OUT" && ok || bad O10 "«не подтвердилась» без довода через двоеточие принята: ${OUT:0:300}"

OUT=$(close ◐ '  **Скептик.** opus по a1b2c3d, находки H/M — нет.')
silent "$OUT" "O6 закрытие без находок H/M отбито"

OUT=$(EXTRA='  Уточнение текста закрытого пункта.' close ☑ "$SK")
silent "$OUT" "O7 правка уже закрытого пункта судится"

OUT=$(close ◐ '  **Скептик.** opus: M1–M3 починены.' "  **Происхождение.** M1, M3 — $GOOD")
denied "$OUT" && grep -q 'M2' <<< "$OUT" && ok || bad O8 "находка M2 внутри диапазона без происхождения прошла: ${OUT:0:300}"

OUT=$(close ◐ '  **Скептик.** opus по '"$C1"': H нет;' '  M1 (свидетель по двум образцам) починена.')
denied "$OUT" && grep -q 'M1' <<< "$OUT" && ok || bad O9 "находка на строке продолжения абзаца не прочитана: ${OUT:0:300}"

OUT=$(OPEN_WRITE_TIMEOUT=1 close ◐ "$SK" "  **Происхождение.** H1 — $C1 hooks/x-guard.sh:1; братьев 1: \`sleep 5; echo a\`")
denied "$OUT" && grep -q 'не уложился' <<< "$OUT" && ok || bad O11 "поиск братьев дольше срока принят: ${OUT:0:300}"

OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $GOOD" "  **Происхождение.** H1 — $C2 hooks/x-guard.sh:1; $SIB")
silent "$OUT" "O12 верная строка проиграла неверной, стоящей после неё"

OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $C1 .:1; братьев 0: \`true\`")
denied "$OUT" && ok || bad O14 "путь «.» принят местом происхождения: ${OUT:0:300}"

OUT=$(close ◐ '  **Скептик по '"$C1"' (opus, с разбором).** M: Н4 — свидетель судил тишину.' '  **Скептик.** opus по '"$C1"', см. выше.')
denied "$OUT" && grep -q 'H4' <<< "$OUT" && ok || bad O15 "кириллическая находка под заголовком «Скептик по …» не прочитана: ${OUT:0:300}"

OUT=$(close ◐ '  **Скептик.** opus: M1 → D7.' '  **Происхождение.** M1 — пунктом D7')
silent "$OUT" "O16 находка, ушедшая в пункт с корнем, отбита"
OUT=$(close ◐ '  **Скептик.** opus: M1 → D8.' '  **Происхождение.** M1 — пунктом D8')
denied "$OUT" && grep -q 'D8' <<< "$OUT" && ok || bad O16b "ссылка на несуществующий пункт принята: ${OUT:0:300}"

# O18: номер в кавычках целиком — цитата примера, а не находка (сквозняк закрытием D1305: «пишут «Н4», «М2»»).
OUT=$(close ◐ "$SK" "  **Происхождение.** H1 — $GOOD" '  **Круг скептика (opus).** H1 — 4 закрытия пишут кириллические «Н4», «М2», а `H7` — формат.')
silent "$OUT" "O18 номер в кавычках прочитан находкой"

# O17: помощник упал — копия хуков с помощником, выходящим кодом 3.
HK="$TMP/hk"; cp -R "$HOOKS_DIR" "$HK" 2>/dev/null && printf '%s\n' 'import sys' 'sys.exit(3)' > "$HK/lib/skeptic_origin.py" \
    || { echo "подготовка мира не удалась: hooks/tests/test_skeptic_finding_needs_origin.sh:$LINENO" >&2; exit 1; }
OUT=$(HOOK_UNDER="$HK/backlog-open-write-guard.sh" close ◐ "$SK")
denied "$OUT" && grep -q 'упал (код 3)' <<< "$OUT" && ok || bad O17 "упавший помощник пропустил закрытие: ${OUT:0:300}"

echo "происхождение находок скептика: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
