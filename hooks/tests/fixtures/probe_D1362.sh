#!/usr/bin/env bash
# СУДИТ: scripts/publish/forbidden.txt
# probe_D1362.sh — адрес домашнего сервера владельца в сети Tailscale не едет в открытый снимок.
#
# Повод (23 ноября 2026, D1362). Тест замера подавал `DOCKER_HOST` с настоящим адресом Tailscale домашнего сервера;
# файл публикуется, `redact.sed` строку не меняет, `forbidden.txt` такой формы не знал — гейт публикации пропустил бы
# её. Здесь две стороны: дерево вне `scripts/publish/` адресов сети Tailscale (100.64/10) не несёт, и перечень
# гейта, прочитанный так, как его читает гейт (`publish-public.sh`: срез по `#`, обрезка пробелов, `grep -aE` с учётом
# регистра), ловит адрес этой сети. Образец собирается на лету: литерал адреса в этом файле сам уронил бы гейт.
# Проверка результата: bash hooks/tests/fixtures/probe_D1362.sh → 0 — дерево чисто и перечень ловит образцы;
#   1 — в дереве есть такой адрес либо перечень пропускает образец; 2 — не измерено (нет git, перечня или дерева).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
F="$REPO/scripts/publish/forbidden.txt"
command -v git >/dev/null 2>&1 && [ -f "$F" ] && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
    || { echo "нет git, перечня гейта или дерева — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# Перечень так, как его читает гейт.
while IFS= read -r pat; do
    pat="${pat%%#*}"; pat="$(printf '%s' "$pat" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
    [ -n "$pat" ] && printf '%s\n' "$pat"
done < "$F" > "$W/pats"
[ -s "$W/pats" ] || { echo "перечень гейта пуст — не измерено"; exit 2; }
RC=0
# Сторона 1: перечень ловит адрес сети Tailscale — края диапазона и середину, в строке команды и в прозе.
for b in 64 101 127; do
    s="DOCKER_HOST=\"ssh://user@100.$b.7.33\" и узел 100.$b.250.1"
    printf '%s\n' "$s" | LC_ALL=C grep -qaE -f "$W/pats" || { echo "перечень гейта пропускает адрес 100.$b.x.x"; RC=1; }
done
# Отрицательный контроль: соседние сети не Tailscale — перечень их не трогает (иначе он ловил бы и версии вида 100.1.2.3).
for b in 63 128; do
    printf '%s\n' "узел 100.$b.7.33" | LC_ALL=C grep -qaE -f "$W/pats" && { echo "перечень ловит 100.$b.x.x — не сеть Tailscale"; RC=1; }
done
# Сторона 2: дерево вне конфига публикации адресов этой сети не несёт (форма, а не одно значение).
FORM='(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'
HITS=$(git -C "$REPO" grep -n -I -E "$FORM" -- . ':!scripts/publish/' 2>/dev/null)
[ -z "$HITS" ] || { echo "в дереве адрес сети Tailscale:"; printf '%s\n' "$HITS" | cut -d: -f1,2; RC=1; }
[ "$RC" = 0 ] && echo "дерево чисто, перечень гейта ловит адрес сети Tailscale"
exit "$RC"
