#!/usr/bin/env bash
# СУДИТ: scripts/behavior-condition-probe.sh
# СУД: только в рабочем дереве
# probe_D474 — «Проверка» закрытого D474 дословно: предмет разрешён у каждого свидетеля-атаки (`--unresolved` пуст), и
#   последний полный прогон прибора по ЭТОМУ дереву вынес вердикт каждому разрешимому (judged = resolved в журнале).
# Вынесена из текста пункта в пробу 15 ноября 2026 (скептик opus по D1295, M2): журнал ищется по пути рабочего дерева,
#   и в клоне коммита (`scripts/archive-checks-after-commit.sh`) строки нет по построению — красное без поломки на каждом
#   коммите, задевшем прибор (44 из 400). Маркер «только в рабочем дереве» выводит пробу из такого суда; судит её недельный
#   прогон архива в настоящем дереве. Её же зовёт «Проверка» D1295 (откат D474).
# Код: 0 — держится; 1 — есть неразрешённые, нет строки журнала или вердикт вынесен не всем; 2 — прибор не ответил.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
u=$(bash scripts/behavior-condition-probe.sh --unresolved) || exit 2
n=$(printf "%s" "$u" | grep -c . || true)
[ "$n" -eq 0 ] || exit 1
f="${STATE_DIR:-$HOME/.claude/hooks/state}/behavior-condition-probe.jsonl"
r="$(git rev-parse --show-toplevel 2>/dev/null)"
l=$(grep -F "\"repo\":\"$r\"" "$f" 2>/dev/null | tail -1)
[ -n "$l" ] || exit 1
j=$(sed -n "s/.*\"judged\":\([0-9]*\).*/\1/p" <<< "$l")
v=$(sed -n "s/.*\"resolved\":\([0-9]*\).*/\1/p" <<< "$l")
[ -n "$j" ] && [ "$j" = "$v" ]
