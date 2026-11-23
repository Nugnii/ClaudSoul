#!/usr/bin/env bash
# ClaudSoul — единый источник истины по числам проекта.
# Результат: производные числа в документах совпадают с деревом
# Проверка результата: bash hooks/tests/test_derived_counts_inventory.sh даёт 0
#
#
# Числа в документах (README / CLAUDE.md / PLAN.md) дрейфовали, потому что
# правились вручную в нескольких местах. Этот скрипт считает их из файловой
# системы — единственный авторитетный источник. Запускать перед релизом и
# сверять статус-строки документов; CI-страж mcp-server/tests/test_doc_counts.py
# проверяет канонную строку README против этого вывода.
#
# Вывод — key=value (для парсинга) + человекочитаемая сводка в stderr.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

hooks=$(find hooks -maxdepth 1 -name '*.sh' ! -name '*-lib.sh' | wc -l | tr -d ' ')
libs=$(find hooks -maxdepth 1 -name '*-lib.sh' | wc -l | tr -d ' ')
skills=$(find skills -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
domains=$(find domains -maxdepth 1 -name '*.md' ! -name '_*' | wc -l | tr -d ' ')
bridges=$(find bridges -maxdepth 1 -name 'L*.md' | wc -l | tr -d ' ')
hook_test_files=$(find hooks/tests -maxdepth 1 -name 'test_*.sh' | wc -l | tr -d ' ')
mcp_test_files=$(find mcp-server/tests -maxdepth 1 -name 'test_*.py' | wc -l | tr -d ' ')
# Подключённых к событиям — из HOOKS_CONFIG в install.sh, а не из установленных настроек:
# число должно считаться в чистом дереве, где ~/.claude/settings.json ещё нет.
# Повод: «52 хука на события» в README и «45 подключены» жили рукой и разошлись с деревом
# на 4 и на 3 соответственно — обе фразы шли прозой, у которой не было генератора.
hooks_registered=$(python3 - "$ROOT/install.sh" <<'PYEOF' 2>/dev/null || echo 0
import json, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", src, re.S)
cfg = json.loads(m.group(1)) if m else {}
names = set()
def walk(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "command" and isinstance(v, str):
                names.update(re.findall(r"([a-z0-9-]+\.sh)", v))
            else:
                walk(v)
    elif isinstance(o, list):
        for v in o:
            walk(v)
walk(cfg)
print(len({n for n in names if not n.endswith("-lib.sh")}))
PYEOF
)

# Сколько хуков могут вмешаться в вызов и как именно. Считается по строке, где решение
# реально ПЕЧАТАЕТСЯ, а не упоминается в комментарии: слово «ask» в пояснении не делает
# хук спрашивающим. Повод: 28 августа 2026 проза «из 53 хуков отказывает ровно один»
# и «пятеро могут вмешаться» разошлись с деревом в справочнике и в мастер-копии правил —
# оба числа правились рукой и генератора не имели. Это второй такой случай за день.
_dec() { # _dec <deny|ask> → имена хуков через пробел
    for f in hooks/*.sh; do
        case "$f" in *-lib.sh) continue ;; esac
        grep -qE "permissionDecision\"?[[:space:]]*:[[:space:]]*\"?$1" \
            <<< "$(grep -nE "permissionDecision" "$f" | grep -vE "^[0-9]+:[[:space:]]*#")" \
            && printf '%s ' "$(basename "$f" .sh)"
    done
}
hooks_deny_list=$(_dec deny); hooks_ask_list=$(_dec ask)
hooks_deny=$(printf '%s' "$hooks_deny_list" | wc -w | tr -d ' ')
hooks_ask=$(printf '%s' "$hooks_ask_list" | wc -w | tr -d ' ')
# Поимённые списки — той же формы, что в документах: `имя`, через запятую с пробелом, по
# алфавиту (порядок glob). Число без состава сверялось реестром с 30 августа, а состав —
# никем: README держал «8 отказывают» при пяти именах в скобках, правила — четверых
# спрашивающих среди отказывающих (D378, 12 сентября 2026).
_canon() { printf '%s' "$1" | tr ' ' '\n' | grep . | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g'; }
hooks_deny_names=$(_canon "$hooks_deny_list"); hooks_ask_names=$(_canon "$hooks_ask_list")

cat <<OUT
hooks=$hooks
hooks_registered=$hooks_registered
hooks_deny=$hooks_deny
hooks_ask=$hooks_ask
hooks_deny_list=$hooks_deny_names
hooks_ask_list=$hooks_ask_names
libs=$libs
skills=$skills
domains=$domains
bridges=$bridges
hook_test_files=$hook_test_files
mcp_test_files=$mcp_test_files
OUT

echo "ClaudSoul: ${hooks} хуков (+${libs} библиотек), ${skills} скиллов, ${bridges} мостов, ${domains} доменов; тест-файлов: ${hook_test_files} хук + ${mcp_test_files} mcp" >&2

# --patch-claude-md (D65): три места с числами в CLAUDE.md правит скрипт, не рука.
# Повод: 2026-08-08 три ручные синхронизации за вечер (44→46 хуков) — тот же
# класс дрейфа, что «42 хуков» в ablation-протоколе. Замена по temp+mv (без
# sed -i: BSD/GNU расходятся); словоформы считаются, чтобы не писать «82 файл».
if [ "${1:-}" = "--patch-claude-md" ]; then
    # Различение «прочитал» / «не смог» — единым источником, а не копией в этом файле
    # (род дефекта B, scripts/defect-class-carriers.py). Подключается ЗДЕСЬ, а не в
    # шапке: голый прогон (его зовут doc-figures.sh, publish-public.sh и страж
    # test_doc_counts.py) правкой файлов не занимается, и ронять его из-за библиотеки,
    # которая нужна только на этой ветке, значило бы расширить радиус отказа.
    # Запасной ветки нет намеренно: без библиотеки ход упадёт с «command not found»,
    # а не досчитает молча по-своему.
    . "$ROOT/hooks/lib/unread-lib.sh"
    MD="${CLAUDE_MD_PATH:-$ROOT/CLAUDE.md}"
    ru_form() {
        local n=$1 m=$(( $1 % 100 )) d=$(( $1 % 10 ))
        if [ "$m" -ge 11 ] && [ "$m" -le 14 ]; then printf '%s' "$4"
        elif [ "$d" -eq 1 ]; then printf '%s' "$2"
        elif [ "$d" -ge 2 ] && [ "$d" -le 4 ]; then printf '%s' "$3"
        else printf '%s' "$4"; fi
    }
    # ОБЩИЙ ЗАМОК (род H): CLAUDE.md и README правит и этот генератор, и живая сессия, и
    # вторая сессия в том же дереве. Окно read-modify-write — от чтения `sed`/`awk` до
    # переименования. Временный файл РЯДОМ с целью, а не в /tmp: на разных файловых
    # системах `mv` перестаёт быть переименованием и становится копией, теряя атомарность.
    _CS_LOCK_LIB="${_CS_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../hooks" 2>/dev/null && pwd)/state-lock-lib.sh}"
    # shellcheck source=/dev/null
    [ -f "$_CS_LOCK_LIB" ] && . "$_CS_LOCK_LIB"
    command -v lock_acquire >/dev/null 2>&1 || {
        printf 'count-stats: нет state-lock-lib — документы правятся БЕЗ замка\n' >&2
        lock_acquire() { :; }; lock_release() { :; }
    }

    HOOK_TREE=$(ru_form "$hooks" "активный хук" "активных хука" "активных хуков")
    HOOK_TBL=$(ru_form "$hooks" "активный" "активных" "активных")
    TEST_W=$(ru_form "$hook_test_files" "файл" "файла" "файлов")
    SKILL_W=$(ru_form "$skills" "скилл" "скилла" "скиллов")
    lock_acquire "$MD"
    tmp="${MD}.tmp.$$"
    sed -E \
        -e "s@# [0-9]+ активн(ый|ых) хук(а|ов)? \+ [0-9]+ библиотек@# ${hooks} ${HOOK_TREE} + ${libs} библиотек@" \
        -e "s@\| [0-9]+ активн(ый|ых) \+ [0-9]+ библиотек \|@| ${hooks} ${HOOK_TBL} + ${libs} библиотек |@" \
        -e "s@\| Тесты \| [0-9]+ файл(а|ов)? тестов хуков \+ [0-9]+ mcp@| Тесты | ${hook_test_files} ${TEST_W} тестов хуков + ${mcp_test_files} mcp@" \
        -e "s@# [0-9]+ файл(а|ов)? тестов хуков \+ [0-9]+ mcp@# ${hook_test_files} ${TEST_W} тестов хуков + ${mcp_test_files} mcp@" \
        -e "s@# [0-9]+ скилл(а|ов)?: @# ${skills} ${SKILL_W}: @" \
        -e "s@\| Скиллы \| [0-9]+: @| Скиллы | ${skills}: @" \
        "$MD" > "$tmp" && mv "$tmp" "$MD"
    lock_release "$MD"
    # ГРАНИЦА ОХВАТА НАЗВАНА ТОМУ, КТО ЗОВЁТ (24 сентября 2026). Она стояла в комментарии
    # выше, но зовущий читает ВЫВОД, а не исходник: прибор ложной зелени позвал этот режим
    # ради ВСЕХ носителей числа, а правится только CLAUDE.md — свидетель продолжал краснеть
    # на `docs/mechanism-errors-and-backlog.ru.md`. Корень R5: объявление есть, до
    # действующего лица не доходит.
    echo "patched: $MD (hooks=${hooks}+${libs}, hook_test_files=${hook_test_files}, skills=${skills})" >&2
    echo "  охват: ТОЛЬКО этот файл. Все носители производных чисел правит scripts/docs-refresh-claims.sh" >&2

    # Канонные строки README (их проверяет CI-страж test_doc_counts) — тот же
    # класс ручного синка: второе проявление за день 2026-08-08 → механизм.
    #
    # Строка статистики отделена от строки версии (2026-08-21). Раньше версия и
    # производные числа жили в одной строке `**Current version:** v1.27.0 — 49 active
    # hooks`, и работа этого генератора выглядела для docs-family-check как бамп версии:
    # страж требовал обновить пять документов под релиз, которого не было. Носитель
    # двух независимых фактов путает любого, кто на него смотрит; разделение убирает
    # причину, а не очередное её следствие.
    #
    # Строка не патчится регекспами, а СОБИРАЕТСЯ целиком. Прежний вариант привязывался
    # к соседнему слову — `s@(активных хуков, )[0-9]+ скилл@` — и молча переставал
    # работать, когда склонение менялось: на 51 хуке форма стала «активный хук», и число
    # скиллов в русском README не обновлялось вовсе. Дефект дремал, потому что страж
    # ловит расхождение чисел, а расхождения не было, пока скиллов не прибавилось.
    # У собранной строки словоформ в условии нет — есть только в результате.
    # Производные версии, СВЕЖИЕ до правки, остаются свежими после неё: генератор ведёт обе
    # языковые версии синхронно, меняя только числа (14 сентября 2026). Снимок берётся ДО
    # правки — отставший по ПРОЗЕ был отставшим и до прогона и таким останется; штамповка
    # «всех подряд» замаскировала бы непереведённую правку источника.
    _DERIVED_CHK="$ROOT/scripts/docs-derived-check.sh"
    _DERIVED_FRESH=""
    [ -f "$_DERIVED_CHK" ] && _DERIVED_FRESH=$(bash "$_DERIVED_CHK" fresh 2>/dev/null | tr '\n' ' ')
    RM_EN="${COUNT_STATS_README:-$ROOT/README.md}"
    RM_RU="${COUNT_STATS_README_RU:-$ROOT/README.ru.md}"
    STATS_EN="**At a glance:** ${hooks} active hooks, ${skills} skills, ${bridges} inter-layer bridges, ${domains} domain nodes — tests green."
    BRIDGE_W=$(ru_form "$bridges" "межслойный мост" "межслойных моста" "межслойных мостов")
    DOMAIN_W=$(ru_form "$domains" "домен" "домена" "доменов")
    STATS_RU="**Коротко о системе:** ${hooks} ${HOOK_TREE}, ${skills} ${SKILL_W}, ${bridges} ${BRIDGE_W}, ${domains} ${DOMAIN_W} — тесты зелёные."
    # Наличие якоря проверяет тот же awk, что и патчит, буквальным index() — без regex.
    # Первая версия спрашивала `grep -q "^**At a glance:**"`, и это молча не работало:
    # на машине стоит ugrep, для которого `^**` — синтаксическая ошибка, а не литерал.
    # Два инструмента с разным пониманием одной строки — лишняя пара, где им расходиться
    # (pattern-shell-portability). Один инструмент, одно понимание, счётчик замен вместо
    # отдельной проверки.
    patch_stats_line() {   # patch_stats_line <файл> <префикс-якорь> <новая строка>
        [ -f "$1" ] || return 0
        # Тот же замок и тот же довод, что у CLAUDE.md выше: README правят из нескольких
        # мест, а временный файл рядом с целью держит `mv` переименованием.
        lock_acquire "$1"
        tmp="$1.tmp.$$"
        _hits=$(awk -v anchor="$2" -v line="$3" '
            index($0, anchor) == 1 { print line; n++; next }
            { print }
            END { print n + 0 > "/dev/stderr" }
        ' "$1" 2>"$tmp.n" > "$tmp")
        _n=$(cat "$tmp.n" 2>/dev/null); rm -f "$tmp.n"
        # Пусто — END не выполнился (awk убит сигналом, нет места под временный файл);
        # мусор — awk сообщил об ошибке своим текстом. Ни то, ни другое НЕ равно «ноль
        # замен»: до 4 сентября 2026 умолчание-ноль стояло в СЛОВЕ разбора `case`, а не в
        # переменной, и потому не срабатывало никогда — слово при пустом `_n` было
        # буквальным нулём, ни одна ветка не совпадала, `_n` оставалась пустой,
        # `[ "$_n" -eq 0 ]` падало кодом 2, ход уходил в `mv` и клал УСЕЧЁННЫЙ
        # файл поверх README. Провал чтения становился уничтожением файла с рапортом об
        # успехе. Мусор сводим к пустоте, пустоту предъявляем unread_or.
        case "$_n" in *[!0-9]*) _n="" ;; esac
        if ! unread_or _n 0 "счётчик замен awk ($1)"; then
            rm -f "$tmp"
            echo "count-stats: awk не сообщил число замен для $1 — файл НЕ ТРОНУТ" >&2
            lock_release "$1"; return 1
        fi
        if [ "$_n" -eq 0 ]; then
            rm -f "$tmp"
            echo "count-stats: в $1 нет строки статистики (якорь «$2») — не тронут" >&2
            lock_release "$1"; return 0
        fi
        mv "$tmp" "$1"
        lock_release "$1"
    }
    patch_stats_line "$RM_EN" "**At a glance:**"       "$STATS_EN" || true
    patch_stats_line "$RM_RU" "**Коротко о системе:**" "$STATS_RU" || true
    if _UNREAD_NOTE=$(unread_note); then
        echo "count-stats: $_UNREAD_NOTE — канонные строки README приведены НЕ ВСЕ" >&2
        exit 1
    fi
    for _d in $_DERIVED_FRESH; do
        bash "$_DERIVED_CHK" stamp "$_d" >/dev/null 2>&1 || \
            echo "count-stats: штамп производного $_d не переставлен — сверь bash scripts/docs-derived-check.sh" >&2
    done
    # РАПОРТ НАЗЫВАЕТ ГРАНИЦУ СВОЕЙ РАБОТЫ И ВЛАДЕЛЬЦА ОСТАЛЬНОГО (21 сентября 2026, D475).
    # Здесь стояло одно слово «patched», и оно читалось как «числа приведены». А приведены
    # ДВЕ канонные строки README и статистика CLAUDE.md; прочие числа документов держит
    # реестр `scripts/doc-claims.tsv`, и правит их другой владелец — `docs-refresh-claims.sh`.
    # Цена рапорта на частичной работе измерена в день заведения пункта: добавлен 86-й хук,
    # генератор сообщил «patched», сверщик производных чисел тут же назвал ВОСЕМЬ мест, и
    # они были поправлены рукой при живом писателе — правило «числа из генераторов, не
    # руками» обошло себя собственным инструментом.
    echo "patched: README canonical lines (${hooks} hooks, ${skills} skills)" >&2
    echo "count-stats: это КАНОННЫЕ строки README и статистика CLAUDE.md, а не все числа документов." >&2
    echo "  Остальные держит реестр scripts/doc-claims.tsv — правь их владельцем:" >&2
    echo "  bash scripts/docs-refresh-claims.sh run   (сверить: --check)" >&2
fi
