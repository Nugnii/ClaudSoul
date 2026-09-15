#!/usr/bin/env bash
# test_ci_status.sh — «Проверка результата» ci-status.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/ci-status.sh печатает исход прогона, чей headSha равен
#            проверяемому коммиту, а не самого свежего: свежий чужой прогон зелёный, свой красный —
#            ответ «failure» и код 1; своего прогона нет — «не найден» и код 2, а не «зелено»;
#            короткий sha разрешается в полный до сравнения; незавершённый без ожидания — код 2.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Девять кандидатов в свидетели упоминают инструмент, ни один его
# не гоняет (`pattern-marker-matches-form-not-role`). Инструмент опрашивает `gh run list`; здесь в
# PATH подкладывается поддельный `gh`, печатающий строки в форме `--jq`-шаблона инструмента:
# «id sha status conclusion». Журнал поводов разбора уводится в свой STATE_DIR: красный прогон
# своего коммита инструмент записывает как повод (D200), и живое состояние трогать нельзя.
# Команда БЕРЁТСЯ из шапки инструмента, как в test_split_provenance_log.sh.
set -uo pipefail
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/ci-status.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—|печатает).*//; s/ <sha>.*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *ci-status.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/state"
# В PATH — инструмент, подделка и coreutils, которые зовёт библиотека разбора: без `cat`
# поддельный gh молчал бы, и «не найден» сходило бы за проверку; без `dirname`/`date`/`mkdir`
# библиотека молча бы деградировала (прожарка 13 сентября 2026, атаки 2 и 6).
for t in bash git awk sed grep sleep cat head dirname basename date mkdir mktemp tr wc cut sort uniq tail; do p=$(command -v "$t") && ln -s "$p" "$BIN/$t"; done
MINE=$(cd "$REPO" && git rev-parse HEAD)
OTHER=$(printf '%s' "$MINE" | tr '0-9a-f' 'f0123456789abcde')   # заведомо другой sha той же длины

# Поддельный gh: печатает переданные строки, как их дал бы `--jq` инструмента, и ЧТИТ `-L N`:
# подделка, печатавшая всё независимо от окна, зеленила мутант `-L 1` — тот самый дефект,
# ради которого инструмент написан (прожарка 13 сентября 2026, атака 2).
mk_gh() {
    {
        printf '#!/usr/bin/env bash\nn=20; while [ $# -gt 0 ]; do case "$1" in -L) n="$2"; shift ;; esac; shift; done\n'
        printf 'head -n "$n" <<LINES\n%s\nLINES\n' "$1"
    } > "$BIN/gh"; chmod +x "$BIN/gh"
}
run_tool() {   # $1 — аргумент-sha (или пусто = HEAD); переменные окружения — через префикс
    # HOME подменён: инструмент не должен дотянуться до установленной копии библиотек.
    OUT=$(cd "$REPO" && PATH="$BIN" HOME="$TMP/home" STATE_DIR="$TMP/state" CI_WAIT="${CI_WAIT:-0}" CI_POLL_INTERVAL=0 CI_MAX_TRIES="${CI_MAX_TRIES:-2}" bash -c "$CMD $1" 2>&1); RC=$?
}
mkdir -p "$TMP/home"

# --- T1: свежий чужой прогон зелёный, свой красный — ответ о СВОЁМ ------------------------------
mk_gh "2 $OTHER completed success
1 $MINE completed failure"; run_tool "$MINE"
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 "прогон 1 для ${MINE:0:7}: failure"
# Красный прогон своего коммита — повод разбора (D200): библиотека дерева пишет его в STATE_DIR.
# Прежняя редакция снимала эту ногу с объяснением «rc_env_is_real молчит вне настоящей среды» —
# объяснение было неверным: ветка молчала, потому что `cat` отсутствовал в PATH и красного исхода
# не было вовсе (прожарка 13 сентября 2026, атака 6).
[ -n "$(ls -A "$TMP/state" 2>/dev/null)" ] && ok || bad T1 "красный свой прогон не записан поводом разбора в STATE_DIR"

# --- T2: свой прогон зелёный — 0 -----------------------------------------------------------------
mk_gh "2 $OTHER completed failure
1 $MINE completed success"; run_tool "$MINE"
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 "прогон 1 для ${MINE:0:7}: success"

# --- T2b: свой прогон третьей строкой — окно опроса шире одного прогона ------------------------------
mk_gh "3 $OTHER completed success
2 $OTHER completed success
1 $MINE completed success"; run_tool "$MINE"
[ "$RC" -eq 0 ] && ok || bad T2b "свой прогон за пределами первой строки не найден: rc=$RC — $OUT"

# --- T3: своего прогона нет — «не найден», код 2, не зелено --------------------------------------
mk_gh "2 $OTHER completed success"; run_tool "$MINE"
[ "$RC" -eq 2 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 "прогон для ${MINE:0:7} не найден"

# --- T4: короткий sha и HEAD разрешаются в полный до сравнения ----------------------------------
mk_gh "1 $MINE completed success"; run_tool "${MINE:0:7}"
[ "$RC" -eq 0 ] && ok || bad T4 "короткий sha: rc=$RC — $OUT"
run_tool ""
[ "$RC" -eq 0 ] && ok || bad T4 "HEAD: rc=$RC — $OUT"

# --- T5: не завершён, без ожидания — код 2 и статус ----------------------------------------------
mk_gh "1 $MINE in_progress -"; run_tool "$MINE"
[ "$RC" -eq 2 ] && ok || bad T5 "rc=$RC — $OUT"
has T5 "прогон 1 для ${MINE:0:7}: in_progress"

# --- T6: ожидание с потолком попыток — прогон не появился, код 2 --------------------------------
mk_gh ""; CI_WAIT=1 CI_MAX_TRIES=2 run_tool "$MINE"
[ "$RC" -eq 2 ] && ok || bad T6 "rc=$RC — $OUT"
has T6 "не появился за"

echo ""
echo "ci-status tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
