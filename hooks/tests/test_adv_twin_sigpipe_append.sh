#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/output-language-check.sh hooks/relative-date-check.sh hooks/fix-level-check.sh hooks/accepted-alternative-gap.sh
# test_adv_twin_sigpipe_append.sh — противник окна хода (D498): гонка дописывания. Помощник
# меряет конец окна по размеру файла в момент своего вызова, а байты режет `tail -c +S | head -c N`
# уже позже. Если харнесс за это время дописал ПОЛНУЮ запись больше буфера канала, `head`
# выходит, прочитав N байт, а `tail` получает SIGPIPE на остатке: `transcript_turn_window`
# возвращает 141. Под `set -eo pipefail` присваивание `last_assistant=$(transcript_turn_window …)`
# роняет хук целиком — нарушение не записано. Прежний `jq -s` по файлу целиком полную
# дописанную запись разбирает без ошибки.
# Гонка воспроизводится детерминированно: python3 на PATH — прозрачная обёртка, которая ПОСЛЕ
# ответа помощника дописывает в расшифровку одну полную запись в 1 МБ (результат инструмента
# параллельного вызова), то есть ровно то, что делает харнесс между двумя шагами хука.
# С 2 октября 2026 байты окна отдаёт сам помощник (режим --emit), и зазора между замером конца
# и чтением больше нет; обёртка дописывает после его ответа — хук обязан пережить и это.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
REAL_PY=$(command -v python3) || { echo "SKIP: нет python3"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
SID="adv-sigpipe"

mkdir -p "$T/bin"
cat > "$T/bin/python3" <<EOF
#!/usr/bin/env bash
case " \$* " in
  *transcript_window.py*--range*|*transcript_window.py*--emit*)
    out=\$("$REAL_PY" "\$@"); rc=\$?
    if [ ! -f "$T/appended" ]; then
        : > "$T/appended"
        # \$1 — путь помощника, \$2 — расшифровка: дописывается ТОЛЬКО файл под каталогом теста.
        case "\$2" in "$T"/*) ;; *) echo "обёртка: чужой путь \$2" >&2; exit 97 ;; esac
        "$REAL_PY" -c 'import json,sys; open(sys.argv[1],"a").write(json.dumps({"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"p1","content":"x"*1048576}]}})+"\n")' "\$2"
    fi
    printf '%s\n' "\$out"; exit \$rc ;;
  *) exec "$REAL_PY" "\$@" ;;
esac
EOF
chmod +x "$T/bin/python3"

mk() {  # mk <файл>: ход владельца, ответ агента со смешением алфавитов
    { jq -nc '{type:"user",origin:{kind:"human"},message:{role:"user",content:[{type:"text",text:"проверь журнал"}]}}'
      jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Сверяю лookup по журналу"}]}}'; } > "$1"
}

# Окно + гонка (обёртка на PATH).
mk "$T/race.jsonl"; mkdir -p "$T/st-race"
printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$SID" "$T/race.jsonl" \
    | PATH="$T/bin:$PATH" STATE_DIR="$T/st-race" bash "$HOOKS/output-language-check.sh" >/dev/null 2>&1
RC_RACE=$?
# Прежнее поведение на ТОМ ЖЕ итоговом содержимом: файл целиком.
cp "$T/race.jsonl" "$T/whole.jsonl"; mkdir -p "$T/st-whole"
# Окно — весь файл: настоящая библиотека ввода (её ядро «запись user», D1153), подменено только окно.
printf '. "%s/hook-input-lib.sh"\n%s\n' "$HOOKS" 'transcript_turn_window() { cat "$1"; }' > "$T/whole-lib.sh"
printf '{"session_id":"%s","transcript_path":"%s","hook_event_name":"Stop","stop_hook_active":false}' "$SID" "$T/whole.jsonl" \
    | INPUT_LIB="$T/whole-lib.sh" STATE_DIR="$T/st-whole" bash "$HOOKS/output-language-check.sh" >/dev/null 2>&1
RC_WHOLE=$?

[ -f "$T/appended" ] && ok || bad T0 "контроль: обёртка не сработала — гонка не воспроизведена"
grep -q "ookup" "$T/st-whole/output-violations-$SID.jsonl" 2>/dev/null && ok \
    || bad T1 "контроль: по файлу целиком нарушение обязано записаться"
[ "$RC_RACE" -eq 0 ] && ok || bad T2 "хук упал с кодом $RC_RACE при дописывании между помощником и tail (по файлу целиком — $RC_WHOLE)"
grep -q "ookup" "$T/st-race/output-violations-$SID.jsonl" 2>/dev/null && ok \
    || bad T3 "нарушение «лookup» не записано: окно уронило хук на гонке дописывания"

echo "test_adv_twin_sigpipe_append: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
