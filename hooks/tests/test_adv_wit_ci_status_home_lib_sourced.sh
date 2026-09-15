#!/usr/bin/env bash
# test_adv_wit_ci_status_home_lib_sourced.sh — в среде свидетеля ci-status красная ветка инструмента подключает библиотеку из $HOME/.claude/hooks, а не из дерева: свидетель гоняет установленную копию, не репозиторий.
#
# Результат: PATH свидетеля без `dirname` → `_RC_LIB` дерева не резолвится (`cd "/../hooks"`
#            падает, остаётся «/root-cause-lib.sh») → откат на `$HOME/.claude/hooks/root-cause-lib.sh`.
#            HOME свидетель не подменяет, значит на машине с установкой исполняется ЖИВАЯ копия
#            библиотеки, и `rc_env_is_real` в этой среде отвечает «настоящая» (CLAUDSOUL_REPO,
#            CLAUDE_HOME, BACKLOG_FILE не выставлены) — вопреки комментарию свидетеля «rc_note_event
#            молчит вне настоящей среды». На машине без установки ветка молча пропускается: один
#            свидетель — два разных исполнения. Здесь HOME подменён канарейкой; ожидание — канарейка
#            не подключалась, инструмент под свидетелем берёт библиотеку дерева.
# Проверка результата: этот тест.
set -uo pipefail
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/ci-status.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; H="$TMP/home"; MARK="$TMP/canary-sourced"
mkdir -p "$BIN" "$TMP/state" "$H/.claude/hooks"
for t in bash git awk sed grep sleep cat; do p=$(command -v "$t") && ln -s "$p" "$BIN/$t"; done
# Канарейка на месте живой библиотеки: подключили — оставила след.
printf '#!/usr/bin/env bash\n: > "%s"\nrc_note_event() { :; }\n' "$MARK" > "$H/.claude/hooks/root-cause-lib.sh"
MINE=$(cd "$REPO" && git rev-parse HEAD)
printf '#!/usr/bin/env bash\ncat <<LINES\n1 %s completed failure\nLINES\n' "$MINE" > "$BIN/gh"; chmod +x "$BIN/gh"

# --- T1: сцена T1 свидетеля в его же среде, HOME → канарейка -------------------------------------
OUT=$(cd "$REPO" && PATH="$BIN" HOME="$H" STATE_DIR="$TMP/state" CI_WAIT=0 CI_POLL_INTERVAL=0 CI_MAX_TRIES=2 bash -c "bash scripts/ci-status.sh $MINE" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — ${OUT}"
has T1 "прогон 1 для ${MINE:0:7}: failure"
[ ! -f "$MARK" ] && ok || bad T1 "инструмент под свидетелем подключил \$HOME/.claude/hooks/root-cause-lib.sh, а не библиотеку дерева; вывод: $(grep -F 'command not found' <<< "$OUT" | head -1)"

echo ""
echo "adv ci-status home lib sourced: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
