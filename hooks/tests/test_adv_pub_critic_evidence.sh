#!/usr/bin/env bash
# СУДИТ: scripts/publish-public.sh
# test_adv_pub_critic_evidence.sh — свидетельство раунда свежего критика предъявляется БЕЗ раунда.
#
# Дыра. Гейт перед необратимой публикацией (scripts/publish-public.sh:163 — счёт
# `git log --diff-filter=A --name-only … -- 'hooks/tests/test_adv*'`) считает ПУТИ, ДОБАВЛЕННЫЕ
# КОММИТАМИ, и больше ничего: ни того, что файл дожил до публикуемого дерева, ни того, что в нём
# есть хоть байт, ни того, что это не копия уже лежащего теста. Число уходит в журнал
# (publish-public.sh:556), и замер scripts/critic-rounds-before-publish.sh:33 навсегда пишет
# «раунд был». Собственный довод скрипта (publish-public.sh:139 — «тесты атак остаются в дереве
# навсегда», «свежесть встроена в артефакт») ни одной из трёх форм не выдерживает.
#
# Доказано поведением на песочном репозитории, командой самого гейта:
#   · пустой файл hooks/tests/test_adv_x.sh                   → «свидетельство свежего критика: 1»
#   · файл добавлен и УДАЛЁН до публикации (в дереве его нет)  → «…: 1»
#   · побайтовая копия старого теста под новым именем          → «…: 1»
# Это ровно «зачёт любого вызова», против которого механизм заведён (D331).
#
# Результат: свидетельством считается только тест атаки, который есть в публикуемом дереве,
#            непуст и не является побайтовой копией уже лежащего теста; настоящий новый тест
#            по-прежнему засчитывается.
# Проверка результата: bash hooks/tests/test_adv_pub_critic_evidence.sh даёт 0
#
# Песочный: живой репозиторий не правится и его состояние не читается; всё в своём каталоге
# под ${HOME} (не /tmp — гейт публикации судит пути), STATE_DIR подменён на песочный.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"

# Предмет этого свидетеля в публичный снимок не входит (подсистема публикации). В неполном дереве
# «файла нет» значит «изъят по решению», а не «пропал»: пропуск называется, дефект не
# объявляется — иначе один канал несёт два состояния мира (корень R6).
UNIVERSE_ROOT="$ROOT"; . "$ROOT/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_adv_pub_critic_evidence" "подсистема публикации"; exit 0
fi
PUB="$ROOT/scripts/publish-public.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
[ -f "$PUB" ] || { echo "FAIL: нет $PUB"; exit 1; }
# shellcheck source=/dev/null
. "$ROOT/hooks/timeout-lib.sh" 2>/dev/null || { echo "FAIL: нет hooks/timeout-lib.sh"; exit 1; }

SB=$(mktemp -d "${HOME}/.claudsoul-test-adv-critic.XXXXXX") || exit 1
trap 'rm -rf "$SB"' EXIT
gitc() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

# build <имя> → каталог песочного репозитория с базовым коммитом и журналом публикации на нём
build() {
    local d="$SB/$1"
    mkdir -p "$d/scripts/publish" "$d/hooks/tests" "$SB/state-$1"
    cp "$PUB" "$d/scripts/publish-public.sh"
    echo "1.0.0" > "$d/VERSION"
    : > "$d/scripts/publish/exclude.txt"
    : > "$d/scripts/publish/redact.sed"
    : > "$d/scripts/publish/forbidden.txt"
    printf '#!/usr/bin/env bash\n# старый тест атаки, лежал до окна\ntest 1 = 1 || exit 1\nexit 0\n' \
        > "$d/hooks/tests/test_adv_old.sh"
    ( cd "$d" && git init -q . && git add -A && gitc commit -qm base ) >/dev/null
    printf '{"ts":"2026-09-13T00:00:00Z","sha":"%s","tag":"v0.9.0","critic":"rounds","evidence":1}\n' \
        "$( cd "$d" && git rev-parse HEAD )" > "$SB/state-$1/publications.jsonl"
    echo "$d"
}

# evidence <имя> <каталог> → число зачтённых свидетельств по выводу самого гейта.
# Пайпов в grep -q здесь нет намеренно: grep выходит на первом совпадении, производитель
# получает SIGPIPE, и под pipefail успешная проверка прочиталась бы как провал.
evidence() {
    local out rc
    out=$( cd "$2" && STATE_DIR="$SB/state-$1" run_with_timeout 60 bash scripts/publish-public.sh --push 2>&1 )
    rc=$?
    case "$rc" in 124) echo "TIMEOUT"; return ;; esac
    if grep -q 'свидетельство свежего критика' <<<"$out"; then
        sed -n 's/.*свидетельство свежего критика: \([0-9]*\).*/\1/p' <<<"$out" | head -1
    elif grep -q 'раунда свежего критика' <<<"$out"; then
        echo 0
    else
        echo "BROKEN"; sed 's/^/      /' <<<"$out" >&2
    fi
}

# --- T1 (положительный контроль): настоящий новый тест атаки засчитывается -------------------
D=$(build real)
printf '#!/usr/bin/env bash\n# новый тест атаки\n[ 1 = 1 ] || exit 1\nexit 0\n' > "$D/hooks/tests/test_adv_fresh_finding.sh"
( cd "$D" && git add -A && gitc commit -qm fresh ) >/dev/null
N=$(evidence real "$D")
[ "$N" = 1 ] && ok || bad "T1" "настоящий новый тест атаки обязан считаться: ждали 1, получили ${N}"

# --- T2: ПУСТОЙ файл с именем test_adv* ------------------------------------------------------
D=$(build empty)
: > "$D/hooks/tests/test_adv_nothing.sh"
( cd "$D" && git add -A && gitc commit -qm empty ) >/dev/null
N=$(evidence empty "$D")
[ "$N" = 0 ] && ok || bad "T2" "пустой файл зачтён как раунд критика: свидетельств ${N} (ждали 0)"

# --- T3: свидетельство добавлено и УДАЛЕНО до публикации — в дереве его нет -------------------
D=$(build ghost)
printf '#!/usr/bin/env bash\nexit 0\n' > "$D/hooks/tests/test_adv_ghost.sh"
( cd "$D" && git add -A && gitc commit -qm ghost-add && git rm -q hooks/tests/test_adv_ghost.sh && gitc commit -qm ghost-del ) >/dev/null
LEFT=$( cd "$D" && git ls-files 'hooks/tests/test_adv*' | grep -c ghost )
[ "$LEFT" = 0 ] || bad "T3-фикстура" "файл должен был исчезнуть из дерева, а он есть"
N=$(evidence ghost "$D")
[ "$N" = 0 ] && ok || bad "T3" "удалённое из дерева свидетельство зачтено: ${N} (ждали 0); довод скрипта — «тесты атак остаются в дереве»"

# --- T4: побайтовая копия уже лежащего теста под новым именем --------------------------------
D=$(build copy)
cp "$D/hooks/tests/test_adv_old.sh" "$D/hooks/tests/test_adv_old_again.sh"
( cd "$D" && git add -A && gitc commit -qm copy ) >/dev/null
N=$(evidence copy "$D")
[ "$N" = 0 ] && ok || bad "T4" "копия старого теста под новым именем зачтена как свежий раунд: ${N} (ждали 0)"

# --- T5 (контроль уже закрытого): git mv старого теста свидетельством НЕ становится ----------
D=$(build rename)
( cd "$D" && git mv hooks/tests/test_adv_old.sh hooks/tests/test_adv_old_renamed.sh && gitc commit -qm rename ) >/dev/null
N=$(evidence rename "$D")
[ "$N" = 0 ] && ok || bad "T5" "переименование старого теста зачтено: ${N} (ждали 0)"

echo "passed: ${PASS}, failed: ${FAIL}"
[ "$FAIL" -eq 0 ] && exit 0
exit 1
