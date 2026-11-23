#!/usr/bin/env bash
# test_adversary_d509r2_nul_in_command_heredoc_views.sh
#
# АТАКА (D509, противник, раунд 2) и ВЕРДИКТ «не дефект»: байт NUL (`\u0000`) в `.command`
# вызова Bash. Прежняя редакция кормила awk видов `targets` и `hbody_raw` прямо из
# `jq -r '.command'`, и решение зависело от ПЛАТФОРМЫ: BSD awk (macOS) обрезал строку на NUL,
# gawk — нет. Новая строит эти виды из вида `cmd`, то есть из подстановки, где NUL вырезан,
# и отвечает одинаково на любом awk — так, как прежняя отвечала на Linux.
# Эталоном прежнее поведение здесь быть не может: у него два ответа. Такую команду Claude Code
# и не исполнит (Node отвергает NUL в аргументах запуска, ERR_INVALID_ARG_VALUE).
# Тест ЗАКРЕПЛЯЕТ поведение: NUL снят до разбора видов, текст справа от него приклеен — и это
# одинаково на macOS и на Linux. Закрытие находки зелёным тестом — правило /adversary Step 3.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$REPO/hooks/detection-signals-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

FAIL=0

# run <функция> <аргументы…> → "rc=N|вывод"
run() {
    bash -c '. "$1"; shift; out=$("$@" 2>/dev/null); printf "rc=%s|%s" "$?" "$out"' _ "$LIB" "$@"
}

check() { # $1=метка $2=ожидание $3=факт
    if [ "$2" = "$3" ]; then
        echo "ok   $1: $3"
    else
        echo "FAIL $1: ждали [$(printf '%q' "$2")], получили [$(printf '%q' "$3")]"
        FAIL=1
    fi
}

# Положительный контроль: без NUL цель и тело видны.
check "контроль: цель без NUL" "rc=0|" \
    "$(run ds_evaluate_node '{"heredoc_target_regex":"hooks/"}' Bash '{"command":"cat > hooks/a.sh <<EOF\nbody\nEOF"}' "")"
check "контроль: тело без NUL" "rc=0|" \
    "$(run ds_evaluate_node '{"heredoc_body_regex":"date -j"}' Bash '{"command":"cat > hooks/x.sh <<EOF\ndate -j\nEOF"}' "")"
# Отрицательный контроль: склейка не выдумывает того, чего в команде нет.
check "контроль: чужой образец за NUL" "rc=1|" \
    "$(run ds_evaluate_node '{"heredoc_target_regex":"scripts/"}' Bash '{"command":"cat > /tmp/x\u0000hooks/a.sh <<EOF\nbody\nEOF"}' "")"

while IFS='|' read -r label node ti; do
    [ -n "$label" ] || continue
    check "NUL снят, текст справа приклеен: $label" "rc=0|" "$(run ds_evaluate_node "$node" Bash "$ti" "")"
done <<'EOF'
цель за NUL|{"heredoc_target_regex":"hooks/"}|{"command":"cat > /tmp/x\u0000hooks/a.sh <<EOF\nbody\nEOF"}
хвост цели за NUL|{"heredoc_target_regex":"junk"}|{"command":"cat > hooks/x.sh\u0000junk <<EOF\nbody\nEOF"}
тело за NUL|{"heredoc_body_regex":"date -j"}|{"command":"cat > hooks/x.sh <<EOF\nfoo\u0000date -j\nEOF"}
EOF

[ "$FAIL" -eq 0 ] && echo "PASS"
exit $(( FAIL != 0 ))
