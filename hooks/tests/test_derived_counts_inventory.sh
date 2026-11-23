#!/usr/bin/env bash
# СУДИТ: hooks/docs-derived-lib.sh scripts/count-stats.sh scripts/docs-refresh-claims.sh
# test_derived_counts_inventory.sh — инвентарь производных чисел в документах
# состояния: поверхности находятся ПЕРЕЧИСЛЕНИЕМ, а не ожогами стражей.
#
# Корень (2026-08-08): счётные фразы всплывали по одной — 4-е место в CLAUDE.md,
# потом канонные строки README — каждый раз постфактум, срабатыванием стража.
# Этот тест греп-ит все документы состояния по всем счётным фразам и сверяет
# каждое найденное число с count-stats. Новая поверхность с фразой из списка
# попадает под сверку автоматически; новая ФРАЗА добавляется в PATTERNS здесь.
#
# Цена этого устройства измерена 28 августа 2026: два числа в README.ru прожили
# устаревшими несколько релизов — «52 хука на события» (правда: 48) и «из 52 хуков 45
# подключены» (правда: 55 и 48). Обе фразы не входили в список форм, и страж молчал.
# Списком форм он и остаётся сознательно: голый корень («[0-9]+ хук[а-я]*») ловит
# исторические числа модульных доков («41 хук к моменту заведения конвенции» — законно)
# и родительный падеж при другом существительном («33 проверки: 13 детектора, 10 хука»).
# Правило «число рядом с существительным» здесь ложно, а «число о НАСТОЯЩЕМ»
# наблюдаемого признака не имеет.
#
# Хроники (CHANGELOG, SESSION, BACKLOG*, архивы) сознательно вне охвата:
# исторические числа там легитимны.
#
# То же и для хроники ВНУТРИ документа состояния (2026-08-21): секция Roadmap в
# README перечисляет закрытые разрывы по релизам, и «незакрыты во всех 21 скилле»
# там относится к v1.12.1. Скан по всему файлу требовал переписать эту строку под
# текущее число — то есть подделать запись о прошлом. Roadmap вырезается перед
# сверкой; правило «документ состояния ≠ хроника» действует и внутри файла.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

eval "$(bash "$ROOT/scripts/count-stats.sh" 2>/dev/null | grep -E '^(hooks|hooks_registered|hooks_deny|hooks_ask|libs|skills|hook_test_files)=')"

# Фраза → эталон. Формат: "ERE-паттерн|имя эталона".
# Формат: "ERE-паттерн|эталон|поверхность". Поверхность — narrow или wide, и выбор её
# определяется тем, насколько признак САМООПРЕДЕЛЯЕМ.
#
# «N скиллов» самоопределяемым не является: замер 28 августа 2026 при расширении поверхности
# показал, что та же форма означает порог («при >10 скиллов»), диапазон шагов («Step 2–7
# скилла») и состав ЧУЖОЙ системы («181 скилл» у конкурента). Такой признак проверяется
# только там, где документ заведомо описывает НАШ состав, — narrow.
#
# «N отказывают», «N поднимают permissionDecision» самоопределяемы: другого предмета у этих
# фраз в наших документах нет. Их можно проверять по всем документам состояния — wide.
# Именно они и разошлись 28 августа 2026 в справочнике и мастер-копии правил, куда прежний
# перечень поверхностей не смотрел.
# УЗКАЯ ПОВЕРХНОСТЬ ЖИВЁТ В РЕЕСТРЕ (13 сентября 2026, D377). Здесь стояли семь строк
# «N active hooks», «N библиотек», «N скиллов» и т. п. — второй перечень тех же мест, что
# держит `scripts/doc-claims.tsv`, и они разошлись: английская форма README жила в реестре и
# отсутствовала здесь (число 63 при мире 64 тест пропускал, реестр ловил). Теперь узкая
# поверхность — сам реестр, сверенный по коммит-обусловленным ключам (`--keys`): числа,
# которые растит работа системы, а не коммит, сюда не входят намеренно (D268).
# Перечень — у владельца реестра (имя @commit, scripts/docs-refresh-claims.sh), здесь только имя:
# свой перечень в этом файле уже расходился с реестром (D377).
NARROW_KEYS="@commit"
PATTERNS=(
    '[0-9]+ хук(а|ов)? на события|hooks_registered|wide'
    '[0-9]+ подключены к событиям|hooks_registered|wide'
    '[0-9]+ отказывают|hooks_deny|wide'
    '[0-9]+ спрашивают|hooks_ask|wide'
    '[0-9]+ возвращают|hooks_deny|wide'
    '[0-9]+ поднимают|hooks_ask|wide'
    '[0-9]+ return `?deny|hooks_deny|wide'
    '[0-9]+ raise|hooks_ask|wide'
)

# Узкая поверхность — документы, заведомо описывающие НАШ состав.
NARROW_DOCS=("$ROOT/README.md" "$ROOT/README.ru.md" "$ROOT/CLAUDE.md")
while IFS= read -r f; do NARROW_DOCS+=("$f"); done < <(ls "$ROOT/.claude-docs/modules/"*.md 2>/dev/null)

# Широкая — все документы состояния ПО ПРАВИЛУ: отслеживаемый markdown минус хроника
# (CHANGELOG / SESSION / BACKLOG / датированные разборы), минус база знаний (там числа
# принадлежат своим замерам), минус черновики. То же правило, что в scripts/docs-inventory.sh.
WIDE_DOCS=()
while IFS= read -r f; do WIDE_DOCS+=("$ROOT/$f"); done < <(
    git -C "$ROOT" ls-files --cached --others --exclude-standard '*.md' 2>/dev/null | grep -vE '_drafts/|^knowledge/|(^|/)(CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG|BACKLOG-archive)\.md$|-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$'
)

# ОТСТАВШИЙ ПРОИЗВОДНЫЙ ДОКУМЕНТ ПРОПУСКАЕТСЯ — тем же владельцем, что у реестра
# (18 сентября 2026, D462). Перевод, помеченный `stale`, пересобирается целиком перед
# публикацией, и `scripts/docs-refresh-claims.sh --check` его не сверяет («пропущено: производный документ отстал
# от источника»; запись `run` с D1223 числа в нём правит, как count-stats). Этот тест того же флага не знал
# и краснел на документе, который чинить запрещено: расхождение вскрылось, когда число
# отказывающих хуков выросло с 10 до 11 — русский справочник реестр обновил, английский
# пропустил, а тест потребовал совпадения. Один факт — один владелец: `docs_derived_state`.
# Названный предел: если библиотеки нет, пропуск не работает и тест судит ВСЕ документы,
# включая отставшие переводы — это прежнее поведение, то есть строже, а не слабее, и потому
# безопасный отказ. Условие снятия: `docs-derived-lib.sh` станет обязательной зависимостью
# набора (её отсутствие будет валить тест явно), и тогда молчаливая ветка станет не нужна.
_DERIVED_LIB="$(cd "$(dirname "$0")/.." && pwd)/docs-derived-lib.sh"
# shellcheck source=/dev/null
[ -f "$_DERIVED_LIB" ] && . "$_DERIVED_LIB" 2>/dev/null
is_stale_derived() {
    command -v docs_derived_state >/dev/null 2>&1 || return 1
    [ "$(DOCS_DERIVED_ROOT="$ROOT" docs_derived_state "$1" 2>/dev/null)" = stale ]
}

# Тело документа без секции Roadmap: там числа исторические, привязанные к релизу.
state_part() { awk '/^## Roadmap/ {skip=1; next} /^## / {skip=0} !skip' "$1" 2>/dev/null; }

scan() { # scan <файл> <поверхность> → 0 чисто, 1 расхождения (печатает их)
    local file="$1" want="$2" dirty=0 entry re key surface truth m num
    for entry in "${PATTERNS[@]}"; do
        surface="${entry##*|}"
        [ "$surface" = "$want" ] || continue
        entry="${entry%|*}"
        re="${entry%|*}"; key="${entry##*|}"
        truth=$(eval "printf '%s' \"\$$key\"")
        while IFS= read -r m; do
            [ -n "$m" ] || continue
            num=$(printf '%s' "$m" | grep -oE '^[0-9]+')
            if [ "$num" != "$truth" ]; then
                echo "  $file: «${m}» ≠ ${key}=${truth}"
                dirty=1
            fi
        done < <(state_part "$file" | grep -hoE "$re" 2>/dev/null)
    done
    return "$dirty"
}

# --- T1: все документы состояния согласованы с count-stats ---
DIRTY=""
# Узкая поверхность — реестр утверждений по коммит-обусловленным ключам: код 1 — числа
# разошлись, 3 — строка реестра без места, 2 — сверщик не отработал; всё это здесь красное.
OUTN=$(bash "$ROOT/scripts/docs-refresh-claims.sh" check --keys "$NARROW_KEYS" 2>&1); RCN=$?
[ "$RCN" -eq 0 ] || DIRTY="$DIRTY  реестр (--keys $NARROW_KEYS), код $RCN:"$'\n'"$(printf '%s\n' "$OUTN" | grep '^  · ' | head -8)"$'\n'
# Предфильтр (D1275): документ без единого совпадения выражений широкой поверхности `scan` судить нечем — на 10 ноября
# 2026 таких 214 из 218, а цикл порождал по ним около 2000 процессов (17 из 38 с CPU теста). Один `grep -l` по тем же
# выражениям по всему файлу — надмножество того, что видит `scan` (тот режет Roadmap), поэтому расхождение не теряется.
_WRE=""
for entry in "${PATTERNS[@]}"; do
    [ "${entry##*|}" = wide ] || continue
    entry="${entry%|*}"; _WRE="${_WRE:+$_WRE|}(${entry%|*})"
done
_HIT=()
if [ -n "$_WRE" ] && [ ${#WIDE_DOCS[@]} -gt 0 ]; then
    while IFS= read -r f; do _HIT+=("$f"); done < <(grep -lE -- "$_WRE" "${WIDE_DOCS[@]}" 2>/dev/null)
fi
SKIPPED_DERIVED=0
for f in ${_HIT[@]+"${_HIT[@]}"}; do
    [ -f "$f" ] || continue
    if is_stale_derived "$f"; then SKIPPED_DERIVED=$((SKIPPED_DERIVED + 1)); continue; fi
    OUT=$(scan "$f" wide) || DIRTY="$DIRTY$OUT"$'\n'
done
[ "$SKIPPED_DERIVED" -gt 0 ] && echo "  (пропущено отставших переводов: $SKIPPED_DERIVED — их правит пересборка, не генератор чисел)"
if [ -z "$DIRTY" ]; then ok
else bad "T1: дрейф производных чисел" $'\n'"$DIRTY  (правь генератором: scripts/count-stats.sh --patch-claude-md)"; fi

# --- T2: сам сканер ловит враньё (негативный контроль — детектор не завязан
#         только на успех) ---
FIX=$(mktemp)
echo "из них 9999 отказывают и 8888 спрашивают" > "$FIX"
if scan "$FIX" wide >/dev/null; then bad "T2" "фикстура с 9999 прошла широкую поверхность как чистая"
else ok; fi
rm -f "$FIX"
# T2b: узкая поверхность через реестр тоже ловит враньё — README с подложным числом хуков.
FX=$(mktemp -d); cp "$ROOT/README.md" "$FX/README.md"
sed -i.bak -E 's/^([0-9]+) hooks \(/9999 hooks (/' "$FX/README.md" && rm -f "$FX/README.md.bak"
if CLAUDSOUL_REPO="$FX" DOC_FIGURES="$ROOT/scripts/doc-figures.sh" DOC_CLAIMS_FILE="$ROOT/scripts/doc-claims.tsv" \
   bash "$ROOT/scripts/docs-refresh-claims.sh" check --keys hooks >/dev/null 2>&1; then bad "T2b" "реестр не заметил 9999 хуков в подложном README"
else ok; fi

echo "test_derived_counts_inventory: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
