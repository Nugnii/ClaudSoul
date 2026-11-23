#!/usr/bin/env bash
# СУДИТ: дерево
# test_live_home_in_tests.sh — тест не читает установленную копию `~/.claude` вместо фикстуры.
#
# Результат: ни один тест дерева не берёт вход из живого `$HOME/.claude/hooks` или
#            `$HOME/.claude/CLAUDE.md` без песочницы (`HOME=` подменён), без названного пропуска
#            («SKIP: нет X») и без названной причины (`# live-home-ok: <почему>`); положительный
#            контроль — подложенный тест без всего этого ловится, отрицательные — три законные формы нет.
# Проверка результата: bash hooks/tests/test_live_home_in_tests.sh даёт 0
#
# Повод (D403, 13 сентября 2026). Тест, читающий `~/.claude`, зелен только на машине автора: в CI
# и контейнере входа нет — тест краснеет (поймано), молча зеленеет (ветка с входом не исполняется)
# либо честно проверяет фоллбек. «Показание» пункта считало по форме `HOME/.claude/hooks` и
# давало 12; разбор по одному: 9 подменяют HOME песочницей (`export HOME="$TMP"`, `FAKE_HOME`,
# `SANDBOX_HOME`), 1 несёт путь строкой в фикстуре для классификатора фаз, 2 читают живой каталог
# НАМЕРЕННО — утверждение об ОТСУТСТВИИ записи туда (изоляция), с веткой «каталога нет — доказывать
# нечего». Признак сужен по этому замеру: литерал `$HOME`/`${HOME}`/`~` (не `FAKE_HOME`), файл без
# присваивания `HOME=`, без `SKIP` и без `live-home-ok:`.
#
# НАЗВАННЫЙ ПРЕДЕЛ: песочница узнаётся по присваиванию `HOME=` где угодно в файле — тест, подменяющий
# HOME в одной ноге и читающий живой каталог в другой, пройдёт. Условие снятия: сверка потоком
# (какое значение HOME действует у строки чтения), а не по файлу.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
SELF="$(basename "$0")"
scan() {  # scan <каталог> → имена тестов, читающих живой ~/.claude без песочницы и без причины
    local f
    for f in "$1"/test_*.sh; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "$SELF" ] && continue
        # Код без комментариев берётся в переменную, а НЕ подаётся трубой в `grep -q`:
        # `-q` закрывает вход на первом совпадении, верхний grep получает SIGPIPE, и под
        # `pipefail` статус трубы становится 141 — утверждение врёт под нагрузкой
        # (сканер hooks/tests/test_assert_no_sigpipe.sh, класс правлен 13 сентября 2026).
        _lhit_body=$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null || true)
        grep -qF -e '$HOME/.claude/hooks' -e '${HOME}/.claude/hooks' -e '~/.claude/hooks' \
                 -e '$HOME/.claude/CLAUDE.md' -e '${HOME}/.claude/CLAUDE.md' -e '~/.claude/CLAUDE.md' \
                 <<< "$_lhit_body" || continue
        grep -qE '(^|[^A-Z_])(export )?HOME=' "$f" && continue
        grep -qE 'SKIP|live-home-ok:' "$f" && continue
        basename "$f"
    done
}
# --- T1: живое дерево тестов ---
HITS=$(scan "$DIR"); N=$(printf '%s\n' "$HITS" | grep -c . || true)
if [ "$N" -eq 0 ]; then ok; else bad "T1" "тесты читают живой ~/.claude без песочницы и причины ($N):"$'\n'"$HITS"; fi
# --- T2: положительный контроль — подложенный тест ловится ---
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
printf '#!/usr/bin/env bash\nLIVE="$HOME/.claude/hooks/state"\nls "$LIVE"\n' > "$TMP/test_bad.sh"
[ "$(scan "$TMP")" = "test_bad.sh" ] && ok || bad "T2" "подложенный носитель не пойман: «$(scan "$TMP")»"
# --- T3-T6: отрицательные контроли — четыре законные формы не ловятся ---
rm -f "$TMP"/test_*.sh
printf '#!/usr/bin/env bash\nexport HOME="$TMP/home"\nmkdir -p "$HOME/.claude/hooks/state"\n' > "$TMP/test_sandbox.sh"
printf '#!/usr/bin/env bash\nFAKE_HOME=$(mktemp -d)\nls "$FAKE_HOME/.claude/hooks"\n' > "$TMP/test_fake.sh"
printf '#!/usr/bin/env bash\n# live-home-ok: утверждение об отсутствии записи в живой каталог\nLIVE="$HOME/.claude/hooks/state"\n[ -d "$LIVE" ] || exit 0\n' > "$TMP/test_reason.sh"
printf '#!/usr/bin/env bash\n[ -f "$HOME/.claude/CLAUDE.md" ] || { echo "SKIP: нет установки"; exit 0; }\n' > "$TMP/test_skip.sh"
printf '#!/usr/bin/env bash\n# в комментарии путь $HOME/.claude/hooks не считается\necho x\n' > "$TMP/test_comment.sh"
[ -z "$(scan "$TMP")" ] && ok || bad "T3" "законная форма поймана: $(scan "$TMP" | tr '\n' ' ')"
echo "live home in tests: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
