#!/usr/bin/env bash
# СУДИТ: scripts/publish-public.sh scripts/publish/forbidden.txt
# probe_D1365.sh — гейт истории открытого репозитория не считает секретом хвост обычного слова.
#
# Повод (23 ноября 2026, D1365). Публикация 1.37.2 остановилась на гейте истории: шаблон `sk-[A-Za-z0-9_-]{16,}`
# совпал с хвостом имени знания `…background-task-invisible-to-owner`. Разрешающий перечень гейта форму
# `[Bb]ackground-task` знал, но `history_forbidden_tokens` сверяет его с вырезанным совпадением — хвостом от «sk» до
# конца имени, где этого контекста уже нет. На такой находке публикатор предлагает удалить и пересоздать открытый
# репозиторий.
# Функция и перечень берутся из самого публикатора (как в `hooks/tests/test_publish_history_gate.sh`), шаблоны — из
# `scripts/publish/forbidden.txt`. Две стороны: имя знания находкой не становится; ключ формы `sk-…` в истории — находка.
# Проверка результата: bash hooks/tests/fixtures/probe_D1365.sh → 0 — обе стороны верны; 1 — имя знания найдено как
#   секрет либо ключ пропущен; 2 — не измерено (нет git, публикатора, перечня или функции).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
P="$REPO/scripts/publish-public.sh"; F="$REPO/scripts/publish/forbidden.txt"
command -v git >/dev/null 2>&1 && [ -f "$P" ] && [ -f "$F" ] || { echo "нет git, публикатора или перечня — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
{ awk '/^TOKEN_ALLOW=/' "$P"; awk '/^history_forbidden_tokens\(\) \{/,/^\}/' "$P"; } > "$W/fn.sh"
grep -q '^TOKEN_ALLOW=' "$W/fn.sh" && grep -q '^history_forbidden_tokens()' "$W/fn.sh" \
    || { echo "функция гейта истории или перечень не вырезаны — не измерено"; exit 2; }
# shellcheck source=/dev/null
. "$W/fn.sh"
mk() { mkdir -p "$1" && git -C "$1" init -q && printf '%s\n' "$2" > "$1/f.txt" && git -C "$1" add -A \
    && git -C "$1" -c user.name=p -c user.email=p@example.com -c commit.gpgsign=false commit -qm x; }
mk "$W/a" 'см. case-2026-09-10-background-task-invisible-to-owner' >/dev/null 2>&1 || { echo "песочница не собрана — не измерено"; exit 2; }
# Ключ собирается при прогоне: литералом в исходнике он ронял бы гейт снимка.
mk "$W/b" "OPENAI_API_KEY=\"sk""-proj9aB3dE7fG1hJ5kL2mN8\"" >/dev/null 2>&1 || { echo "песочница не собрана — не измерено"; exit 2; }
RC=0
got=$(history_forbidden_tokens "$W/a" "$F")
case "$got" in *sk-*) echo "гейт истории считает секретом хвост имени знания: [$got]"; RC=1 ;; esac
got=$(history_forbidden_tokens "$W/b" "$F")
case "$got" in *sk-*) ;; *) echo "контроль: ключ формы sk-… в истории не найден: [$got]"; RC=1 ;; esac
[ "$RC" = 0 ] && echo "гейт истории: имя знания не секрет, ключ — находка"
exit "$RC"
