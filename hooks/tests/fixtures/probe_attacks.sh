#!/usr/bin/env bash
# СУДИТ: hooks/tests/fixtures/adversary-recall/2026-11-18-triage.tsv
# probe_attacks.sh <D-номер> — тесты атак критиков, отнесённые разбором D1325 к пункту, зелёны на нынешнем дереве.
#
# Проверка результата: bash hooks/tests/fixtures/probe_attacks.sh D<N> → 0 — все атаки пункта зелёны; 1 — есть
#   красная (печатается ПЕРВАЯ, дальше не идёт: у открытого пункта ответ нужен быстро); 2 — не измерено (нет таблицы
#   разбора, нет архива атак, у пункта нет строк, нет git/tar).
# Атаки — архивы вне репозитория (`.claude-docs/adversary-recall/2026-11-18-attacks*.tar.gz`, каталог закрыт
# .gitignore: в тестах абсолютные пути машины). Судится РАБОЧЕЕ дерево: отслеживаемые файлы копируются во временный
# каталог, тесты случая кладутся поверх, HOME — песочница. Строка разбора: `<случай>/<тест>` ⇥ исход ⇥ …
# Предел: на машине без архива проба отвечает 2 — пункт там не проверяется.
# Условие снятия: тесты атак очищены от путей машины и лежат в репозитории.
set -uo pipefail
ID="${1:-}"
[ -n "$ID" ] || { echo "нужен номер пункта — не измерено"; exit 2; }
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TRI="$REPO/hooks/tests/fixtures/adversary-recall/2026-11-18-triage.tsv"
ARC="$REPO/.claude-docs/adversary-recall"
[ -f "$TRI" ] || { echo "нет таблицы разбора — не измерено"; exit 2; }
command -v git >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || { echo "нет git или tar — не измерено"; exit 2; }
KEYS=$(awk -F'\t' -v id="$ID" '!/^#/ && $2 == id { print $1 }' "$TRI")
[ -n "$KEYS" ] || { echo "у $ID нет строк в таблице разбора — не измерено"; exit 2; }
W=$(mktemp -d) || { echo "нет временного каталога — не измерено"; exit 2; }
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/tree" "$W/att" "$W/home"
( cd "$REPO" && git ls-files -z | tar --null -T - -cf - 2>/dev/null ) | tar -xf - -C "$W/tree" 2>/dev/null
[ -d "$W/tree/hooks" ] || { echo "копия дерева не собрана — не измерено"; exit 2; }

n=0
while IFS= read -r key; do
    case_="${key%%/*}"; test_="${key#*/}"; dir="${case_%-base}"
    case "$case_" in
        *-base) a="$ARC/2026-11-18-attacks-3.tar.gz" ;;
        D1207|D1213|D1223|D1259|D1268|D1286|D1288|D1307) a="$ARC/2026-11-18-attacks-2.tar.gz" ;;
        *) a="$ARC/2026-11-18-attacks.tar.gz" ;;
    esac
    [ -f "$a" ] || { echo "нет архива атак $(basename "$a") — не измерено"; exit 2; }
    if [ ! -d "$W/att/$case_" ]; then
        mkdir -p "$W/att/$case_"
        tar -xzf "$a" -C "$W/att/$case_" "$dir" 2>/dev/null || { echo "случай $case_ не распакован — не измерено"; exit 2; }
    fi
    # Тесты случая кладутся в дерево ПЕРЕД КАЖДЫМ прогоном: у разных случаев есть одноимённые тесты с разным
    # содержимым, и без этого исход зависел бы от порядка строк таблицы (скептик D1325, L2).
    cp -R "$W/att/$case_/$dir/." "$W/tree/" || { echo "тесты $case_ не положены в дерево — не измерено"; exit 2; }
    f=$(cd "$W/att/$case_/$dir" && find . -name "$test_" -type f | head -1)
    [ -n "$f" ] || { echo "теста $key нет в архиве — не измерено"; exit 2; }
    n=$((n + 1))
    out=$(HOME="$W/home" perl -e 'alarm 90; exec @ARGV' bash "$W/tree/$f" 2>&1)
    rc=$?
    # Тест, ответивший SKIP с кодом 0 (нет предмета, jq, python3), атаку не исполнил: это «не измерено», а не зелёный.
    case "$rc:$out" in 0:SKIP*|0:*$'\n'SKIP*) echo "атака $key пропущена тестом (SKIP) — не измерено"; exit 2 ;; esac
    [ "$rc" -eq 0 ] || { echo "красная атака $key (код $rc), проверено $n"; exit 1; }
done <<EOF
$KEYS
EOF
echo "атаки $ID зелёны: $n"
exit 0
