#!/usr/bin/env bash
# test_adv2_wit_ci_status_env_override_silences_event.sh — свидетель ci-status красен на исправном инструменте и настоящем дереве, когда в окружении экспортирован CLAUDSOUL_REPO — документированный переключатель установки; сам инструмент под этой переменной молча теряет запись повода D200.
#
# Результат: `bin/resolve-claudsoul-repo.sh:32` велит пользователю задать CLAUDSOUL_REPO, если
#            дерево не найдено по умолчанию. С этой переменной в окружении `rc_env_is_real`
#            (hooks/root-cause-lib.sh:176-181) объявляет среду «фикстурой», `rc_note_event`
#            выходит молча (:233), и нога T1 свидетеля test_ci_status.sh «красный свой прогон
#            записан поводом разбора в STATE_DIR» краснеет — инструмент исправен, дерево своё,
#            переменная указывает на ЭТО ЖЕ дерево. Свидетель переменную не очищает и не задаёт.
#            То же с CLAUDE_HOME. Вторая половина — не свидетель, а мир: у пользователя с
#            экспортированным CLAUDSOUL_REPO `ci-status.sh` никогда не заводит повод `ci-red`,
#            контур D200 для него мёртв без единой ошибки. Ожидание: свидетель зелен при любом
#            законном способе указать дерево; повод записывается.
# Проверка результата: этот тест.
set -uo pipefail
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WIT="$REPO/hooks/tests/test_ci_status.sh"
TOOL="$REPO/scripts/ci-status.sh"
[ -f "$WIT" ] || { echo "FAIL: $WIT not found"; exit 1; }
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

# --- T1: контроль — без переменных свидетель зелен -------------------------------------------
OUT=$(cd "$REPO" && env -u CLAUDSOUL_REPO -u CLAUDE_HOME bash "$WIT" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T1 "контроль: свидетель красен и в чистом окружении: rc=$RC — ${OUT}"

# --- T2: CLAUDSOUL_REPO = ЭТО ЖЕ дерево — законная настройка, свидетель обязан остаться зелёным
OUT=$(cd "$REPO" && env -u CLAUDE_HOME CLAUDSOUL_REPO="$REPO" bash "$WIT" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T2 "с CLAUDSOUL_REPO=<это дерево> свидетель красен: rc=$RC — $(grep '^FAIL' <<< "$OUT" | head -2 | tr '\n' ' ')"

# --- T3: CLAUDE_HOME = настоящий ~/.claude — та же законная настройка, тот же исход -------------
OUT=$(cd "$REPO" && env -u CLAUDSOUL_REPO CLAUDE_HOME="$HOME/.claude" bash "$WIT" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok || bad T3 "с CLAUDE_HOME=<настоящий> свидетель красен: rc=$RC — $(grep '^FAIL' <<< "$OUT" | head -2 | tr '\n' ' ')"

# --- T4: сам инструмент под CLAUDSOUL_REPO: красный прогон своего коммита — повод НЕ записан ----
TMP=$(mktemp -d)
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/home"
MINE=$(cd "$REPO" && git rev-parse HEAD)
{
    printf '#!/usr/bin/env bash\nn=20; while [ $# -gt 0 ]; do case "$1" in -L) n="$2"; shift ;; esac; shift; done\n'
    printf 'head -n "$n" <<LINES\n1 %s completed failure\nLINES\n' "$MINE"
} > "$BIN/gh"; chmod +x "$BIN/gh"
# контроль: без переменной повод записывается
OUT=$(cd "$REPO" && env -u CLAUDSOUL_REPO -u CLAUDE_HOME PATH="$BIN:$PATH" HOME="$TMP/home" STATE_DIR="$TMP/state-a" CI_WAIT=0 bash "$TOOL" "$MINE" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T4a "контроль: rc=$RC — ${OUT}"
grep -q '"kind":"ci-red"' "$TMP/state-a/pending-events.jsonl" 2>/dev/null && ok || bad T4a "контроль: повод не записан и без переменной — подделка gh не сработала: ${OUT}"
# атака: та же сцена, переменная указывает на это же дерево
OUT=$(cd "$REPO" && env -u CLAUDE_HOME PATH="$BIN:$PATH" HOME="$TMP/home" STATE_DIR="$TMP/state-b" CI_WAIT=0 CLAUDSOUL_REPO="$REPO" bash "$TOOL" "$MINE" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok || bad T4b "rc=$RC — ${OUT}"
grep -q '"kind":"ci-red"' "$TMP/state-b/pending-events.jsonl" 2>/dev/null && ok \
    || bad T4b "под CLAUDSOUL_REPO=<это дерево> красный прогон своего коммита поводом не записан: $(ls -A "$TMP/state-b" 2>/dev/null | tr '\n' ' ')(пусто)"

echo ""
echo "adv2 ci-status env override tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
