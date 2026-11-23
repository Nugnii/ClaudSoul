#!/usr/bin/env bash
# СУДИТ: lib/hooks-merge.jq
# test_install_hooks_merge.sh — слияние регистраций не плодит дублей и не трогает чужое.
#
# Повод (5 сентября 2026). Программа слияния жила инлайном в install.sh и не имела прибора
# ни одного: позвать её можно было только полной установкой. Смена matcher у одного хука
# показала дефект — группа искалась по РАВЕНСТВУ matcher, не находилась, и регистрация
# ДОБАВЛЯЛАСЬ рядом с прежней. Замер того же дня: 6 дублей из 75 регистраций.
# Сверщик дрейфа этого не видел и не увидит: matcher в сравнение не входит (D317).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Путь программы переопределяется РАДИ МУТАЦИИ: прибор обязан краснеть на прежней
# редакции, и показать это можно только подсунув её.
MERGE="${MERGE_JQ:-$ROOT/lib/hooks-merge.jq}"
[ -f "$MERGE" ] || { echo "FAIL: нет $MERGE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

CFG='{"PostToolUse":[{"matcher":"Bash|Write|Edit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/our.sh"}]}],
      "SessionEnd":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/end.sh"}]}]}'

merge() { jq --argjson cfg "$CFG" -f "$MERGE"; }
# Сколько раз команда зарегистрирована на событии.
count_cmd() { jq --arg ev "$2" --arg c "$3" '[.hooks[$ev][]? | (.hooks // [])[] | select(.command == $c)] | length' <<< "$1"; }
matchers_of() { jq -r --arg ev "$2" --arg c "$3" '[.hooks[$ev][]? | select([(.hooks // [])[].command] | index($c)) | (.matcher // "")] | join(",")' <<< "$1"; }

# --- T1: наш хук стоит с ПРЕЖНИМ matcher — после слияния он ОДИН и с объявленным ---
LIVE='{"hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/our.sh"}]}]}}'
OUT=$(printf '%s' "$LIVE" | merge)
N=$(count_cmd "$OUT" PostToolUse "bash ~/.claude/hooks/our.sh")
[ "$N" = "1" ] && ok || bad "T1" "регистраций после слияния: $N (ожидалась 1)"
M=$(matchers_of "$OUT" PostToolUse "bash ~/.claude/hooks/our.sh")
[ "$M" = "Bash|Write|Edit" ] && ok || bad "T1b" "matcher после слияния: «${M}»"

# --- T2: чужой хук в чужой группе не тронут ---
LIVE2='{"hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/our.sh"},{"type":"command","command":"bash ~/.claude/hooks/alien.sh"}]}]}}'
OUT2=$(printf '%s' "$LIVE2" | merge)
NA=$(count_cmd "$OUT2" PostToolUse "bash ~/.claude/hooks/alien.sh")
[ "$NA" = "1" ] && ok || bad "T2" "чужая команда: $NA (ожидалась 1)"
NO=$(count_cmd "$OUT2" PostToolUse "bash ~/.claude/hooks/our.sh")
[ "$NO" = "1" ] && ok || bad "T2b" "наша команда: $NO (ожидалась 1)"

# --- T3: пустой matcher и ОТСУТСТВУЮЩИЙ ключ — одно и то же, дубля быть не должно ---
LIVE3='{"hooks":{"SessionEnd":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/end.sh"}]}]}}'
OUT3=$(printf '%s' "$LIVE3" | merge)
N3=$(count_cmd "$OUT3" SessionEnd "bash ~/.claude/hooks/end.sh")
[ "$N3" = "1" ] && ok || bad "T3" "регистраций end.sh: ${N3} (ожидалась 1); пустой matcher и отсутствие ключа — одно и то же"

# --- T4: слияние идемпотентно — второй прогон не плодит ---
OUT4=$(printf '%s' "$OUT" | merge)
N4=$(count_cmd "$OUT4" PostToolUse "bash ~/.claude/hooks/our.sh")
[ "$N4" = "1" ] && ok || bad "T4" "после повторного слияния: $N4"

# --- T5: чистая машина — регистрация появляется ---
OUT5=$(printf '%s' '{"hooks":{}}' | merge)
N5=$(count_cmd "$OUT5" PostToolUse "bash ~/.claude/hooks/our.sh")
[ "$N5" = "1" ] && ok || bad "T5" "на пустых hooks: $N5"

# --- T6: чужое СОБЫТИЕ целиком не тронуто ---
LIVE6='{"hooks":{"Notification":[{"matcher":"","hooks":[{"type":"command","command":"bash ~/.claude/hooks/alien2.sh"}]}]}}'
OUT6=$(printf '%s' "$LIVE6" | merge)
N6=$(count_cmd "$OUT6" Notification "bash ~/.claude/hooks/alien2.sh")
[ "$N6" = "1" ] && ok || bad "T6" "чужое событие: $N6"

# --- T7: та же регистрация в ДРУГОЙ форме записи — после слияния она ОДНА ---
# Повод, 9 сентября 2026: живая запись стояла как `$HOME/.claude/hooks/x.sh`, а канон
# установщика — `bash ~/.claude/hooks/x.sh`. Слияние сравнивало строки целиком, не находило
# и добавляло вторую: хук вызывался бы дважды на одном событии. Замер по живым настройкам —
# команд 76, в каноне 75, задвоилась ровно та одна, что записана иначе.
# Тот же корень, что чинили здесь 5 сентября для matcher: ключ поиска обязан быть тем, что
# НЕ меняется. Команда меняется вместе с формой записи; имя файла — нет.
LIVE7='{"hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"$HOME/.claude/hooks/our.sh"}]}]}}'
OUT7=$(printf '%s' "$LIVE7" | merge)
N7=$(count_cmd "$OUT7" PostToolUse "bash ~/.claude/hooks/our.sh")
N7OLD=$(count_cmd "$OUT7" PostToolUse '$HOME/.claude/hooks/our.sh')
if [ "$N7" = "1" ] && [ "$N7OLD" = "0" ]; then ok
else bad "T7" "иная форма записи задвоила регистрацию: канон=$N7, прежняя форма=$N7OLD (ожидалось 1 и 0)"; fi

# --- T8: хук с аргументами — имя файла берётся без них ---
LIVE8='{"hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"bash ~/.claude/hooks/our.sh --flag"}]}]}}'
OUT8=$(printf '%s' "$LIVE8" | merge)
N8=$(count_cmd "$OUT8" PostToolUse "bash ~/.claude/hooks/our.sh")
[ "$N8" = "1" ] && ok || bad "T8" "форма с аргументами: $N8 (ожидалась 1)"

# --- T9: чужой хук с ТЕМ ЖЕ базовым именем не исчезает ---
# Повод, 10 сентября 2026, прожарка. Ключ сопоставления стал именем файла (T7), и вместе с
# задвоением ушла чужая регистрация: `node /opt/vendor/bin/our.sh --json` получала тот же id,
# что наш `our.sh`, и вычищалась молча. Шапка обещает «чужие хуки не тронуты».
# Прежний предел оправдывался тем, что в НАШЕМ дереве одинаковых имён нет — но слияние
# работает в ЧУЖИХ настройках, где это ничего не гарантирует, а имена генерические.
LIVE9='{"hooks":{"PostToolUse":[{"matcher":"Write|Edit","hooks":[{"type":"command","command":"node /opt/vendor/bin/our.sh --json"},{"type":"command","command":"bash ~/.claude/hooks/our.sh"}]}]}}'
OUT9=$(printf '%s' "$LIVE9" | merge)
N9ALIEN=$(count_cmd "$OUT9" PostToolUse "node /opt/vendor/bin/our.sh --json")
N9OURS=$(count_cmd "$OUT9" PostToolUse "bash ~/.claude/hooks/our.sh")
if [ "$N9ALIEN" = "1" ] && [ "$N9OURS" = "1" ]; then ok
else bad "T9" "чужой хук с тем же именем: чужих=$N9ALIEN (ожидался 1), своих=$N9OURS (ожидался 1)"; fi

echo "install hooks merge: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
