#!/usr/bin/env bash
# АТАКА: хук объявлен на четырёх событиях, зарегистрирован на одном — пара молчит.
#
# Пара «регистрация хуков» заведена против того, что хук «висит на не том событии —
# или сразу на двух». Ловит она две формы: ПРИЗРАК (`extra = evs - declared[name]`,
# лишнее событие в settings.json) и полное отсутствие (`name not in live`). Между
# ними — щель: хук, потерявший часть своих регистраций. Обратная сверка идёт по
# ИМЕНИ, а не по паре «имя+событие», хотя прямая — по паре.
#
# Вход: полная установка; `output-language-check.sh` объявлен в HOOKS_CONFIG на
# PreCompact, PreToolUse, Stop, UserPromptSubmit, а в settings.json оставлен только
# на PreToolUse (ровно то, что делает аддитивное слияние, если запись потеряли).
# Ожидание: DRIFT — три события из четырёх не срабатывают.
# Факт: OK|регистрация хуков|50|0, код возврата 0.
#
# Хуков с несколькими событиями в HOOKS_CONFIG четыре, не один: ablation-phase-guard,
# output-language-check, relative-date-check, fix-level-check.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

VICTIM="output-language-check.sh"
TMP=$(mktemp -d)
H="$TMP/home"
mkdir -p "$H"

KEPT=$(python3 - "$REPO/install.sh" "$H/settings.json" "$VICTIM" <<'PY'
import json, pathlib, re, sys
t = pathlib.Path(sys.argv[1]).read_text()
cfg = json.loads(re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", t, re.S).group(1))
victim = sys.argv[3]
keep_event = "PreToolUse"
dropped = []
for ev, groups in cfg["hooks"].items():
    if ev == keep_event:
        continue
    for g in groups:
        before = g.get("hooks", [])
        after = [h for h in before if victim not in h.get("command", "")]
        if len(after) != len(before):
            dropped.append(ev)
        g["hooks"] = after
pathlib.Path(sys.argv[2]).write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
print(",".join(sorted(set(dropped))))
PY
)
[ -n "$KEPT" ] || { echo "SKIP: $VICTIM не объявлен более чем на одном событии"; exit 0; }

OUT=$(CLAUDSOUL_REPO="$REPO" CLAUDE_HOME="$H" bash "$DRIFT" 2>/dev/null)
LINE=$(printf '%s\n' "$OUT" | grep '|регистрация хуков|' || true)

echo "  снято регистраций: $VICTIM с событий $KEPT (оставлен PreToolUse)"
echo "  | $LINE"

if grep -q '^DRIFT|' <<< "$LINE"; then
    echo "PASS: потерянные регистрации названы расхождением"
    exit 0
fi
echo "FAIL: хук потерял регистрацию на событиях $KEPT, а пара «регистрация хуков» этого не увидела."
echo "      Сверка «объявлено → установлено» идёт по ИМЕНИ хука, а не по паре «имя+событие»:"
echo "      пока хоть одна регистрация жива, недостающие невидимы."
exit 1
