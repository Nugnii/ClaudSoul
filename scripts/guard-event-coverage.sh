#!/usr/bin/env bash
# guard-event-coverage.sh — страж, объявивший предметом правку файла, обязан видеть событие Bash.
#
# Результат: у каждого стража, чей предмет — запись в файл, событие покрывает ОБА пути правки
#            (инструмент Edit/Write и команда Bash), либо исключение записано в самом страже
# Проверка результата: bash scripts/guard-event-coverage.sh --check даёт 0, когда слепых нет
#
# Зачем (13 сентября 2026, D407). Замер: за сессию правлено 11 файлов кода, через хук карты
# прошло НОЛЬ — он висел на `Edit|Write|MultiEdit`, а все правки шли командой Bash. У
# `backlog-open-write-guard` (отказ уровня 4) срабатываний 0 при четырёх коммитах, тронувших
# BACKLOG.md. Знание об этом классе лежит с 27 августа
# (`case-2026-08-27-tool-name-detection-blind-to-work-mode`: правок оболочкой 1357 против
# 1675 файловыми, 45%), и девять стражей его не применили.
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ: ничем. `drift-check.sh` сверяет СОСТАВ регистрации (кто зарегистрирован),
# а не ПОКРЫТИЕ события предметом стража; `dep-index` рёбер «хук → событие» не держит вовсе.
# Карта связей их держит с сегодняшнего дня и читает ту же регистрацию, что и здесь.
#
# ПРЕДМЕТ ОПОЗНАЁТСЯ ПО ШАПКЕ стража: первые четыре строки говорят «правка», «запись» или
# «файл». НАЗВАННЫЙ ПРЕДЕЛ: страж, чья шапка молчит о предмете, здесь не судится вовсе —
# признак судит ОБЪЯВЛЕНИЕ, как и всюду, где отличить намерение автоматом нельзя.
# Условие снятия: у хука появится объявленное поле предмета, а не проза шапки.
#
# Исключение записывается В САМОМ СТРАЖЕ строкой `bash-путь: не нужен — <почему>` —
# наблюдаемое решение вместо умолчания.
set -uo pipefail
ROOT="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] && [ -f "$ROOT/install.sh" ] || { echo "guard-event-coverage: нет install.sh — не наш проект" >&2; exit 0; }

python3 - "$ROOT" <<'PY'
import re, os, sys
root = sys.argv[1]
txt = open(os.path.join(root, "install.sh"), errors="replace").read()
cur, matcher, reg = None, "", {}
EV = r'"(PreToolUse|PostToolUse|Stop|UserPromptSubmit|SessionStart|PreCompact|Notification|SubagentStop|SessionEnd)"\s*:'
for line in txt.split("\n"):
    e = re.search(EV, line)
    if e:
        cur, matcher = e.group(1), ""
        continue
    m = re.search(r'"matcher"\s*:\s*"([^"]*)"', line)
    if m:
        matcher = m.group(1)
        continue
    h = re.search(r'hooks/([a-z0-9_-]+\.sh)', line)
    if h and cur:
        reg.setdefault("hooks/" + h.group(1), []).append((cur, matcher))

# ПОКРЫТИЕ БЫВАЕТ НЕ ТОЛЬКО СВОЕЙ РЕГИСТРАЦИЕЙ (13 сентября 2026). Диспетчер
# `hooks/bash-write-dispatch.sh` подаёт стражам правку, сделанную командой, — такой страж
# слепым не является, хотя его собственная подписка не изменилась. Список берётся У
# ВЛАДЕЛЬЦА (строка `GUARDS=` диспетчера), а не переписывается здесь: копия правила у
# потребителя есть род K, и она разошлась бы молча.
dispatched = set()
disp = os.path.join(root, "hooks", "bash-write-dispatch.sh")
if os.path.exists(disp):
    m = re.search(r'^GUARDS="([^"]*)"', open(disp, errors="replace").read(), re.M)
    if m:
        dispatched = {"hooks/" + g for g in m.group(1).split()}

blind, judged = [], 0
for path, evs in sorted(reg.items()):
    full = os.path.join(root, path)
    if not os.path.exists(full):
        continue
    head = "".join(open(full, errors="replace").readlines()[:4])
    if not re.search(r"правк|запис|файл", head):
        continue
    body_all = open(full, errors="replace").read()
    # ПРЕДМЕТ ВИДЕН В КОДЕ, А НЕ ТОЛЬКО В ПРОЗЕ (13 сентября 2026). Страж, не читающий ни
    # пути файла, ни его тела, предметом «правка файла» не обладает, чем бы ни говорила
    # шапка. Замер: из девяти, отобранных прозой, путь или тело читают ВОСЕМЬ; девятый —
    # `budget-gate.sh`, у которого из входа берутся только `session_id` и `tool_name`
    # (`:36-37`), а вывод побайтово одинаков на чистом и на нарушающем файле. Прибор
    # числил его слепым ЛОЖНО: признак судил прозу, а не устройство.
    if not re.search(r"file_path|notebook_path|tool_input\.content|new_string", body_all):
        continue
    judged += 1
    if "bash-путь: не нужен" in body_all:
        continue
    sees_edit = any("Edit" in m or "Write" in m for _, m in evs)
    sees_bash = any("Bash" in m or m == "" for _, m in evs)
    if path in dispatched:
        continue
    if sees_edit and not sees_bash:
        blind.append((path, "; ".join(f"{e}[{m}]" for e, m in evs)))

print(f"стражей с предметом «правка файла»: {judged}; покрыто диспетчером: {len(dispatched)}; слепых к Bash: {len(blind)}")
for p, e in blind:
    print(f"  · {p} — {e}")
sys.exit(1 if blind else 0)
PY
