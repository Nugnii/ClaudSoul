#!/usr/bin/env bash
set -u
. "$(dirname "$0")/../alerts-read.sh"
# СУДИТ: hooks/completion-gate.sh
# probe_D1221 — состав дросселя гейта границы хода различает пункты любой нумерации, которую признаёт владелец признака
#   (`BACKLOG_ID_TOKEN_RE`), а не только D-номера. Рамка настоящая: гейт на фикстуре бэклога, одна сессия, два хода —
#   на первом назван пункт B541, на втором тем же каналом B542; второе сообщение обязано дойти до очереди. Каналы три:
#   «Проверка» открытого не красная, красная «Проверка» закрытого и «закрыт по форме» (номера через пробел). И D-номер:
#   состав непустой и несёт номер.
#   0 — оба канала доставили B542, состав D1196 несёт номер; 1 — сообщение о B542 погасло как повтор либо состав D1196
#   пуст; 2 — нет гейта либо контроль (B542 на чистом состоянии) не назван.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
G="$PWD/hooks/completion-gate.sh"
[ -f "$G" ] || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
gate() {  # <бэклог> <каталог состояния>
    printf '{"session_id":"probe-d1221","cwd":"/"}' | env -u BACKLOG_CHECKS_NESTED -u BACKLOG_CMD_RUNNING -u BACKLOG_CMD_DEPTH_MAX \
        CG_BACKLOG="$1" STATE_DIR="$2" bash "$G" >/dev/null 2>&1
}
item() {  # <метка> <номер> <команда> <файл>
    printf -- '- %s **%s** пункт пробы\n  **Результат.** проба\n  **Проверка.** `%s` → 0\n' "$1" "$2" "$3" > "$4"
}
bad=0
for ch in open closed; do
    case $ch in open) mk='☐'; c=true ;; closed) mk='☑'; c=false ;; esac
    mkdir -p "$W/$ch/s" "$W/$ch/c"
    item "$mk" B542 "$c" "$W/$ch/ctl.md"
    gate "$W/$ch/ctl.md" "$W/$ch/c"
    alerts_of "$W/$ch/c" | grep -q B542 || { echo "контроль $ch: гейт не назвал B542 на чистом состоянии"; exit 2; }
    item "$mk" B541 "$c" "$W/$ch/a.md"
    gate "$W/$ch/a.md" "$W/$ch/s"
    n=$(alerts_of "$W/$ch/s" | grep -c .)
    item "$mk" B542 "$c" "$W/$ch/b.md"
    gate "$W/$ch/b.md" "$W/$ch/s"
    alerts_of "$W/$ch/s" | tail -n +"$((n + 1))" | grep -q B542 \
        || { echo "канал $ch: сообщение о B542 погасло как повтор сообщения о B541"; bad=1; }
done
# Канал «закрыт по форме» (FORMBAD) собирается через пробел, а не строками (скептик opus по 1b597801, M1): первый
# бэклог — один ☑ B541 с меткой формы, второй — B541 и B542; сообщение о B542 обязано дойти.
form() {  # <файл> <номера…>
    local f="$1" x; shift; : > "$f"
    for x in "$@"; do printf -- '- ☑ **%s** закрыт по форме\n  **Результат.** проба\n  **Проверка.** `true` → 0\n  Метка: судит по форме\n\n' "$x" >> "$f"; done
}
mkdir -p "$W/form/s"
form "$W/form/a.md" B541
gate "$W/form/a.md" "$W/form/s"
alerts_of "$W/form/s" | grep -q B541 || { echo "контроль form: гейт не назвал B541 каналом формы"; exit 2; }
n=$(alerts_of "$W/form/s" | grep -c .)
form "$W/form/b.md" B541 B542
gate "$W/form/b.md" "$W/form/s"
alerts_of "$W/form/s" | tail -n +"$((n + 1))" | grep -q B542 \
    || { echo "канал form: сообщение о B542 погасло как повтор сообщения о B541"; bad=1; }
mkdir -p "$W/d/s"
item '☐' D1196 true "$W/d/a.md"
gate "$W/d/a.md" "$W/d/s"
grep -rqs '"key":"open-not-red:D1196' "$W/d/s" || { echo "состав сообщения о D1196 не несёт номера"; bad=1; }
exit "$bad"
