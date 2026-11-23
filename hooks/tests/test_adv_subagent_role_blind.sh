#!/usr/bin/env bash
# test_adv_subagent_role_blind.sh — «последний значимый блок» в subagent-outcome.sh
# считается БЕЗ различения роли, и потому чужая реплика сходит за ответ агента.
#
# Признак стража объявлен так (subagent-outcome.sh:23): «последний значимый блок
# транскрипта не является ТЕКСТОВЫМ ОТВЕТОМ», text → «договорил, молчим».
# Выражение jq (:99-105) роль не смотрит вовсе: оно берёт `.message.content` у ЛЮБОЙ
# записи и, если content — строка, объявляет вид блока «text».
#
# А строкой content в расшифровках бывает именно у РЕПЛИК СОБЕСЕДНИКА И ОТВЕТОВ
# ИНСТРУМЕНТА: проверено на живой расшифровке этого проекта
#   ~/.claude/projects/-Users-user-My-Project-ClaudSoul/*.jsonl
#   jq 'select(.message.content|type=="string")' → записи с role "user".
# Значит субагент, оборвавшийся сразу после ответа инструмента, для стража «договорил»,
# и повод разбора не заводится — ровно тот случай, ради которого страж написан
# (его собственная шапка: «все три оборвались на tool_result/thinking»).
#
# Вторая половина атаки — расшифровка, которая ЧИТАЕТСЯ и не даёт ни одного блока
# (пустой файл, файл из одних записей `summary`). `jq -se .` её пропускает как читаемую,
# LAST_KIND выходит пустым и попадает в ветку «блоков нет вовсе — не наш случай» (:109),
# то есть страж молчит. Молчание здесь неотличимо от «сработал успешно», а по правилу
# самого проекта у прибора три состояния, и «не посмотрел» обязано звучать.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/subagent-outcome.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# Ожидание роста расшифровки (D1354) — 20 раз по 0,1 с на каждом вердикте «не договорил»: настоящим `sleep` ноги
# обрыва стоили бы по 2 с. Расшифровка ноги не растёт, поэтому `sleep` подменён пустым; ожидание с ростом файла
# держат нога T18 (свой `sleep` дописывает результат) и проба hooks/tests/fixtures/probe_D1354.sh.
NOSLEEP="$TMP/nosleep"; mkdir -p "$NOSLEEP"; printf '#!/bin/sh\nexit 0\n' > "$NOSLEEP/sleep"; chmod +x "$NOSLEEP/sleep"
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

# said <метка> <файл> → «yes», если страж что-то сказал в очередь либо завёл повод
said() {
    local st="$TMP/st-$1"
    mkdir -p "$st"
    # Форма payload ВЗЯТА ИЗ МИРА (замер 17 сентября 2026, D450): расшифровка СУБАГЕНТА
    # приходит полем `agent_transcript_path`, а `transcript_path` несёт путь РОДИТЕЛЯ, и
    # родитель в этот момент стоит на `tool_use` самого вызова Task. Прежде тест подавал
    # расшифровку агента полем `transcript_path` — той же неверной моделью payload, из-за
    # которой и жил дефект. Родительская фикстура здесь ещё и ловушка: страж, вернувшийся к
    # чтению родителя, заговорит на КАЖДОМ честном успехе, и обратный контроль это назовёт.
    if [ ! -f "$TMP/parent-tool-use.jsonl" ]; then
        printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Task","input":{}}]}}\n' \
            > "$TMP/parent-tool-use.jsonl"
    fi
    # Раскладка путей взята из мира: расшифровка агента лежит в
    # `<проект>/<session_id>/subagents/`, родительская рядом с каталогом сессии; владелец
    # резолва эту раскладку сверяет, и плоская фикстура ему законно не годится.
    local sid="sid-$1"; local proj="$TMP/proj-$1"
    mkdir -p "$proj/$sid/subagents"
    cp "$TMP/parent-tool-use.jsonl" "$proj/$sid.jsonl"
    local ag="$proj/$sid/subagents/agent-$1.jsonl"
    if [ -f "$2" ]; then cp "$2" "$ag"; fi
    jq -cn --arg a "$ag" --arg p "$proj/$sid.jsonl" --arg s "$sid" --arg i "$1" \
        '{transcript_path:$p, agent_transcript_path:$a, session_id:$s, agent_id:$i}' \
      | PATH="$NOSLEEP:$PATH" STATE_DIR="$st" bash "$HOOK" >/dev/null 2>&1
    if [ -s "$st/pending-alerts.txt" ] || [ -s "$st/pending-events.jsonl" ]; then
        printf 'yes'
    else printf 'no'; fi
}

must_speak() {  # must_speak <метка> <файл> <имя>
    if [ "$(said "$1" "$2")" = "yes" ]; then ok "$3"
    else bad "$3 — СТРАЖ ПРОМОЛЧАЛ, обрыв выдан за успех"; fi
}

# --- Контроль: обрыв на tool_result массивом виден -------------------------------
F="$TMP/ctl.jsonl"
{ printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}\n'
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"42"}]}}\n'
} > "$F"
must_speak ctl "$F" "контроль: обрыв на tool_result (массив) замечен"

# --- Контроль обратный: настоящий ответ агента обязан пройти молча ----------------
F="$TMP/ctl2.jsonl"
{ printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}\n'
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"готово, вот итог"}]}}\n'
} > "$F"
if [ "$(said ctl2 "$F")" = "no" ]; then ok "контроль: договоривший субагент проходит молча"
else bad "контроль обратный не сработал: страж заговорил на честном успехе"; fi

# --- Атака 1: тот же обрыв, но ответ инструмента пришёл СТРОКОЙ -------------------
F="$TMP/a1.jsonl"
{ printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"смотрю"}]}}\n'
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}\n'
  printf '{"type":"user","message":{"role":"user","content":"результат команды: 42"}}\n'
} > "$F"
must_speak a1 "$F" "обрыв, где последняя запись — user со строкой, замечен"

# --- Атака 2: последняя запись — реплика собеседника (роль не смотрится) ----------
F="$TMP/a2.jsonl"
{ printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}\n'
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"давай ещё"}]}}\n'
} > "$F"
must_speak a2 "$F" "обрыв, где последний текст принадлежит собеседнику, замечен"

# --- Атака 3: расшифровка читается, но блоков в ней нет ---------------------------
F="$TMP/a3.jsonl"; : > "$F"
must_speak a3 "$F" "пустая расшифровка названа неизвестностью, а не успехом"

F="$TMP/a4.jsonl"
printf '{"type":"summary","summary":"прогон субагента"}\n' > "$F"
must_speak a4 "$F" "расшифровка без единого блока названа неизвестностью"

# --- Свидетельство: строковый content в живых расшифровках существует --------------
# ВЫБОРКА, А НЕ ОДИН САМЫЙ СВЕЖИЙ ФАЙЛ (12 сентября 2026, D401). Прежняя редакция читала
# `head -1` от списка по времени — то есть расшифровку ТЕКУЩЕЙ сессии, которая в начале хода
# почти пуста. В прогоне 00:13 нога покраснела именно поэтому: в только что начатой сессии
# строкового content ещё не было, а в чистой копии того же кода нога зелёная. Выход не
# различал «такой формы в жизни не бывает» (настоящая находка) и «в этом файле её пока нет»
# (нормальное состояние мира) — корень R6.
# Утверждение свидетельства — о СУЩЕСТВОВАНИИ формы, значит и выборка должна быть о ней:
# хватает одной расшифровки из многих. Замер 12 сентября: форма нашлась в 9 файлах из 10.
LIVE_DIR="$HOME/.claude/projects/-Users-user-My-Project-ClaudSoul"
# shellcheck disable=SC2012
LIVE_N=$(ls -t "$LIVE_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
case "${LIVE_N:-0}" in ''|*[!0-9]*) LIVE_N=0 ;; esac
if [ "$LIVE_N" -lt 3 ]; then
    # НЕ ИЗМЕРЕНО названо отдельно от находки: на трёх файлах «не нашли» ничего не значит.
    echo "  (свидетельство НЕ ИЗМЕРЕНО: живых расшифровок $LIVE_N, нужно не меньше трёх)"
else
    _seen_roles=""; _seen_files=0; _scanned=0
    for _lf in $(ls -t "$LIVE_DIR"/*.jsonl 2>/dev/null | head -10); do
        _scanned=$((_scanned + 1))
        _r=$(jq -r 'select((.message.content | type) == "string") | (.message.role // "?")' "$_lf" 2>/dev/null | sort -u | tr '\n' ' ')
        if [ -n "${_r// /}" ]; then
            _seen_files=$((_seen_files + 1))
            _seen_roles="$_seen_roles$_r"
        fi
    done
    if [ "$_seen_files" -gt 0 ]; then
        ok "свидетельство: content-строка найдена в $_seen_files расшифровках из $_scanned, роли [$(printf '%s' "$_seen_roles" | tr ' ' '\n' | sort -u | tr '\n' ' ')]"
    else
        bad "свидетельство не получено: content-строк нет ни в одной из $_scanned живых расшифровок"
    fi
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
