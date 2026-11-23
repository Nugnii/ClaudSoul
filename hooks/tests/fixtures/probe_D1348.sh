#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_project_graph.sh
# probe_D1348.sh — свидетель карты связей зелёный и на машине БЕЗ установки ClaudSoul в домашней папке.
#
# Повод (21 ноября 2026, прогон CI 44893864632 по 44c93e3e). Песочница теста копирует один прибор карты; библиотеку
# разбора команд (`hooks/lib/write_targets.py`) прибор находит по указателю `~/.claude/claudsoul-repo` либо в
# установке `~/.claude/hooks/lib`. У автора оба есть, на раннере CI — ни одного: прибор откатывается на прежнее
# правило, ноги T12b и T12c красны. Полный набор у автора при этом 689 из 689.
# Проверка результата: bash hooks/tests/fixtures/probe_D1348.sh → 0 — тест зелёный с пустой домашней папкой;
#   1 — красный; 2 — не измерено (нет теста, либо положительный контроль не сошёлся: с указателем на репозиторий в той
#   же пустой папке тест обязан быть зелёным — иначе рамка не отличает отсутствие установки от поломки).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
T="hooks/tests/test_project_graph.sh"
[ -f "$REPO/$T" ] || { echo "нет теста — не измерено"; exit 2; }
H=$(mktemp -d) || exit 2
trap 'rm -rf "$H"' EXIT
mkdir -p "$H/bare" "$H/pointed/.claude"
printf '%s\n' "$REPO" > "$H/pointed/.claude/claudsoul-repo"
frame() {   # <домашняя папка> → код теста без адреса ClaudSoul в окружении
    ( cd "$REPO" && env -u CLAUDSOUL_ROOT -u CLAUDSOUL_REPO HOME="$1" bash "$T" >/dev/null 2>&1 )
}
frame "$H/pointed" || { echo "контроль: с указателем на репозиторий $T красен — не измерено"; exit 2; }
if frame "$H/bare"; then
    echo "свидетель карты зелёный и без установки в домашней папке"
    exit 0
fi
echo "без установки в домашней папке красен: ${T##*/}"
exit 1
