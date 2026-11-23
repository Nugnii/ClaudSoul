#!/usr/bin/env bash
set -u
# СУДИТ: scripts/named-limits.py scripts/behavior-condition-probe.sh
# probe_D1258 — у прибора свидетелей-атак не стоит названный предел, чьё условие снятия уже наступило: замер
#   `python3 scripts/named-limits.py --check` не называет `scripts/behavior-condition-probe.sh` среди пределов с
#   наступившим условием; положительный контроль — тот же замер называет предел, если вернуть его текст в копию прибора.
# Предмет — пара (D1295, 15 ноября 2026): утверждение об ОТСУТСТВИИ предела в тексте прибора выхолащиванием одного прибора
#   выполняется даром (заглушка пределов не несёт), и проба была зелена на мёртвом предмете; краснеть обязана от потери судьи.
# Дерево замера называется ему явно: `named-limits.py` берёт корень из `CLAUDSOUL_REPO`, и унаследованная переменная
#   (рамка прибора свидетелей, сверка архива по копии) уводила контроль из клона в дерево вызывающего — контроль краснел.
# Код: 0 — так; 1 — нет (названо); 2 — нет предмета или замер не ответил.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/named-limits.py" ] && [ -f "$R/scripts/behavior-condition-probe.sh" ] || exit 2
command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
nl() { (cd "$1" && CLAUDSOUL_REPO="$1" python3 scripts/named-limits.py --check 2>&1); }
out=$(nl "$R")
grep -q 'проверка не отработала: 0' <<< "$out" || { echo "рамка: замер пределов не ответил"; exit 2; }
miss=""
grep -q '· scripts/behavior-condition-probe.sh:' <<< "$out" && miss="$miss предел прибора с наступившим условием стоит;"
# Контроль: в клоне в шапку прибора возвращён прежний предел — замер обязан его назвать.
C="$W/repo"; git clone -q --local "$R" "$C" 2>/dev/null || exit 2
cp "$R/scripts/behavior-condition-probe.sh" "$C/scripts/" && cp "$R/scripts/named-limits.py" "$C/scripts/" || exit 2
{ sed -n 1p "$C/scripts/behavior-condition-probe.sh"
  printf '%s\n' '# НАЗВАННЫЙ ПРЕДЕЛ: однозначен предмет не у всех свидетелей (контроль probe_D1258).' \
      '# Условие снятия: у свидетеля появится объявленный предмет строкой шапки.' \
      '# Проверка снятия: `_n=$(bash scripts/behavior-condition-probe.sh --unresolved | wc -l) && test "$_n" -eq 0`'
  sed 1d "$C/scripts/behavior-condition-probe.sh"; } > "$W/b" && cp "$W/b" "$C/scripts/behavior-condition-probe.sh"
grep -q '· scripts/behavior-condition-probe.sh:' <<< "$(nl "$C")" || miss="$miss контроль: возвращённый предел замер не назвал;"
[ -z "$miss" ] && { echo "предела с наступившим условием у прибора нет; возвращённый — назван"; exit 0; }
echo "не держится:$miss"
exit 1
