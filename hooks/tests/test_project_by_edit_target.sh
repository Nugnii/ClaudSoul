#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh hooks/backlog-lib.sh
# test_project_by_edit_target.sh — проект работы сессии виден и по целям её правок, а не только по каталогу события (D1307,
# корень R6): инициированный проект, который ход правит файловым инструментом по абсолютному пути, получает недостающие
# части договора (BACKLOG.md, ROOTS.md) на границе хода, даже если ход кончился в другом каталоге.
#
# Повод: два проекта Biznes-sovetnik, 3 сессии с 23 октября 2026 (скептик opus по D1301, M4): сессия стартовала в
# родительском каталоге и правила проект по абсолютному пути; граница хода судила только каталог события.
#
# E1 — каталог события родительский (не проект), правка Edit в инициированный подпроект без частей: обе части заведены
#      в корне подпроекта, слово с его путём — в канале своей сессии;
# E2 — цель Read (чтение, не правка) в другом инициированном проекте частей не заводит — положительный контроль E1;
# E3 — правка в каталоге без SESSION.md (не инициирован) частей не заводит;
# E4 — правка прошлого хода (до последней реплики) на этой границе не судится: окно — ход.
set -uo pipefail
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-collector.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
[ -f "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" ] && [ -f "$HOOKS_DIR/../templates/ROOTS.md.tmpl" ] \
    || { echo "FAIL: нет шаблонов частей в дереве"; exit 1; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd) || exit 1
mkdir -p "$TMP/state" "$TMP/home/.claude/templates" "$TMP/parent"
cp "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" "$HOOKS_DIR/../templates/ROOTS.md.tmpl" "$TMP/home/.claude/templates/"

_proj() {   # <каталог> [без-session] — проект с .git; SESSION.md, если второго аргумента нет
    mkdir -p "$1" && ( cd "$1" && git init -q && { [ -n "${2:-}" ] || printf '# Session Log\n' > SESSION.md; } ) \
        || { echo "подготовка мира не удалась: hooks/tests/test_project_by_edit_target.sh:$LINENO ($1)" >&2; exit 1; }
}
_rec_user() { jq -cn --arg t "$1" '{type:"user", message:{role:"user", content:$t}}'; }
_rec_tool() { jq -cn --arg n "$1" --arg f "$2" '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", id:"t1", name:$n, input:{file_path:$f}}]}}'; }
_stop() {   # <cwd> <расшифровка> <sid> — одна граница хода; печатает канал своей сессии
    rm -f "$TMP/state/stop-signals-$3.txt" "$TMP/state/stop-signals-$3.project"
    jq -cn --arg s "$3" --arg c "$1" --arg t "$2" '{session_id:$s, hook_event_name:"Stop", cwd:$c, transcript_path:$t}' \
        | HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_BACKLOG="$TMP/none.md" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" bash "$HOOK" >/dev/null 2>&1 \
        || { echo "подготовка мира не удалась: hooks/tests/test_project_by_edit_target.sh:$LINENO (Stop-хук вернул не 0)" >&2; exit 1; }
    cat "$TMP/state/stop-signals-$3.txt" 2>/dev/null
}

# E1. Ход из родительского каталога правит подпроект по абсолютному пути.
SUB="$TMP/parent/sovetnik"; _proj "$SUB"
T1="$TMP/t1.jsonl"; { _rec_user "поправь заметку"; _rec_tool Edit "$SUB/notes/a.md"; } > "$T1"
OUT=$(_stop "$TMP/parent" "$T1" e1)
cmp -s "$SUB/BACKLOG.md" "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" && ok || bad E1a "BACKLOG.md не заведён в правленом подпроекте"
cmp -s "$SUB/ROOTS.md" "$HOOKS_DIR/../templates/ROOTS.md.tmpl" && ok || bad E1b "ROOTS.md не заведён в правленом подпроекте"
case "$OUT" in *"$SUB"*"заведены BACKLOG.md, ROOTS.md"*) ok ;; *) bad E1c "заведённое не названо с путём подпроекта в канале своей сессии: $(printf '%s' "$OUT" | head -c 200)" ;; esac
[ ! -e "$TMP/parent/BACKLOG.md" ] && ok || bad E1d "части легли в каталог события, а не в проект правки"

# E2. Чтение — не правка.
RD="$TMP/parent/readonly"; _proj "$RD"
T2="$TMP/t2.jsonl"; { _rec_user "прочитай"; _rec_tool Read "$RD/README.md"; } > "$T2"
_stop "$TMP/parent" "$T2" e2 >/dev/null
[ ! -e "$RD/BACKLOG.md" ] && [ ! -e "$RD/ROOTS.md" ] && ok || bad E2 "цель чтения получила части договора"

# E3. Правка в проекте без SESSION.md.
NI="$TMP/parent/plain"; _proj "$NI" no-session
T3="$TMP/t3.jsonl"; { _rec_user "правь"; _rec_tool Write "$NI/x.txt"; } > "$T3"
_stop "$TMP/parent" "$T3" e3 >/dev/null
[ ! -e "$NI/BACKLOG.md" ] && [ ! -e "$NI/ROOTS.md" ] && ok || bad E3 "неинициированный проект получил части"

# E4. Правка прошлого хода: после неё была реплика — нынешняя граница хода её не судит.
OLD="$TMP/parent/old"; _proj "$OLD"
T4="$TMP/t4.jsonl"; { _rec_user "раньше"; _rec_tool Edit "$OLD/a.md"; _rec_user "теперь другое"; } > "$T4"
_stop "$TMP/parent" "$T4" e4 >/dev/null
[ ! -e "$OLD/BACKLOG.md" ] && ok || bad E4 "правка прошлого хода судится на этой границе — окно не ход"

# Ноги по кругу скептика opus по 176e7f0a (M3: выпотрошенная ветка оставляла зелёными 4 ноги из 7).
# E5, E6 — Write в новый подкаталог и MultiEdit тоже цели (в корпусе 27 правок Write в чужие проекты, 12 сессий).
for _k in Write:e5 MultiEdit:e6; do
    PW="$TMP/parent/${_k#*:}"; _proj "$PW"
    TW="$TMP/${_k#*:}.jsonl"; { _rec_user "правь"; _rec_tool "${_k%%:*}" "$PW/new/dir/x.md"; } > "$TW"
    _stop "$TMP/parent" "$TW" "${_k#*:}" >/dev/null
    [ -f "$PW/BACKLOG.md" ] && [ -f "$PW/ROOTS.md" ] && ok || bad "${_k#*:}" "цель ${_k%%:*} не дала частей"
done
# E7 — сводка сжатия посреди хода не обрывает окно: правка до неё судится (18 Stop в 7 сессиях корпуса).
P7="$TMP/parent/e7"; _proj "$P7"
T7="$TMP/t7.jsonl"
{ _rec_user "длинная задача"; _rec_tool Edit "$P7/a.md"
  jq -cn '{type:"user", isCompactSummary:true, message:{role:"user", content:"This session is being continued"}}'
  jq -cn '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"продолжаю"}]}}'; } > "$T7"
_stop "$TMP/parent" "$T7" e7 >/dev/null
[ -f "$P7/BACKLOG.md" ] && ok || bad E7 "правка до сводки сжатия посреди хода не судится — окно оборвано сводкой"
# E8 — канал своей сессии привязан к проекту СЕССИИ, а не к правленому (M2): иначе её сообщения уйдут сессиям чужого.
A8="$TMP/a8"; _proj "$A8"; cp "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" "$A8/BACKLOG.md"; cp "$HOOKS_DIR/../templates/ROOTS.md.tmpl" "$A8/ROOTS.md"
B8="$TMP/b8"; _proj "$B8"
T8="$TMP/t8.jsonl"; { _rec_user "правь соседа"; _rec_tool Edit "$B8/x.md"; } > "$T8"
OUT8=$(_stop "$A8" "$T8" e8)
[ -f "$B8/ROOTS.md" ] && ok || bad E8a "правленый соседний проект не получил частей"
[ "$(head -1 "$TMP/state/stop-signals-e8.project" 2>/dev/null)" = "$A8" ] && ok \
    || bad E8b "канал сессии привязан не к её проекту: $(head -1 "$TMP/state/stop-signals-e8.project" 2>/dev/null)"
case "$OUT8" in *"$B8"*) ok ;; *) bad E8c "путь правленого проекта не назван в слове: $(printf '%s' "$OUT8" | head -c 200)" ;; esac
# E9 — путь с переводом строки не вешает сборщик (M1: цикл подъёма не кончался на куске без косой черты).
P9="$TMP/parent/e9"; _proj "$P9"
T9="$TMP/t9.jsonl"; { _rec_user "правь"; _rec_tool Write "$(printf '%s/a\nb.md' "$P9")"; } > "$T9"
jq -cn --arg s e9 --arg c "$TMP/parent" --arg t "$T9" '{session_id:$s, hook_event_name:"Stop", cwd:$c, transcript_path:$t}' \
    | HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_BACKLOG="$TMP/none.md" CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
      timeout 30 bash "$HOOK" >/dev/null 2>&1
RC9=$?
[ "$RC9" -ne 124 ] && ok || bad E9 "путь с переводом строки повесил сборщик (снят по сроку 30 с)"

echo "test_project_by_edit_target: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
