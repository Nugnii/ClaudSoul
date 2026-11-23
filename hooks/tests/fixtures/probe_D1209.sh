#!/usr/bin/env bash
set -u
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/tests/fixtures/probe_D1153.sh
# probe_D1209 — источники признака реплики судят её правилом владельца, а не своей копией рядом с ним (D1209, R3):
#   `transcript_user_texts` и `transcript_agent_text_before_reply` (`hooks/hook-input-lib.sh`) — `owner_reply`,
#   `_is_reply_any` (`hooks/lib/transcript_window.py`) — `is_owner_speech`. Формы, на которых копии расходились с
#   владельцем (в мире таких 0 из 109 701, дефект устройственный): роль не `user` при типе `user`, результат
#   инструмента рядом с текстом, автор строкой. Ответ каждой функции на каждой форме равен ответу владельца.
#   Распознаватель своей копии (`probe_D1153`) судит и источники: копия, возвращённая в `transcript_user_texts` в копии
#   дерева, краснит его кодом 1 строкой «своя проверка роли».
# Код: 0 — все функции отвечают как владелец, распознаватель видит копию в источнике; 1 — нет (названо); 2 — рамка.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
L="$R/hooks/hook-input-lib.sh"; TW="$R/hooks/lib/transcript_window.py"; P53="$R/hooks/tests/fixtures/probe_D1153.sh"
[ -f "$L" ] && [ -f "$TW" ] && [ -f "$P53" ] && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
own() {  # own <запись> → true/false владельца и быстрого пути через пробел
    python3 -c 'import json,sys; sys.path.insert(0, sys.argv[1]); import transcript_window as t; r=json.loads(sys.argv[2])
print(str(t.is_owner_speech(r)).lower(), str(t._is_reply_any(r)).lower())' "$R/hooks/lib" "$1" 2>/dev/null; }
[ "$(own '{"type":"user","message":{"role":"user","content":"да"}}')" = "true true" ] || { echo "рамка: реплика владельца не реплика" >&2; exit 2; }
miss=""
for name in role mixed origin; do
    case "$name" in
        role)   F='{"type":"user","message":{"role":"assistant","content":"ФОРМА"}}' ;;
        mixed)  F='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"x"},{"type":"text","text":"ФОРМА"}]}}' ;;
        origin) F='{"type":"user","origin":"human","message":{"role":"user","content":"ФОРМА"}}' ;;
    esac
    read -r o f <<< "$(own "$F")"
    [ -n "$o" ] || { echo "рамка: владелец не ответил на форму $name" >&2; exit 2; }
    [ "$f" = "$o" ] || miss="$miss _is_reply_any:$name"
    { printf '%s\n' '{"type":"user","message":{"role":"user","content":"ПЕРВАЯ"}}' \
        '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"A1"}]}}' "$F" \
        '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"A2"}]}}'; } > "$W/$name.jsonl"
    if [ "$o" = true ]; then want_ut="ПЕРВАЯ|ФОРМА|"; want_ab="A1"; else want_ut="ПЕРВАЯ|"; want_ab=""; fi
    ut=$(STATE_DIR="$W/st-$name" bash -c '. "$1"; transcript_user_texts "$2" 2' _ "$L" "$W/$name.jsonl" 2>/dev/null | tr '\n' '|')
    [ "$ut" = "$want_ut" ] || miss="$miss transcript_user_texts:$name"
    ab=$(STATE_DIR="$W/st-$name" bash -c '. "$1"; transcript_agent_text_before_reply "$2"' _ "$L" "$W/$name.jsonl" 2>/dev/null)
    [ "$ab" = "$want_ab" ] || miss="$miss transcript_agent_text_before_reply:$name"
done
[ -z "$miss" ] || { echo "копия правила реплики отвечает не как владелец:$miss"; exit 1; }
# Распознаватель своей копии судит источники: копия, возвращённая в `transcript_user_texts`, краснит probe_D1153.
mkdir -p "$W/t/hooks/tests/fixtures" "$W/t/scripts" && cp "$R"/hooks/*.sh "$W/t/hooks/" && cp -R "$R/hooks/lib" "$W/t/hooks/" \
    && cp -R "$R"/scripts/. "$W/t/scripts/" && cp "$P53" "$W/t/hooks/tests/fixtures/" || exit 2
python3 - "$W/t/hooks/hook-input-lib.sh" <<'PY' || { echo "рамка: строка правила владельца в transcript_user_texts не легла ровно раз" >&2; exit 2; }
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
a = "        as_reply | select(owner_reply)\n"
if s.count(a) != 1:
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s.replace(a, '        as_reply | select(.type == "user" and ((.isMeta // false) | not))\n'))
PY
out=$(CLAUDSOUL_REPO="$W/t" bash "$W/t/hooks/tests/fixtures/probe_D1153.sh" 2>/dev/null); rc=$?
[ "$rc" = 1 ] && printf '%s' "$out" | grep -q 'своя проверка роли.*hooks/hook-input-lib.sh' \
    || { echo "распознаватель своей копии не видит копию в источнике (probe_D1153: код $rc, ${out:0:160})"; exit 1; }
echo "копии правила реплики отвечают как владелец; распознаватель судит источники"
exit 0
