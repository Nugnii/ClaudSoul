#!/usr/bin/env bash
# test_adv5_partial_section_success.sh — заменена одна секция из двух: генератор
# отдаёт 0 и печатает число строк, которых в файле нет.
#
# scripts/regen-readme-skills.sh:227-230 после прошлого раунда проверяет «REPLACED == 0».
# Порог поставлен на ноль, а секций две. При REPLACED == 1 условие не выполняется, и:
#   • exit 0;
#   • итоговая строка печатает «N skills, M hooks» — числа считаются по временным файлам
#     $SKILLS_ROWS/$HOOKS_ROWS (строки 156, 219), то есть по СОБРАННОМУ, а не по
#     попавшему в файл. Ровно то основание, по которому строку 227 и добавляли:
#     «числа ниже считаются по временным файлам строк, а не по попавшему в целевой файл».
#     Для второй секции оговорка осталась в силе, и число врёт.
#
# Достижимость. Вызывающий один — install.sh:181:
#     if README_FILE="…/README.ru.md" bash "$REGEN_SCRIPT" "$CLAUDSOUL_DIR" >/dev/null; then
#         info "README.ru.md: таблица скиллов регенерирована"
# stdout заглушён, судится ровно код возврата. Установщик скажет «регенерирована»,
# а таблица хуков останется прежней навсегда — и в следующий раз тоже, потому что
# каждый запуск даёт тот же зелёный ответ.
#
# Вход достижим без экзотики: любая правка README, где одна пара маркеров сломана
# (переименована, задвоена, отредактирована в редакторе с автопереносом) — вторая пара
# продолжает работать и прикрывает первую.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GEN="$REPO/scripts/regen-readme-skills.sh"
rc_test=0

T="$(mktemp -d)"
mkdir -p "$T/hooks" "$T/skills/dummy"
printf -- '---\nname: dummy\ndescription: заглушка для генератора.\n---\n' > "$T/skills/dummy/SKILL.md"
printf '#!/bin/bash\n# live-hook.sh — PreToolUse: делает нечто полезное и объяснимое.\necho\n' > "$T/hooks/live-hook.sh"

# В README есть пара SKILLS и НЕТ пары HOOKS.
cat > "$T/README.ru.md" <<'MDEOF'
# Справочник

<!-- SKILLS-TABLE:START -->
<!-- SKILLS-TABLE:END -->

## Хуки

| Хук | Что делает |
|-----|-----------|
| `устаревшая-запись` | таблица без маркеров, обновить её некому |
MDEOF

gen_out="$(README_FILE="$T/README.ru.md" bash "$GEN" "$T" 2>&1)"; gen_rc=$?
echo "генератор: rc=$gen_rc"
printf '%s\n' "$gen_out" | sed 's|^|  |'

landed=$(grep -c '^| `live-hook`' "$T/README.ru.md" || true)
stale=$(grep -c 'устаревшая-запись' "$T/README.ru.md" || true)
echo "строк хука в файле: $landed ; прежняя запись на месте: $stale"

# 1. Код возврата обязан отличать «сделано целиком» от «сделана половина».
if [ "$gen_rc" -eq 0 ] && [ "$landed" -eq 0 ]; then
    echo "FAIL [A7a]: rc=0, но в целевой файл не уехало ни одной строки хуков."
    echo "  install.sh:181 судит ровно по коду и напечатает «регенерирована»."
    rc_test=1
else
    echo "PASS [A7a]: код возврата отражает неполную замену"
fi

# 2. Отчёт обязан считать попавшее, а не собранное.
case "$gen_out" in
    *"1 hooks"*)
        echo "FAIL [A7b]: отчёт заявляет «1 hooks», хотя в файле $landed строк хуков."
        rc_test=1 ;;
    *) echo "PASS [A7b]: отчёт не заявляет несуществующих строк" ;;
esac

echo ""
if [ "$rc_test" -ne 0 ]; then
    echo "adv5 partial-section-success: КРАСНЫЙ — порог отказа поставлен на ноль замен,"
    echo "  а секций две; половина работы отчитывается как целая."
fi
exit "$rc_test"
