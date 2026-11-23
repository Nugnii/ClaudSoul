#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# probe_D1346.sh — служебная копия запроса (`api-request-blob`) с ролью assistant действием нынешнего хода не считается.
#
# Повод (21 ноября 2026, взятие D1343). Клиент пишет в расшифровку копии сообщений запроса записью вида
# `api-request-blob`; у копии ответа модели `message.role` — assistant, и в ней те же вызовы инструментов. Копия
# последнего ответа прошлого хода ложится уже в следующий ход, и читатель, отбирающий ответы модели по роли, а не по
# виду записи, засчитывает прошлую правку бэклога исходом нынешнего хода.
# Проверка результата: bash hooks/tests/fixtures/probe_D1346.sh → 0 — ход из одних слов с копией прошлой правки исхода
#   не имеет; 1 — имеет; 2 — не измерено (нет библиотек, jq или python3, либо рамка не различает: правка в нынешнем
#   ходе обязана дать исход, а прошлая правка без копии — не дать).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
for f in hooks/paths-lib.sh hooks/portable-lib.sh hooks/hook-input-lib.sh hooks/root-cause-lib.sh; do
    [ -f "$REPO/$f" ] || { echo "нет $f — не измерено"; exit 2; }
done
for c in jq python3; do command -v "$c" >/dev/null 2>&1 || { echo "нет $c — не измерено"; exit 2; }; done
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
python3 - "$T" <<'PY' || { echo "расшифровки не собраны — не измерено"; exit 2; }
import json, os, sys
d = sys.argv[1]
def u(t): return {"type": "user", "message": {"role": "user", "content": [{"type": "text", "text": t}]}}
edit = {"type": "tool_use", "id": "toolu_A", "name": "Edit",
        "input": {"file_path": "/repo/BACKLOG.md", "old_string": "a", "new_string": "- ☐ **D9** x"}}
real = {"type": "assistant", "message": {"role": "assistant", "content": [edit]}}
res = {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "toolu_A", "content": "ok"}]}}
blob = {"type": "api-request-blob", "hash": "h1", "sessionId": "s", "message": {"role": "assistant", "content": [edit]}}
say = {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Смотрю дальше."}]}}
def w(name, rows):
    with open(os.path.join(d, name), "w", encoding="utf-8") as f:
        f.write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
w("now.jsonl", [u("дальше"), real, res, say])                    # правка в нынешнем ходе
w("past.jsonl", [u("чини"), real, res, u("дальше"), say])        # правка в прошлом ходе
w("copy.jsonl", [u("чини"), real, res, u("дальше"), blob, say])  # то же и копия запроса в нынешнем ходе
PY
seen() {   # <расшифровка> → исходы хода строкой либо пусто
    bash -c '. "$0/hooks/paths-lib.sh" 2>/dev/null; . "$0/hooks/portable-lib.sh" 2>/dev/null
             . "$0/hooks/hook-input-lib.sh" 2>/dev/null; . "$0/hooks/root-cause-lib.sh" 2>/dev/null
             command -v rc_outcome_observed >/dev/null 2>&1 || exit 3
             rc_outcome_observed "$1"' "$REPO" "$1" 2>/dev/null
}
now=$(seen "$T/now.jsonl"); past=$(seen "$T/past.jsonl"); copy=$(seen "$T/copy.jsonl")
case "$now" in *"пункт долга"*) ;; *) echo "контроль: правка бэклога в нынешнем ходе исходом не названа — не измерено"; exit 2 ;; esac
[ -z "$past" ] || { echo "контроль: прошлая правка без копии названа исходом нынешнего хода (${past}) — не измерено"; exit 2; }
if [ -n "$copy" ]; then
    echo "копия запроса с прошлой правкой засчитана исходом нынешнего хода: ${copy}"
    exit 1
fi
echo "копия запроса исходом нынешнего хода не считается"
exit 0
