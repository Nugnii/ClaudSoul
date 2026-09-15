#!/usr/bin/env bash
# test_payload_cwd_root.sh — страж берёт корень репозитория из cwd СЕССИИ, а не из каталога процесса.
#
# Результат: ни в одном hooks/*.sh нет строки кода, где `rev-parse --show-toplevel`
#            вызван без `git -C` на ТОЙ ЖЕ строке; и ни в одном hooks/*.sh, кроме самой
#            session-registry-lib.sh, нет строки кода с `sr_register_session` без каталога
# Проверка результата: bash hooks/tests/test_payload_cwd_root.sh даёт 0
#
# Повод (D275, 2 сентября 2026). Класс «вход берётся из окружения процесса вместо payload
# сессии» приходил ТРЕТИЙ раз: v1.12.4 (claude-md-size-check), 2026-08-08 e6575ce (три
# стража аудита переносимости), и снова — backlog-vanish-check, написанный 26 августа,
# после обеих починок. Обе прежние волны кончились правкой найденных файлов и не оставили
# ни теста, ни стража, поэтому четвёртую волну встречать было нечем. Процесс хука не
# обязан стоять в каталоге сессии: Claude Code запускает его из своего cwd, и `git
# rev-parse` без `-C` отвечает про чужое дерево либо молчит.
#
# ПОЧЕМУ ПОСТРОЧНО, А НЕ ПОФАЙЛОВО. Пофайловый признак («в файле есть -C») зеленеет там,
# где голый вызов стоит на одной строке, а `git -C "$CWD"` — на другой: он ловит первую
# волну и пропускает вторую. Тот же род, что чинили в D269/D272 (признак снят с вида
# текста, а различать надо роль строки).
#
# КОНТРПРИМЕРЫ, проверяются ниже:
#   · строка с `git -C "$CWD" rev-parse --show-toplevel` — не нарушение (это и есть починка);
#   · комментарий с голой формой — не нарушение (строка не исполняется);
#   · фикстура с голым вызовом в коде — нарушение, тест краснеет (мутация).
# ОБЛАСТЬ. Только hooks/*.sh: у хука есть payload с `.cwd`, и каталог процесса ему не вход.
# scripts/, bin/, install.sh исключены намеренно — это CLI, запускаемые владельцем, у них
# payload'а нет и каталог процесса есть ЗАКОННЫЙ вход (scripts/mechanisms-born.sh:36,
# scripts/publish-public.sh:89, bin/resolve-claudsoul-repo.sh:28 и ещё два).
# Названный предел: ловится ровно форма `rev-parse --show-toplevel` (T1-T5) и форма
# `sr_register_session` без аргумента (T6-T7b, D277). Прочие способы взять каталог из
# окружения (`$PWD/подкаталог`, `CLAUDE_PROJECT_DIR`) признаком НЕ ловятся — в него
# свалились бы места с разными последствиями, и часть отказов стала бы ложной.
# Условие снятия: появится разбор «откуда узел берёт каталог» по данным, а не по форме
# вызова, — тогда признак заменяется им, и предел уходит.
#
# ВТОРАЯ ФОРМА КЛАССА (D277, 3 сентября 2026): `sr_register_session` без аргумента.
# Последствие у неё одно и названо: Session Registry приписывает сессию каталогу ПРОЦЕССА
# хука, а не каталогу сессии (прогон активатора из `/` давал `"project": "/"`).
# ОБЛАСТЬ у этой формы у́же: `hooks/*.sh` БЕЗ `session-registry-lib.sh`. Там живёт сама
# функция и её внутренний вызов на пересоздании носителя дельты — признаку он неотличим
# от нарушения, а голым он остаётся законно: третьего аргумента у `sr_update_knowledge`
# нет, пока его некому передать.
# НАЗВАННЫЙ ПРЕДЕЛ (не измерено стражем, держится поведенческой пробой): единственный
# вызывающий, который дошёл бы до этого внутреннего вызова с payload'ом на руках, —
# `hooks/knowledge-frontmatter-check.sh:91` (`sr_update_knowledge` двумя аргументами).
# Построчным признаком эта форма НЕ ловится намеренно: тот же двухаргументный вызов есть
# у CLI `knowledge-counter-bump.sh:609`, где каталог процесса — законный вход, и общий
# признак дал бы там ложный отказ.
# РУБЕЖА У НЕЁ ПОКА НЕТ, и это сказано числом, а не умолчанием: проба 3 сентября 2026
# (хук из `/`, cwd сессии только полем `.cwd` payload) записала в реестр `"project": "/"`.
# «Проверка» пункта D277 её тоже не мерит — файл вне перечня, отданного тому пункту.
# Форма отдана отдельным кандидатом в долг вместе с этой пробой; когда он закроется,
# рубеж встанет там, а не здесь.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0

# bare_toplevel <файл...> → печатает «файл:строка» для строк кода с голым вызовом
bare_toplevel() {
    for f in "$@"; do
        [ -f "$f" ] || continue
        awk -v F="$f" '
            { line=$0
              sub(/^[[:space:]]+/, "", line)
              if (substr(line, 1, 1) == "#") next
              if (line !~ /rev-parse --show-toplevel/) next
              if (line ~ /git -C/) next
              printf "%s:%d\n", F, FNR
            }' "$f"
    done
}

# T1. Ни один хук дерева не берёт корень из каталога процесса.
BAD=$(cd "$ROOT" && bare_toplevel hooks/*.sh)
if [ -z "$BAD" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [T1]: корень репозитория взят из каталога процесса, а не из cwd payload:"
    printf '%s\n' "$BAD" | sed 's/^/    /'
fi

# T2 (мутация). На фикстуре с голым вызовом признак обязан сработать — иначе T1 зелен ни о чём.
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
printf '%s\n' '#!/usr/bin/env bash' 'REPO=$(git rev-parse --show-toplevel)' > "$TMP/bad.sh"
if [ -n "$(bare_toplevel "$TMP/bad.sh")" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T2]: признак не сработал на фикстуре с голым вызовом"
fi

# T3 (контрпример). Починенная форма нарушением не считается.
printf '%s\n' '#!/usr/bin/env bash' 'REPO=$(git -C "$CWD" rev-parse --show-toplevel)' > "$TMP/good.sh"
if [ -z "$(bare_toplevel "$TMP/good.sh")" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T3]: починенная форма названа нарушением"
fi

# T4 (контрпример). Комментарий с голой формой — не код.
printf '%s\n' '#!/usr/bin/env bash' '# было: git rev-parse --show-toplevel' > "$TMP/comment.sh"
if [ -z "$(bare_toplevel "$TMP/comment.sh")" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T4]: комментарий засчитан нарушением"
fi

# T5 (контрпример на пофайловую слепоту). Голый вызов и починенный в ОДНОМ файле:
# пофайловый признак такое пропускает, построчный обязан назвать голую строку.
printf '%s\n' '#!/usr/bin/env bash' 'A=$(git -C "$CWD" rev-parse --show-toplevel)' 'B=$(git rev-parse --show-toplevel)' > "$TMP/mixed.sh"
if [ "$(bare_toplevel "$TMP/mixed.sh")" = "$TMP/mixed.sh:3" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T5]: голая строка рядом с починенной не названа"
fi

# bare_register <файл...> → «файл:строка» для строк кода, зовущих sr_register_session
# без аргумента. Определение функции и её объявление в шапке — не вызовы.
bare_register() {
    for f in "$@"; do
        [ -f "$f" ] || continue
        awk -v F="$f" '
            { line=$0
              sub(/^[[:space:]]+/, "", line)
              if (substr(line, 1, 1) == "#") next
              if (line !~ /sr_register_session/) next
              if (line ~ /sr_register_session[[:space:]]*\(/) next
              if (line ~ /sr_register_session[[:space:]]+[^[:space:];&|)]/) next
              printf "%s:%d\n", F, FNR
            }' "$f"
    done
}

# T6 (D277). Ни один хук дерева не регистрирует сессию без каталога.
BAD6=$(cd "$ROOT" && bare_register $(ls hooks/*.sh | grep -v 'session-registry-lib\.sh$'))
if [ -z "$BAD6" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1))
    echo "FAIL [T6]: сессия регистрируется от каталога процесса, а не от cwd payload:"
    printf '%s\n' "$BAD6" | sed 's/^/    /'
fi

# T7 (мутация). На фикстуре с голым вызовом признак обязан сработать — иначе T6 зелен ни о чём.
printf '%s\n' '#!/usr/bin/env bash' 'sr_register_session' > "$TMP/bare-reg.sh"
if [ -n "$(bare_register "$TMP/bare-reg.sh")" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T7]: признак не сработал на фикстуре с голым вызовом"
fi

# T7b (контрпример). Вызов с каталогом и определение функции нарушением не считаются.
printf '%s\n' '#!/usr/bin/env bash' 'sr_register_session() { :; }' 'sr_register_session "$CWD"' \
    'sr_register_session "$PAYLOAD_CWD"' > "$TMP/good-reg.sh"
if [ -z "$(bare_register "$TMP/good-reg.sh")" ]; then
    PASS=$((PASS+1))
else
    FAIL=$((FAIL+1)); echo "FAIL [T7b]: починенная форма или определение названы нарушением"
fi

echo ""
echo "payload cwd root: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
