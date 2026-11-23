#!/usr/bin/env bash
# СУДИТ: hooks/session-collector.sh hooks/backlog-lib.sh
# test_contract_parts_mid_session.sh — части договора инициации (BACKLOG.md, ROOTS.md) заводятся в проекте, куда сессия
# вошла ПЕРЕХОДОМ, на границе хода, а не только на старте сессии в нём (D1301, откат D1016, корень R5).
#
# Повод: viral-radar (15 ноября 2026). Сессия 5f355a40 стартовала в домашнем каталоге, перешла в проект в 23:30 и завела
# SESSION.md в 23:50; механизм D1016 смотрел только на каталог старта, и частей проект не получил.
#
# M1 — граница хода с каталогом инициированного проекта (`.git` и SESSION.md, частей нет) заводит обе части из шаблонов
#      и называет заведённое с путём проекта в канале СВОЕЙ сессии (`stop-signals-<sid>.txt`, D1047), а не в общей очереди
#      `pending-alerts.txt`, которую снимает первая сессия с репликой (скептик opus по e6775d9d, H1);
# M2 — повторная граница хода молчит и бэклог не меняет; бэклог, правленный руками, цел (только отсутствующее);
# M3 — каталог без SESSION.md (не инициирован) частей не получает — положительный контроль M1 по другую сторону.
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
mkdir -p "$TMP/state" "$TMP/home/.claude/templates"
# Шаблоны — из дерева, в песочнице HOME: ответ не зависит от того, что лежит в установке.
cp "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" "$HOOKS_DIR/../templates/ROOTS.md.tmpl" "$TMP/home/.claude/templates/"

_stop() {   # <cwd> [sid] — одна граница хода; печатает канал своей сессии, общую очередь кладёт в $TMP/queue
    : > "$TMP/state/pending-alerts.txt"; rm -f "$TMP/state/stop-signals-${2:-x}.txt"
    jq -cn --arg s "${2:-cp$RANDOM}" --arg c "$1" '{session_id:$s, hook_event_name:"Stop", cwd:$c}' \
        | HOME="$TMP/home" STATE_DIR="$TMP/state" CLAUDSOUL_BACKLOG="$TMP/none.md" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" bash "$HOOK" >/dev/null 2>&1 \
        || { echo "подготовка мира не удалась: Stop-хук вернул не 0" >&2; exit 1; }
    cp "$TMP/state/pending-alerts.txt" "$TMP/queue" 2>/dev/null || : > "$TMP/queue"
    cat "$TMP/state/stop-signals-${2:-x}.txt" 2>/dev/null
}

# M1. Проект вошёл в работу посреди сессии: `.git`, SESSION.md, частей нет; граница хода — из подкаталога проекта.
P="$TMP/viral"; mkdir -p "$P/sub"
( cd "$P" && git init -q && printf '# Session Log\n' > SESSION.md ) || { echo "FAIL: мир не собрался"; exit 1; }
OUT=$(_stop "$P/sub" s1)
cmp -s "$P/BACKLOG.md" "$HOOKS_DIR/../templates/BACKLOG.md.tmpl" && ok || bad M1a "BACKLOG.md не заведён из шаблона"
cmp -s "$P/ROOTS.md" "$HOOKS_DIR/../templates/ROOTS.md.tmpl" && ok || bad M1b "ROOTS.md не заведён из шаблона"
case "$OUT" in *"$P"*"заведены BACKLOG.md, ROOTS.md"*) ok ;; *) bad M1c "заведённое не названо с путём в канале своей сессии: $(printf '%s' "$OUT" | head -c 200)" ;; esac
grep -q 'Договор инициации' "$TMP/queue" && bad M1e "слово ушло в общую очередь сессий — его покажет чужая сессия" || ok
[ "$(head -1 "$TMP/state/stop-signals-s1.project" 2>/dev/null)" = "$P" ] && ok || bad M1f "у канала нет корня проекта — сессия того же проекта его не заберёт"
[ ! -e "$P/sub/BACKLOG.md" ] && ok || bad M1d "части легли в подкаталог, а не в корень проекта"

# M2. Повтор молчит; ручная правка бэклога цела.
printf -- '- ☐ **X1** пункт руками\n' >> "$P/BACKLOG.md"
S0=$(cksum < "$P/BACKLOG.md")
OUT2=$(_stop "$P" s1)
[ "$(cksum < "$P/BACKLOG.md")" = "$S0" ] && ok || bad M2a "повторная граница хода изменила бэклог"
case "$OUT2" in *"Договор инициации"*) bad M2b "повтор не молчит: $(printf '%s' "$OUT2" | head -c 200)" ;; *) ok ;; esac

# M3. Не инициирован (нет SESSION.md) — частей нет.
Q="$TMP/plain"; mkdir -p "$Q"; ( cd "$Q" && git init -q ) || exit 1
OUT3=$(_stop "$Q" s3)
[ ! -e "$Q/BACKLOG.md" ] && [ ! -e "$Q/ROOTS.md" ] && ok || bad M3a "в неинициированном проекте заведены части"
case "$OUT3" in *"Договор инициации"*) bad M3b "о неинициированном проекте есть сигнал" ;; *) ok ;; esac

echo "contract parts mid-session: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
