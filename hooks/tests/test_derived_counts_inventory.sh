#!/usr/bin/env bash
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
PATTERNS=(
    '[0-9]+ active hooks|hooks|narrow'
    '[0-9]+ активн(ый|ых) хук(а|ов)?|hooks|narrow'
    '[0-9]+ библиотек|libs|narrow'
    '[0-9]+ файл(а|ов)? тестов хуков|hook_test_files|narrow'
    '[0-9]+ skills|skills|narrow'
    '[0-9]+ скилл(а|ов)?|skills|narrow'
    '[0-9]+ хуков всего|hooks|narrow'
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
    git -C "$ROOT" ls-files '*.md' 2>/dev/null | grep -vE '_drafts/|^knowledge/|(^|/)(CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG|BACKLOG-archive)\.md$|-20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.md$'
)

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
for f in "${NARROW_DOCS[@]}"; do
    [ -f "$f" ] || continue
    OUT=$(scan "$f" narrow) || DIRTY="$DIRTY$OUT"$'\n'
done
for f in "${WIDE_DOCS[@]}"; do
    [ -f "$f" ] || continue
    OUT=$(scan "$f" wide) || DIRTY="$DIRTY$OUT"$'\n'
done
if [ -z "$DIRTY" ]; then ok
else bad "T1: дрейф производных чисел" $'\n'"$DIRTY  (правь генератором: scripts/count-stats.sh --patch-claude-md)"; fi

# --- T2: сам сканер ловит враньё (негативный контроль — детектор не завязан
#         только на успех) ---
FIX=$(mktemp)
echo "здесь 9999 активных хуков и 21 скилл" > "$FIX"
if scan "$FIX" narrow >/dev/null; then bad "T2" "фикстура с 9999 прошла как чистая"
else ok; fi
rm -f "$FIX"

echo "test_derived_counts_inventory: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
