#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/write_targets.py
# probe_D1280 — цель, собранная из подстановки в обратных кавычках, режимом `--literal` литеральной не считается (откат
#   закрытого D1277, 42fc1b0d: заглушка `__subst__` спрятала знак подстановки, и `mkdir -p skills/`whoami`` дал литеральную
#   цель `skills/__subst__` — страж имени скилла отбивал её, нога F3 `test_skill_name_ascii_guard.sh`).
#   (п) `mkdir -p skills/`whoami`` — литеральных целей нет;
#   (к) `mkdir -p skills/plain` — литеральная цель есть (положительный контроль: режим отвечает «да»).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
W="$R/hooks/lib/write_targets.py"
[ -f "$W" ] && command -v python3 >/dev/null 2>&1 || exit 2
k=$(printf '%s' 'mkdir -p skills/plain' | python3 "$W" --literal 2>/dev/null)
[ "$k" = "skills/plain" ] || { echo "рамка: литеральная цель не отдана (k=$k)" >&2; exit 2; }
p=$(printf '%s' 'mkdir -p skills/`whoami`' | python3 "$W" --literal 2>/dev/null)
# (п2) полная выдача — её берёт страж имени скилла и судит имя своим признаком `not_literal` (знаки `*?[]${}` и обратная
#   кавычка): цель из подстановки обязана нести такой знак. Первая редакция починки чинила только режим `--literal`, и F3
#   оставалась красной при зелёной (п).
f=$(printf '%s' 'mkdir -p skills/`whoami`' | python3 "$W" 2>/dev/null)
miss=""
[ -z "$p" ] || miss="$miss (п) режим --literal отдал $p;"
case "$f" in *'*'*|*'?'*|*'['*|*']'*|*'$'*|*'{'*|*'}'*|*'`'*) ;; *) miss="$miss (п2) полная выдача без знака подстановки: $f;" ;; esac
[ -z "$miss" ] && { echo "цель из обратных кавычек литеральной не считается ни в одном режиме; литеральная — отдаётся"; exit 0; }
echo "цель из подстановки в обратных кавычках читается литеральной:$miss"
exit 1
