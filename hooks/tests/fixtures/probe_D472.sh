#!/usr/bin/env bash
# СУДИТ: install.sh
# probe_D472.sh — «на что повлияет» на маршруте Bash приходит ПОСЛЕ записи, а не до.
#
# Предмет. `hooks/impact-inject.sh` объявляет своей задачей ответ ДО правки («потребитель
# карты — ты, когда редактируешь файл, ты смотришь на карту, что ещё зависит»). На маршруте
# инструмента (Edit|Write|MultiEdit) он и стоит на PreToolUse. На маршруте команды (Bash) —
# на PostToolUse, то есть говорит, когда python/sed уже переписал файл и решение принято.
#
# Проба судит РЕГИСТРАЦИЮ у её владельца — `install.sh` (ADR-009, владелец состава хуков),
# а не живой `~/.claude/settings.json`: настройка машины меняется руками и о договоре
# проекта не свидетельствует.
#
# Красная (код 1) = дефект жив: PreToolUse-регистрации с матчером Bash у хука нет.
# Зелёная (код 0) = ответ о влиянии приходит до записи и на маршруте команды.
# Код 2 = судить нечем (нет install.sh либо python3) — не путать с «дефекта нет».

set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$REPO" ] && [ -d "$REPO" ] || { echo "probe_D472: корень репозитория не определён" >&2; exit 2; }
INST="$REPO/install.sh"
[ -f "$INST" ] || { echo "probe_D472: нет install.sh — судить нечем" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "probe_D472: нет python3 — судить нечем" >&2; exit 2; }

# Положительный контроль рамки ПЕРЕД судом: хук в реестре вообще есть. Без него «не нашли
# PreToolUse-регистрацию» было бы неотличимо от «не нашли хука» — корень R6.
if ! grep -q 'impact-inject\.sh' "$INST"; then
    echo "probe_D472: РАМКА НЕ СОБРАЛАСЬ — impact-inject.sh не упомянут в install.sh" >&2
    exit 2
fi

OUT=$(python3 - "$INST" <<'PY'
import json, re, sys

text = open(sys.argv[1], encoding="utf-8").read()
# Регистрации лежат блоками JSON внутри установщика; берём каждый объект с "hooks".
found = []
for m in re.finditer(r'"(PreToolUse|PostToolUse|Stop|UserPromptSubmit|PreCompact|SessionStart)"', text):
    event = m.group(1)
    tail = text[m.end():m.end() + 4000]
    # матчер и команды ближайшего блока
    for g in re.finditer(r'"matcher"\s*:\s*"([^"]*)"(.*?)(?="matcher"|$)', tail, re.S):
        matcher, body = g.group(1), g.group(2)
        if "impact-inject.sh" in body:
            found.append((event, matcher))
for e, mt in sorted(set(found)):
    print(f"{e}\t{mt}")
PY
) || { echo "probe_D472: разбор install.sh не отработал" >&2; exit 2; }

[ -n "$OUT" ] || { echo "probe_D472: РАМКА НЕ СОБРАЛАСЬ — регистраций хука не найдено" >&2; exit 2; }

if grep -q '^PreToolUse	.*Bash' <<< "$OUT"; then
    exit 0
fi

echo "probe_D472: на маршруте Bash ответ о влиянии приходит ПОСЛЕ записи" >&2
echo "probe_D472: найденные регистрации impact-inject:" >&2
sed 's/^/  · /' <<< "$OUT" >&2
exit 1
