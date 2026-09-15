#!/usr/bin/env bash
# test_signal_twin_parity.sh — свидетель прибора scripts/signal-twin-parity.sh.
# Предмет: прибор КРАСНЕЕТ на знании, чей признак не видит путь в теле heredoc, и МОЛЧИТ там,
# где видит; сломанный разбор признаков он называет отказом, а не чистотой.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$REPO/scripts/signal-twin-parity.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

[ -f "$PROBE" ] || { echo "FAIL: нет $PROBE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Фикстуры пишутся построчно printf: вложенный питон здесь однажды умер на тройных кавычках,
# а литерал дефекта отбивает живой блокер переносимости.
mk() {  # mk <файл> <предикат пути: body|command>
    local f="$1" kind="$2"
    mkdir -p "$(dirname "$f")"
    {
        printf -- '---\nname: proba\nblocker: true\ndetection_signals: |\n'
        printf '  [\n    {\n      "name": "proba_signal",\n      "all_of": [\n'
        printf '        { "tool_matches": ["Bash"] },\n'
        if [ "$kind" = "body" ]; then
            printf '        { "heredoc_body_regex": "(hooks|scripts)/[^ ]*[.](sh|bash)" },\n'
            printf '        { "heredoc_body_regex": "grep -oE" }\n'
        else
            printf '        { "command_regex": "(hooks|scripts)/[^ ]*[.](sh|bash)" },\n'
            printf '        { "command_regex": "grep -oE" }\n'
        fi
        printf '      ],\n      "remedy": "proba"\n    }\n  ]\n'
        printf -- '---\n\nproba\n'
    } > "$f"
}

# T1 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ: признак читает ТЕЛО heredoc → запись опознана, прибор молчит.
mk "$TMP/vidit.md" body
O1=$(TWIN_KNOWLEDGE="$TMP/vidit.md" bash "$PROBE" 2>&1); RC1=$?
[ "$RC1" = 0 ] && ok || bad T1 "на знании, видящем тело, код $RC1: $O1"
grep -q "proba_signal" <<< "$O1" && ok || bad T1b "не назван сработавший признак: $O1"

# T2 — ДЫРА: признак судит команду БЕЗ тела heredoc → запись невидима, прибор краснеет.
# Это ровно устройство живого признака, из-за которого 57 записей из 77 проходят мимо.
mk "$TMP/slep.md" command
O2=$(TWIN_KNOWLEDGE="$TMP/slep.md" bash "$PROBE" 2>&1); RC2=$?
[ "$RC2" = 1 ] && ok || bad T2 "слепое знание дало код $RC2, ожидался 1: $O2"
grep -q "НЕ ОПОЗНАНА" <<< "$O2" && ok || bad T2b "дыра не названа словами: $O2"

# T3 — ОТКАЗ РАЗБОРА ≠ ЧИСТОТА. Сломанный JSON признаков молчит так же, как исправный на
# чистом входе: без этой ноги прибор зеленел бы на мёртвом знании (поймано на себе —
# кавычка внутри строки убила разбор всего блока 14 сентября 2026).
printf -- '---\nname: proba\nblocker: true\ndetection_signals: |\n  [ { "name": "bad", \n---\n' > "$TMP/broken.md"
O3=$(TWIN_KNOWLEDGE="$TMP/broken.md" bash "$PROBE" 2>&1); RC3=$?
[ "$RC3" = 2 ] && ok || bad T3 "сломанный разбор дал код $RC3, ожидался 2: $O3"
grep -q "BROKEN" <<< "$O3" && ok || bad T3b "отказ прибора не назван словом BROKEN"

# T4 — НЕТ ЗНАНИЯ — тоже отказ прибора, а не «дыр нет».
O4=$(TWIN_KNOWLEDGE="$TMP/net-takogo.md" bash "$PROBE" 2>&1); RC4=$?
[ "$RC4" = 2 ] && ok || bad T4 "отсутствие знания дало код $RC4, ожидался 2"

echo "test_signal_twin_parity: passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
