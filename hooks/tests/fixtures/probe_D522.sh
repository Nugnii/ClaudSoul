#!/usr/bin/env bash
# probe_D522 — страж замены «первое вхождение»: отказ на замене по образцу без проверки единственности
# образца и тишина на законной замене (с `count(...) == 1`). Исполняется из корня дерева (cwd).
# Код: 0 — страж есть и различает обе стороны; 1 — стража нет либо он не различает.
# Повод: ProjectA B272, 2026-10-10 — `assert o in s` + `s.replace(o, n, 1)` поставил правку в соседний
# обработчик onError, тесты были зелёными, дефект ушёл на прод (pattern-string-replace-must-prove-single-landing).
H=hooks/replace-uniqueness-guard.sh
[ -f "$H" ] || exit 1
# журнал срабатываний стража — в песочницу: проба исполняется еженедельной перепроверкой, живой state ей не предмет
STATE_DIR=$(mktemp -d) || exit 2; export STATE_DIR; trap 'rm -rf "$STATE_DIR"' EXIT
bad='{"tool_name":"Bash","tool_input":{"command":"python3 - <<EOF\ns=open(p).read()\nassert o in s\ns=s.replace(o,n,1)\nEOF"}}'
good='{"tool_name":"Bash","tool_input":{"command":"python3 - <<EOF\ns=open(p).read()\nassert s.count(o)==1\ns=s.replace(o,n,1)\nEOF"}}'
printf '%s' "$bad" | bash "$H" 2>/dev/null | grep -q '"deny"' || exit 1
if printf '%s' "$good" | bash "$H" 2>/dev/null | grep -q '"deny"'; then exit 1; fi
exit 0
