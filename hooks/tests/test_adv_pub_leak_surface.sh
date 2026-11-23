#!/usr/bin/env bash
# СУДИТ: scripts/publish/
# test_adv_pub_leak_surface.sh — идентификатор сессии уходит наружу в УСЕЧЁННОЙ форме,
# и гейт публикации его не видит, хотя обещает видеть.
#
# ДЫРА. scripts/publish/forbidden.txt:45-46 объявляет раздел
#     # --- Идентификаторы сессий (UUID) ---
#     [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
# то есть ОБЕЩАЕТ «идентификаторы сессий», а ЛОВИТ ровно одну их запись — полную.
# Проект же пишет их усечёнными, и это его собственная сложившаяся форма:
#     docs/ab-authorization-2026-08-07.md:8-17   — таблица из 10 строк «<усечённый идентификатор>»
#     hooks/tests/test_adv_arc2_legacy_skill_name.sh:20-21 — «<усечённый идентификатор>, <усечённый идентификатор> и <усечённый идентификатор>»
#     CHANGELOG.md:3348                          — «транскрипт `<идентификатор>.jsonl` L5084»
# Ни exclude.txt, ни redact.sed этих файлов и токенов не касаются: 14 вхождений
# доживают до `git push --force` (scripts/publish-public.sh:544) нетронутыми.
#
# ЧЕМ ДОКАЗАНА, а не придирка. Форма «<8hex>…» / «<8hex>-<4hex>…» проверена на мире:
# все 14 усечённых токенов снимка — префиксы НАСТОЯЩИХ расшифровок сессий владельца
# в ~/.claude/projects/*/ (14 из 14, ложных 0). Признак не выдуман под тест: усечение
# многоточием ставит сам проект, чтобы идентификатор «не выглядел» идентификатором.
# Полный UUID той же сессии гейт роняет; усечённый — пропускает. Одна и та же величина,
# два исхода, разница только в записи.
#
# Почему это утечка, а не косметика: `scripts/regen-seed.py:74-82` чистит `source_session`
# и `provenance_log[].session` — то есть проект СЧИТАЕТ идентификатор сессии непубликуемым
# и вычищает его из frontmatter. В прозе и в таблицах он остаётся, а второй рубеж
# (гейт) настроен на форму, которой в прозе не бывает. Обещание и поведение разошлись.
#
# Зелёная сторона (чем чинится): либо признак гейта расширяется на усечённую запись
#     [0-9a-f]{8}(-[0-9a-f]{4}){0,3}…
# (тогда гейт краснеет и не пускает снимок, пока три файла не зачищены), либо носители
# уходят в exclude.txt. Тест зеленеет в обоих случаях: он требует, чтобы в собранном
# снимке не осталось усечённого идентификатора, МИМО которого гейт молчит.
#
# Тест песочный: живое дерево не правит, собирает снимок в $HOME и уносит за собой.
# Ничего не чинит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# Предмет этого свидетеля в публичный снимок не входит (конфиг публикации scripts/publish/). В неполном дереве
# «файла нет» значит «изъят по решению», а не «пропал»: пропуск называется, дефект не
# объявляется — иначе один канал несёт два состояния мира (корень R6).
UNIVERSE_ROOT="$REPO"; . "$REPO/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_adv_pub_leak_surface" "конфиг публикации scripts/publish/"; exit 0
fi
CONFIG_DIR="$REPO/scripts/publish"
EXCLUDE_FILE="$CONFIG_DIR/exclude.txt"
REDACT_FILE="$CONFIG_DIR/redact.sed"
FORBIDDEN_FILE="$CONFIG_DIR/forbidden.txt"
for f in "$EXCLUDE_FILE" "$REDACT_FILE" "$FORBIDDEN_FILE"; do
    [ -f "$f" ] || { echo "FAIL: нет конфига публикации ${f}"; exit 1; }
done
command -v git >/dev/null 2>&1 || { echo "SKIP: git недоступен"; exit 0; }
( cd "$REPO" && git rev-parse HEAD >/dev/null 2>&1 ) || { echo "SKIP: не git-репозиторий"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

# Песочница в $HOME, а не в /tmp: часть стражей проекта отбрасывает пути */tmp/*.
SANDBOX="${HOME}/.claudsoul-adv-publeak.$$"
STAGE="$SANDBOX/stage"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT
mkdir -p "$STAGE" || { echo "FAIL: не создать песочницу ${SANDBOX}"; exit 1; }

# --- Снимок собирается ТЕМ ЖЕ порядком, что publish-public.sh:198-260 -------------
( cd "$REPO" && git archive HEAD ) | tar -x -C "$STAGE" \
    || { echo "FAIL: git archive не отработал"; exit 1; }

while IFS= read -r line; do                        # шаг 2: exclude.txt (код скопирован)
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
    [ -z "$line" ] && continue
    for target in "$STAGE"/$line; do
        [ -e "$target" ] || continue
        rm -rf "$target"
    done
done < "$EXCLUDE_FILE"

if [ -d "$CONFIG_DIR/replace" ]; then              # шаг 2b: подмены
    while IFS= read -r -d '' src; do
        rel="${src#"$CONFIG_DIR/replace/"}"
        [ -e "$STAGE/$rel" ] && cp "$src" "$STAGE/$rel"
    done < <(find "$CONFIG_DIR/replace" -type f -print0)
fi

# Признак усечённого идентификатора сессии — форма, которой пишет сам проект.
TRUNC_RE='[0-9a-f]{8}(-[0-9a-f]{4})?…'

# Шаг 3 (redact.sed) — только по носителям: доказывается, что замены токен не трогают,
# а прогон по всем 1080 файлам стоил бы минуты процессорного времени ни за что.
CARRIERS=$(grep -rIlE "$TRUNC_RE" "$STAGE" 2>/dev/null || true)
if [ -n "$CARRIERS" ]; then
    printf '%s\n' "$CARRIERS" | while IFS= read -r c; do
        sed -i.bak -f "$REDACT_FILE" "$c" 2>/dev/null && rm -f "$c.bak"
    done
fi

# --- Гейт 4a: тот же цикл, что publish-public.sh:333-344, по настоящему forbidden.txt --
gate_catches() {   # gate_catches <строка> → 0 если хоть один шаблон её ловит
    local s="$1" pat
    while IFS= read -r pat; do
        pat="${pat%%#*}"
        pat="$(echo "$pat" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
        [ -z "$pat" ] && continue
        grep -qE -- "$pat" <<< "$s" && return 0
    done < "$FORBIDDEN_FILE"
    return 1
}

# Положительный контроль: полная запись того же идентификатора гейту видна. Без него
# зелень теста неотличима от «шаблоны не прочитались» (пустой forbidden.txt дал бы то же).
# Префикс СИНТЕТИЧЕСКИЙ: прежде здесь стоял настоящий, взятый из расшифровки владельца, —
# то есть проверка утечки сама вносила в дерево то, что проверяет (поймано гейтом 15
# сентября 2026). Форма сохранена полностью, значение придумано.
if gate_catches "feedbeef-0000-0000-0000-000000000000"; then
    ok "положительный контроль: полный UUID гейт ловит — шаблоны прочитаны"
else
    bad "положительный контроль провален: гейт не ловит даже полный UUID — прибор сломан, остальное недостоверно"
    echo "  проверено: ${FORBIDDEN_FILE}"
    echo; echo "Итог: пройдено ${PASS}, провалено ${FAIL}"
    exit 1
fi

# --- Атака: усечённые идентификаторы в собранном снимке -----------------------------
TOKENS=$(grep -rIohE "$TRUNC_RE" "$STAGE" 2>/dev/null | sort -u)
TOKEN_N=$(grep -c . <<< "$TOKENS" || true)

UNCAUGHT=0
UNCAUGHT_LIST=""
if [ "${TOKEN_N:-0}" -gt 0 ]; then
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        gate_catches "$tok" || { UNCAUGHT=$((UNCAUGHT + 1)); UNCAUGHT_LIST="$UNCAUGHT_LIST $tok"; }
    done <<< "$TOKENS"
fi

if [ "$UNCAUGHT" -eq 0 ]; then
    ok "усечённых идентификаторов сессий, невидимых гейту, в снимке нет (найдено токенов: ${TOKEN_N:-0})"
else
    bad "в снимок уходит ${UNCAUGHT} усечённых идентификаторов сессий, и ни один шаблон forbidden.txt их не ловит"
    echo "     токены:${UNCAUGHT_LIST}"
    echo "     носители (файл:строка):"
    grep -rInE "$TRUNC_RE" "$STAGE" 2>/dev/null | sed "s|^${STAGE}/|       |" | cut -c1-160 | head -20
fi

# --- Сверка признака с миром: усечённые токены — префиксы НАСТОЯЩИХ сессий -----------
# Не гейтится (на чистой машине расшифровок нет), но печатается числом: без неё
# «усечённый идентификатор» — предположение о форме, а не утверждение об утечке.
PROJ_DIR="${HOME}/.claude/projects"
if [ -d "$PROJ_DIR" ] && [ "${TOKEN_N:-0}" -gt 0 ]; then
    REAL=0
    while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        pre="${tok%…}"
        _found=$(find "$PROJ_DIR" -maxdepth 2 -name "${pre}*" -print -quit 2>/dev/null)
        if [ -n "$_found" ]; then
            REAL=$((REAL + 1))
        fi
    done <<< "$TOKENS"
    echo "  · сверка с миром: ${REAL} из ${TOKEN_N} усечённых токенов — префиксы настоящих расшифровок в ${PROJ_DIR}"
else
    echo "  · сверка с миром: НЕ ИЗМЕРЕНО (нет ${PROJ_DIR}) — форма признака не подтверждена на этой машине"
fi

echo
echo "Итог: пройдено ${PASS}, провалено ${FAIL}"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
