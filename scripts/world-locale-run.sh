#!/usr/bin/env bash
# world-locale-run.sh — исполнить команду в окружении хука терминальной сессии: LANG=ru_RU.UTF-8 плюс закрепление
# локали из env настроек Claude Code (`lib/env-pin.jq`, D1176). С `--bare` первым аргументом — то же окружение
# терминала БЕЗ закрепления (положительный контроль: так хуки шли до D1176).
# Результат: команда идёт в той локали, в какой её исполнил бы хук терминального `claude`; код — её код
# Проверка результата: bash hooks/tests/test_world_locale_run.sh даёт 0
#
# Коды самого скрипта: 2 — судить нечем (ru_RU.UTF-8 на машине не живая, нет jq, нет команды);
# 1 — мир не тот, о котором спрашивают: нет настроек, они не один JSON-объект, в env нет закрепления
# либо его перекрывает LC_ALL. Иначе — код команды. Для `--bare` мир не сверяется. Читается только
# `~/.claude/settings.json`: слои проекта (`.claude/settings.json`, `settings.local.json`) и управляемые
# настройки — названный предел. Имена закреплённых ключей — у программы (режим keys), своего перечня нет.
# Локаль живая, если без закрепления awk читает «1.5» как 1 и равняет «☐» и «◐»: на машине без ru_RU обе
# операции идут как под C, и прогон «под ru_RU» был бы прогоном под C с чужим именем.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
J="$R/lib/env-pin.jq"
S="$HOME/.claude/settings.json"
BARE=0; [ "${1:-}" = "--bare" ] && { BARE=1; shift; }
[ "$#" -gt 0 ] || { echo "world-locale-run: нужна команда" >&2; exit 2; }
[ -f "$J" ] || { echo "world-locale-run: нет lib/env-pin.jq" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "world-locale-run: нет jq — НЕ ИЗМЕРЕНО" >&2; exit 2; }
UNSET=(-u LC_ALL)
while IFS= read -r k; do [ -n "$k" ] && UNSET+=(-u "$k"); done < <(echo null | jq -r --arg mode keys -f "$J")
[ "${#UNSET[@]}" -gt 2 ] || { echo "world-locale-run: программа не назвала ключей" >&2; exit 2; }
AWK=/usr/bin/awk; [ -x "$AWK" ] || AWK=$(command -v awk) || exit 2
_bare=$(printf '1.5\n' | env "${UNSET[@]}" LANG=ru_RU.UTF-8 "$AWK" '{ printf "%d %d", $1 * 2, ("☐" == "◐") }')
[ "$_bare" = "2 1" ] || { echo "world-locale-run: ru_RU.UTF-8 не живая (awk без закрепления: «${_bare}») — НЕ ИЗМЕРЕНО" >&2; exit 2; }
[ "$BARE" -eq 1 ] && exec env "${UNSET[@]}" LANG=ru_RU.UTF-8 "$@"
[ -f "$S" ] || { echo "world-locale-run: нет $S — env Claude Code без закрепления" >&2; exit 1; }
[ "$(jq -s 'length == 1 and (.[0] | type) == "object"' "$S" 2>/dev/null)" = true ] \
    || { echo "world-locale-run: $S не один JSON-объект — Claude Code env из него не возьмёт" >&2; exit 1; }
[ "$(jq -c --arg mode set -f "$J" "$S" 2>/dev/null | jq -c '.env')" = "$(jq -c '.env' "$S")" ] \
    || { echo "world-locale-run: env настроек без закрепления: $(jq -c '.env' "$S")" >&2; exit 1; }
# LC_ALL в env настроек перекрывает обе категории — закрепление в мире не действует (M3 второго круга).
# LC_ALL вызывающего снимается намеренно: окружение хука даёт Claude Code, а не эта оболочка.
[ -z "$(jq -r '.env.LC_ALL // empty' "$S")" ] \
    || { echo "world-locale-run: LC_ALL=$(jq -r '.env.LC_ALL' "$S") в env настроек перекрывает закрепление" >&2; exit 1; }
PIN=()
while IFS= read -r k; do PIN+=("$k=$(jq -r --arg k "$k" '.env[$k]' "$S")"); done < <(echo null | jq -r --arg mode keys -f "$J")
exec env "${UNSET[@]}" LANG=ru_RU.UTF-8 "${PIN[@]}" "$@"
