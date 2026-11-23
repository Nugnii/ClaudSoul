#!/usr/bin/env bash
# СУДИТ: hooks/lib/transcript_window.py hooks/hook-input-lib.sh hooks/root-cause-lib.sh hooks/activity-flush-lib.sh hooks/shared-language-lib.sh
# test_transcript_fold.sh — свёртка расшифровки по дописанным байтам (D498): тёплая равна холодной, а читается только дописанное.
#
# Предмет — два утверждения. (1) Накопленное по шагам равно свёртке всего файла с нуля: у rc_*,
# activity_flush и shlang_candidates вывод после каждого дописывания тот же, что у холодного
# вызова. (2) Тёплый вызов НЕ перечитывает прочитанное: строку, уже свёрнутую, переписываем на
# месте (тот же inode и размер) — тёплая свёртка её не видит, холодная видит. Без (2) нога (1)
# прошла бы и у помощника, который всё читает заново, — цена, ради которой свёртка заведена.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
eq()  { if [ "$2" = "$3" ]; then ok; else bad "$1" "ожидалось «$3», получено «$2»"; fi; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CNT='reduce inputs as $r (($a[0] // 0); . + (if $r.x then 1 else 0 end))'
fold() {  # fold <файл> <state|-> <session|turn> [шаг]
    if [ "$2" = - ]; then bash -c '. "$1/hook-input-lib.sh"; transcript_fold "$2" cnt "$3" jq -cn "$4" --slurpfile a' _ "$HOOKS" "$1" "$3" "${4:-$CNT}"
    else STATE_DIR="$2" bash -c '. "$1/hook-input-lib.sh"; transcript_fold "$2" cnt "$3" jq -cn "$4" --slurpfile a' _ "$HOOKS" "$1" "$3" "${4:-$CNT}"; fi
}

# F1 — сессия: тёплый счёт после дописывания равен холодному; недописанная строка не читается.
F="$T/s.jsonl"; mkdir -p "$T/st1"
printf '%s\n' '{"x":true}' '{"x":false}' > "$F"
eq F1a "$(fold "$F" "$T/st1" session)" 1
printf '%s\n' '{"x":true}' >> "$F"; printf '%s' '{"x":tr' >> "$F"
eq F1b "$(fold "$F" "$T/st1" session)" "$(fold "$F" - session)"
eq F1c "$(fold "$F" "$T/st1" session)" 2
printf '%s\n' 'ue}' >> "$F"
eq F1d "$(fold "$F" "$T/st1" session)" 3

# F2 — читается только дописанное: первая строка переписана на месте (тот же размер), тёплая
# свёртка её не видит, холодная видит.
python3 - "$F" <<'PY'
import sys
p = sys.argv[1]; b = open(p, "rb").read()
open(p, "r+b").write(b.replace(b'{"x":true}', b'{"x":null}', 1))
PY
printf '%s\n' '{"x":true}' >> "$F"
eq F2a "$(fold "$F" "$T/st1" session)" 4
eq F2b "$(fold "$F" - session)" 3

# F3 — поменялся шаг: накопленное по старому шагу не используется, счёт идёт с начала.
eq F3 "$(fold "$F" "$T/st1" session 'reduce inputs as $r (($a[0] // 0); . + 1)')" 5

# F4 — ход: новая реплика владельца начинает свёртку заново; испорченная строка ДО неё не мешает.
G="$T/t.jsonl"; mkdir -p "$T/st4"
u() { printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":[{"type":"text","text":"%s"}]},"x":true}\n' "$1"; }
{ u "раз"; printf '%s\n' '{"x":true}' '{"x":true}'; } > "$G"
eq F4a "$(fold "$G" "$T/st4" turn)" 3
{ printf '%s\n' '{"x":tr'; u "два"; printf '%s\n' '{"x":true}'; } >> "$G"
eq F4b "$(fold "$G" "$T/st4" turn)" 2
eq F4c "$(fold "$G" - turn)" 2

# F5 — помощника нет: шаг идёт по всему файлу с пустым накопленным.
mkdir -p "$T/nolib"; cp "$HOOKS/hook-input-lib.sh" "$T/nolib/"
eq F5 "$(STATE_DIR="$T/st1" bash -c '. "$1/hook-input-lib.sh"; transcript_fold "$2" cnt session jq -cn "$3" --slurpfile a' _ "$T/nolib" "$F" "$CNT")" 3

# Расшифровка для потребителей: реплики владельца с латиницей (словарь), правки файлов, вызовы
# инструментов, вставки харнесса (уведомление задачи, сводка сжатия, isMeta), тексты агента.
python3 - "$T/full.jsonl" <<'PY'
import json, sys
def u(x, **kw): return json.dumps(dict({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": x}]}}, **kw), ensure_ascii=False)
def a(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def e(fp, name="Edit"): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": name, "input": {"file_path": fp}}]}}, ensure_ascii=False)
tr = json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}})
ls = [u("проверь workflow и deploy-check"), a("Смотрю workflow"), e("/r/b.sh"), tr, a("Почему так?"),
      json.dumps({"type": "user", "origin": {"kind": "task-notification"}, "message": {"role": "user", "content": [{"type": "text", "text": "задача workflow"}]}}),
      a("после уведомления"), e("/r/a.md", "Write"), tr, u("ещё workflow, deploy-check и rollout-plan"),
      json.dumps({"type": "user", "isMeta": True, "message": {"role": "user", "content": [{"type": "text", "text": "мета workflow"}]}}),
      a("ответ 2"), e("/r/b.sh", "MultiEdit"), tr,
      json.dumps({"type": "user", "isCompactSummary": True, "message": {"role": "user", "content": "сводка"}}),
      a("после сжатия"), u("deploy-check снова, rollout-plan"), a("финал")]
open(sys.argv[1], "w").write("\n".join(ls) + "\n")
PY
GRAB='for f in rc_turn_key rc_last_block rc_turn_text; do printf "%s|" "$("$f" "$2")"; done
      d="$(mktemp -d)"; activity_flush sid-fold-01 "$2" "$d" >/dev/null 2>&1
      sed "/^## /d" "$d/.claude-docs/session-activity.md" 2>/dev/null; rm -rf "$d"
      shlang_candidates "$2" /dev/null 1'
grab() {  # grab <файл> <state> → rc_* | журнал активности | кандидаты словаря
    STATE_DIR="$2" bash -c ". \"\$1/root-cause-lib.sh\"; . \"\$1/activity-flush-lib.sh\"; . \"\$1/shared-language-lib.sh\"; $GRAB" _ "$HOOKS" "$1"
}

# F6 — потребители: после КАЖДОЙ дописанной строки тёплый вывод равен холодному.
P="$T/part.jsonl"; : > "$P"; mkdir -p "$T/st6"; n=0; diff6=""
while IFS= read -r line; do
    printf '%s\n' "$line" >> "$P"; n=$((n + 1))
    [ "$(grab "$P" "$T/st6")" = "$(grab "$P" "$(mktemp -d "$T/cold.XXXX")")" ] || diff6="$diff6 $n"
done < "$T/full.jsonl"
eq F6 "${diff6:-нет}" нет
# Контроль: вывод не тривиален — метка, текст хода, журнал с правками и кандидаты словаря есть.
W=$(grab "$P" "$T/st6")
case "$W" in *"финал"*"Files touched: a.md b.sh"*"deploy-check ×3"*) ok ;;
    *) bad F6c "вывод потребителей пуст или не тот: ${W:0:300}" ;; esac

# F7 — уборка своих файлов: метки окна и свёртки старше трёх суток убираются, свежие и чужие
# остаются; метка часа не даёт обходить каталог на каждом вызове.
mkdir -p "$T/st7"
for n in transcript-fold-x-old transcript-turn-old other-old; do touch -t 202001010000 "$T/st7/$n"; done
touch "$T/st7/transcript-fold-x-new"
fold "$F" "$T/st7" session >/dev/null
eq F7a "$(ls "$T/st7" | grep -c -- '-old$')" 1
[ -e "$T/st7/other-old" ] && [ -e "$T/st7/transcript-fold-x-new" ] && ok || bad F7b "убран чужой или свежий файл"
touch -t 202001010000 "$T/st7/transcript-turn-late"
fold "$F" "$T/st7" session >/dev/null
[ -e "$T/st7/transcript-turn-late" ] && ok || bad F7c "каталог обойдён повторно в пределах часа"

echo "test_transcript_fold: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
