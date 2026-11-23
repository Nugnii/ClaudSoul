#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_hint_age_always_named.sh
# probe_D1353.sh — тест стартовой подсказки не пишет в файл сквозной линии каталога, из которого его запустили.
#
# Повод (21 ноября 2026, D1353). Тест звал hooks/session-start.sh с каталогом состояния во временной папке, а полем
# `cwd` отдавал `$PWD` — настоящий проект. Реестр сессий в песочнице пуст, поэтому сводка собиралась на каждом вызове
# и дописывалась в `<cwd>/.claude-docs/narrative.md`: 2541 запись-проба из 2566 записей рабочего файла ClaudSoul.
# Первая попытка пробы (22 ноября 2026) не умела сказать «да»: в пробном проекте сводка не собиралась вовсе, и «файла
# нет» ничего не доказывало. Поэтому сначала контроль — хук, позванный с пробным проектом, сводку в нём пишет; потом
# суд — тест, запущенный из того же проекта, её не пишет.
# Проверка результата: bash hooks/tests/fixtures/probe_D1353.sh → 0 — тест прошёл и файла сквозной линии в каталоге
#   запуска не оставил; 1 — оставил; 2 — не измерено (нет теста, хука, jq или git; хук сводку не пишет; тест красен).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="$REPO/hooks/tests/test_hint_age_always_named.sh"
H="$REPO/hooks/session-start.sh"
[ -f "$T" ] && [ -f "$H" ] && command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 \
    || { echo "нет теста, хука, jq или git — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
P="$W/proj"; N="$P/.claude-docs/narrative.md"
mkdir -p "$P" "$W/st"
printf '# Пробный проект\n' > "$P/CLAUDE.md"
# Сводке нужны две датированные записи журнала и история в окне: без них она молчит (narrative-compose-lib.sh).
printf '# Session Log\n## 2026-11-20 — первая\n- a\n## 2026-11-21 — вторая\n- b\n' > "$P/SESSION.md"
git -C "$P" init -q && git -C "$P" -c user.name=probe -c user.email=probe@example.com -c commit.gpgsign=false \
    commit -q --allow-empty -m 'feat: проба' || { echo "git не завёл пробный проект — не измерено"; exit 2; }

# Контроль «рамка умеет сказать да»: хук, позванный с этим каталогом, сводку в нём пишет.
printf '{"session_id":"probe-ctl","cwd":"%s"}' "$P" | STATE_DIR="$W/st" bash "$H" >/dev/null 2>&1
[ -s "$N" ] || { echo "хук сводку в пробном проекте не пишет — «файла нет» ничего не докажет; не измерено"; exit 2; }
rm -rf "$P/.claude-docs"

# Суд: тест, запущенный из пробного проекта.
( cd "$P" && bash "$T" ) >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] || { echo "тест красен (код $rc) — о записи судить нечем; не измерено"; exit 2; }
if [ -e "$N" ]; then
    echo "тест записал $(grep -c '^## ' "$N") сводок в файл сквозной линии каталога запуска"; exit 1
fi
echo "файл сквозной линии каталога запуска не тронут"
exit 0
