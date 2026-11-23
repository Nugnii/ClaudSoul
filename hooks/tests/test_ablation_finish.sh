#!/usr/bin/env bash
# СУДИТ: scripts/ablation/
# test_ablation_finish.sh — финишные компоненты запускалки: парсер транскриптов,
# заморозка фазы (тег + read-only runtime), связка outputValue↔signature.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
AB="$ROOT/scripts/ablation"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

TMP=$(mktemp -d)
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"
mkdir -p "$ABLATION_DIR"

# --- T1: парсер — токены из result.json, команды/ошибки из транскриптов ---
RUN="$ABLATION_DIR/runs/t-x/full"
mkdir -p "$RUN/home/.claude/projects/p1"
printf '{"usage":{"input_tokens":100,"output_tokens":200},"num_turns":5,"duration_ms":1234}' > "$RUN/result.json"
cat > "$RUN/home/.claude/projects/p1/t.jsonl" << 'EOF'
{"message":{"content":[{"type":"tool_use","name":"Bash"},{"type":"text","text":"x"}]}}
{"message":{"content":[{"type":"tool_result","is_error":true}]}}
{"message":{"content":[{"type":"tool_use","name":"Edit"},{"type":"tool_use","name":"Read"}]}}
EOF
OUT=$(python3 "$AB/parse-transcript.py" t-x full)
assert_contains "$OUT" '"tokens_in": 100' "T1: токены входа"
assert_contains "$OUT" '"all_commands": 3' "T1b: все вызовы"
assert_contains "$OUT" '"failed_commands": 1' "T1c: упавшие"
assert_contains "$(tail -1 "$ABLATION_DIR/journal.jsonl")" '"e":"arm_metrics"' "T1d: событие в журнале"
assert_contains "$OUT" '"usage": "measured"' "T1e: состояние чтения названо и у исправного итога"

# --- T1f..T1m: ноль в записи значит «измерено: ноль», и только это (D436, 17 сентября 2026) ---
# До починки четыре разных состояния result.json (нет файла, оборван, разобран без usage, честные
# нули) отвечали одной записью 0/0, а ещё три (не UTF-8, JSON не словарь, usage:null) роняли парсер
# до записи. Ноги держат ОБЕ стороны: неизвестное — null с названным состоянием, честный ноль —
# по-прежнему 0 (без этой ноги «всегда null» проходило бы), и запись есть у КАЖДОГО прогона.
mkrun() { mkdir -p "$ABLATION_DIR/runs/$1/full"; [ "$#" -lt 2 ] || printf '%b' "$2" > "$ABLATION_DIR/runs/$1/full/result.json"; }
mkrun t-none
# ПУСТОЙ файл — не выдуманное состояние, а то, что оставляет запуск, убитый таймаутом:
# `shadow-run.sh:78` создаёт result.json перенаправлением ДО старта агента (поправка скептика).
mkrun t-empty   ''
mkrun t-torn    '{"usage": {"input_tokens": 100, '
mkrun t-bin     '\xff\xfe\x00\x80garbage'
mkrun t-list    '[]'
mkrun t-nousage '{"is_error":true,"num_turns":2}'
mkrun t-unull   '{"usage":null}'
mkrun t-zero    '{"usage":{"input_tokens":0,"output_tokens":0},"num_turns":0,"duration_ms":0}'
# Итог из 200 000 скобок даёт RecursionError — не ValueError и не OSError: перечень форм
# исключений дважды оказывался неполон, поэтому ловится любой отказ чтения.
python3 -c "print('[' * 200000, end='')" > "$TMP/deep.json"
mkrun t-deep; cp "$TMP/deep.json" "$ABLATION_DIR/runs/t-deep/full/result.json"
# У честного нуля транскрипт ЕСТЬ и вызовов в нём нет: ноль команд здесь тоже измерен.
mkdir -p "$ABLATION_DIR/runs/t-zero/full/home/.claude/projects/p1"
printf '%s\n' '{"message":{"content":[{"type":"text","text":"hi"}]}}' \
    > "$ABLATION_DIR/runs/t-zero/full/home/.claude/projects/p1/t.jsonl"
for pair in t-none:unknown t-empty:corrupt t-deep:corrupt t-torn:corrupt t-bin:corrupt t-list:no_usage t-nousage:no_usage t-unull:no_usage; do
    id=${pair%%:*}; want=${pair#*:}
    OUT=$(python3 "$AB/parse-transcript.py" "$id" full 2>"$TMP/err.$id"); RC=$?
    [ "$RC" = 0 ] && ok || bad "T1f[$id]" "парсер упал (rc $RC) — прогон выпадает из журнала: $(tail -1 "$TMP/err.$id")"
    assert_contains "$OUT" "\"usage\": \"$want\"" "T1g[$id]: состояние чтения"
    assert_contains "$OUT" '"tokens_in": null, "tokens_out": null' "T1h[$id]: стоимость неизвестна, а не 0"
    assert_contains "$(cat "$TMP/err.$id")" "НЕИЗВЕСТНА (usage=$want)" "T1i[$id]: оператору сказано в stderr"
done
assert_contains "$(python3 "$AB/parse-transcript.py" t-nousage full 2>/dev/null)" '"turns": 2' "T1j: что в итоге есть — берётся"
OUT=$(python3 "$AB/parse-transcript.py" t-zero full 2>"$TMP/err.zero")
assert_contains "$OUT" '"tokens_in": 0, "tokens_out": 0, "usage": "measured"' "T1k: честный ноль остаётся нулём"
assert_contains "$OUT" '"all_commands": 0, "failed_commands": 0' "T1k2: транскрипт без вызовов — честный ноль команд"
assert_empty "$(cat "$TMP/err.zero")" "T1l: на измеренном stderr молчит"
N=$(grep -c '"e":"arm_metrics"' "$ABLATION_DIR/journal.jsonl")
[ "$N" = 11 ] && ok || bad "T1m" "записей arm_metrics $N, а прогонов парсера было 11 — кто-то выпал из журнала"
# Неразобранная строка транскрипта считается, а не растворяется (тот же корень на втором входе);
# пустая строка — не потеря. Транскрипт T1 разборчив целиком: там счётчик обязан быть 0.
mkdir -p "$ABLATION_DIR/runs/t-tr/full/home/.claude/projects/p1"
printf '%s\n' '{"message":{"content":[{"type":"tool_use","name":"Bash"}]}}' '' '{"message":{"content":[{"type":"tool_use","na' \
    > "$ABLATION_DIR/runs/t-tr/full/home/.claude/projects/p1/t.jsonl"
printf '\xff\xfe{"message":\n' >> "$ABLATION_DIR/runs/t-tr/full/home/.claude/projects/p1/t.jsonl"   # не UTF-8: прежде ронял парсер
OUT=$(python3 "$AB/parse-transcript.py" t-tr full 2>/dev/null)
assert_contains "$OUT" '"all_commands": 1' "T1n: разборчивая строка посчитана"
assert_contains "$OUT" '"transcript_unparsed": 2' "T1o: оборванная и не-UTF-8 строки названы числом, пустая — нет"
assert_contains "$(python3 "$AB/parse-transcript.py" t-x full)" '"transcript_unparsed": 0' "T1p: чистый транскрипт — ноль потерь"
# --- T1q..T1s: тот же корень на счётчиках команд (находка скептика, 17 сентября 2026) ---
# Счётчики рождались нулями до чтения транскриптов: «транскриптов нет» и «файл транскрипта пуст»
# отвечали той же записью, что «агент не сделал ни одного вызова». Итог у обоих прогонов исправен —
# null обязан прийти от ВТОРОГО входа, а не от первого.
for id in t-notr t-emptytr; do
    mkrun "$id" '{"usage":{"input_tokens":1,"output_tokens":2},"num_turns":1,"duration_ms":1}'
done
mkdir -p "$ABLATION_DIR/runs/t-emptytr/full/home/.claude/projects/p1"
: > "$ABLATION_DIR/runs/t-emptytr/full/home/.claude/projects/p1/t.jsonl"
for id in t-notr t-emptytr; do
    OUT=$(python3 "$AB/parse-transcript.py" "$id" full 2>"$TMP/err.$id")
    assert_contains "$OUT" '"usage": "measured"' "T1q[$id]: стоимость при этом измерена"
    assert_contains "$OUT" '"all_commands": null, "failed_commands": null' "T1q[$id]: счёт команд неизвестен, а не 0"
    assert_contains "$OUT" '"transcript_lines": 0' "T1q[$id]: разобранных строк ноль — названо числом"
    assert_contains "$OUT" '"denials": null' "T1q[$id]: отказы стражей неизвестны, а не 0"
    assert_contains "$(cat "$TMP/err.$id")" "счёт команд $id/full НЕИЗВЕСТЕН" "T1r[$id]: оператору сказано в stderr"
done
# Строки, разобранные НЕ в словарь, словарь с `message` не-словарём и каталог с именем *.jsonl
# прежде роняли парсер до записи (AttributeError, IsADirectoryError).
mkdir -p "$ABLATION_DIR/runs/t-odd/full/home/.claude/projects/p1/dir.jsonl"
printf '%s\n' '[]' 'null' '5' '{"message":"hello"}' '{"message":[1,2]}' \
    '{"message":{"content":[{"type":"tool_use","name":"Bash"}]}}' \
    > "$ABLATION_DIR/runs/t-odd/full/home/.claude/projects/p1/t.jsonl"
OUT=$(python3 "$AB/parse-transcript.py" t-odd full 2>/dev/null); RC=$?
[ "$RC" = 0 ] && ok || bad "T1s" "парсер упал (rc $RC) на строках-не-словарях — прогон выпадает из журнала"
assert_contains "$OUT" '"all_commands": 1' "T1s: вызов из разборчивой строки посчитан"
assert_contains "$OUT" '"transcript_lines": 3, "transcript_unparsed": 4' "T1s: три словаря разобраны; три не-словаря и каталог названы потерей"
# Сырой U+2028 внутри текста — законный JSONL (JSON.stringify его не экранирует): строка одна.
mkdir -p "$ABLATION_DIR/runs/t-ls/full/home/.claude/projects/p1"
printf '{"message":{"content":[{"type":"text","text":"a\xe2\x80\xa8b"},{"type":"tool_use","name":"Bash"}]}}\r\n' \
    > "$ABLATION_DIR/runs/t-ls/full/home/.claude/projects/p1/t.jsonl"
assert_contains "$(python3 "$AB/parse-transcript.py" t-ls full 2>/dev/null)" '"all_commands": 1, "failed_commands": 0, "transcript_lines": 1, "transcript_unparsed": 0' \
    "T1t: строка с U+2028 (и с \\r\\n на конце) не режется надвое, её вызов посчитан"

# --- T1u..T1z: что в итоге есть стоимость, решает источник, а не перечень имён (D437, 17 сентября 2026) ---
# До починки из `usage` читались два имени литералом, и расход кеша (в замере по расшифровкам —
# 99,76% суммы четырёх счётчиков) в запись не попадал. Ноги держат ОБЕ стороны: всякий числовой
# лист итога доходит до записи под путём источника — верхний, вложенный, из списка, из `modelUsage`
# и с именем, которого нет нигде в дереве (перечень, удлинённый на два имени кеша, на нём краснеет), —
# а названные поля остаются прежними: кеш с input НЕ складывается, нечисловое не переносится,
# чего нет в источнике — того нет и в записи (нулём не рождается).
mkrun t-cache '{"type":"result","is_error":false,"duration_ms":10,"duration_api_ms":8,"num_turns":3,"result":"ОТВЕТ-АГЕНТА","total_cost_usd":0.5,"usage":{"input_tokens":100,"output_tokens":200,"cache_read_input_tokens":4000,"cache_creation_input_tokens":3000,"zz_unnamed_tokens":7,"service_tier":"standard","cache_creation":{"ephemeral_5m_input_tokens":2500},"iterations":[{"input_tokens":60},{"input_tokens":40}]},"modelUsage":{"claude-x":{"inputTokens":5,"costUSD":0.25}}}'
OUT=$(python3 "$AB/parse-transcript.py" t-cache full 2>/dev/null)
for want in '"result.usage.cache_read_input_tokens": 4000' '"result.usage.cache_creation_input_tokens": 3000' \
            '"result.usage.zz_unnamed_tokens": 7' '"result.usage.cache_creation.ephemeral_5m_input_tokens": 2500' \
            '"result.usage.iterations.0.input_tokens": 60' '"result.usage.iterations.1.input_tokens": 40' \
            '"result.modelUsage.claude-x.inputTokens": 5' '"result.total_cost_usd": 0.5' '"result.duration_api_ms": 8'; do
    assert_contains "$OUT" "$want" "T1u: числовой лист итога дошёл до записи"
done
assert_contains "$OUT" '"tokens_in": 100, "tokens_out": 200, "usage": "measured"' "T1v: кеш с input/output не сложен, названные поля прежние"
assert_contains "$OUT" '"turns": 3, "duration_ms": 10' "T1v2: ходы и длительность прежние"
for lost in 'ОТВЕТ-АГЕНТА' 'service_tier"' 'is_error'; do
    if grep -Fq -- "$lost" <<< "$OUT"; then bad "T1w" "нечисловой лист «${lost}» попал в запись — текст ответа раздувает журнал"; else ok; fi
done
# Отрицательный контроль: у итога T1 кеша нет — и ключа нет; ноль здесь был бы выдуманным замером.
OUT=$(python3 "$AB/parse-transcript.py" t-x full)
if grep -Fq -- 'cache' <<< "$OUT"; then bad "T1x" "ключ кеша родился без источника: $OUT"; else ok; fi
assert_contains "$OUT" '"result.usage.input_tokens": 100' "T1x2: у итога из двух полей листья — те же два поля"
# Неразобранный итог листьев не даёт, а парсер не падает (состояние уже названо полем `usage`).
if grep -Fq -- '"result.' <<< "$(python3 "$AB/parse-transcript.py" t-torn full 2>/dev/null)"; then bad "T1y" "у оборванного итога появились листья"; else ok; fi
# Глубокий `usage`: где json.loads его разбирает (C-сканер 3.12+ — да, 3.11 — нет, и это corrupt),
# рекурсивный обход упал бы на пределе в 1000 кадров ДО записи; обход стеком пишет запись всегда.
python3 -c "import sys; n=5000; sys.stdout.write('{\"usage\":{\"input_tokens\":1,\"output_tokens\":2,\"deep\":' + '{\"a\":'*n + '5' + '}'*n + '}}')" > "$TMP/deepusage.json"
mkrun t-deepu; cp "$TMP/deepusage.json" "$ABLATION_DIR/runs/t-deepu/full/result.json"
OUT=$(python3 "$AB/parse-transcript.py" t-deepu full 2>"$TMP/err.deepu"); RC=$?
[ "$RC" = 0 ] && ok || bad "T1z" "парсер упал (rc $RC) на глубоком usage — прогон выпадает из журнала: $(tail -1 "$TMP/err.deepu")"
assert_contains "$OUT" '"e": "arm_metrics"' "T1z2: запись у глубокого итога есть"
# --- T1za..T1ze: ключ источника стал ключом записи — два отказа этого входа (поправки скептика) ---
# (а) Ключ с одиночным суррогатом ронял парсер на записи в журнал (UnicodeEncodeError): прогон
# выпадал из журнала, а парсер из 4551354 на том же входе запись писал — регрессия D437.
# printf '%s', а не mkrun: его `%b` раскрыл бы `\u` сам, и по-разному в bash 3.2 и 5.
mkrun t-surr; printf '%s' '{"usage":{"input_tokens":1,"output_tokens":2,"\ud800":3}}' > "$ABLATION_DIR/runs/t-surr/full/result.json"
OUT=$(python3 "$AB/parse-transcript.py" t-surr full 2>"$TMP/err.surr"); RC=$?
[ "$RC" = 0 ] && ok || bad "T1za" "парсер упал (rc $RC) на ключе с суррогатом — прогон выпадает из журнала: $(tail -1 "$TMP/err.surr")"
SURR_LINE=$(grep -F '"id":"t-surr"' "$ABLATION_DIR/journal.jsonl")
assert_contains "$SURR_LINE" '"tokens_in":1,"tokens_out":2,"usage":"measured"' "T1zb: запись в журнале есть, названные поля целы"
assert_contains "$OUT" '"result.usage.\\ud800": 3' "T1zb2: лист под таким ключом не потерян — знак заменён текстовым видом"
# Строку читает СТРОГИЙ читатель: escape одиночного суррогата (запись с ensure_ascii) — законный
# JSON для Python, а jq 1.7.1 на нём отказывает, и `jq -s` теряет весь журнал, а не одну строку.
if jq -e . <<< "$SURR_LINE" >/dev/null 2>&1; then ok; else bad "T1zc" "строку журнала с таким ключом jq не читает: $SURR_LINE"; fi
# (б) Ключ с буквальной точкой и вложенный ключ давали ОДИН путь: второй лист затирал первый молча.
mkrun t-dot '{"usage":{"input_tokens":1,"output_tokens":2,"a.b":5,"a":{"b":9}}}'
OUT=$(python3 "$AB/parse-transcript.py" t-dot full 2>/dev/null)
assert_contains "$OUT" '"result.usage.a\\.b": 5' "T1zd: лист под ключом с буквальной точкой в записи — точка экранирована"
assert_contains "$OUT" '"result.usage.a.b": 9' "T1ze: вложенный лист с тем же путём не затёрт"

# --- T2: freeze-policy — тег + read-only runtime + манифест ---
# Идентичность — в конфиг фикстурного репо: git tag -a внутри freeze-policy
# требует её так же, как commit; на CI глобального gitconfig нет (поймано
# красным прогоном 31267492512 — локальная рамка проверки маскировала).
git -C "$TMP" init -q crepo && git -C "$TMP/crepo" config user.email t@t \
    && git -C "$TMP/crepo" config user.name t \
    && (cd "$TMP/crepo" && echo x > f && git add f && git commit -qm init)
mkdir -p "$TMP/rt/hooks" && echo '#!/bin/bash' > "$TMP/rt/hooks/h.sh" \
    && echo rules > "$TMP/rt/CLAUDE.md" && echo '{}' > "$TMP/rt/settings.json"
OUT=$(CLAUDSOUL_RUNTIME="$TMP/rt" bash "$AB/freeze-policy.sh" testphase "$TMP/crepo")
assert_contains "$OUT" "ablation-testphase" "T2: тег создан"
git -C "$TMP/crepo" rev-parse -q --verify refs/tags/ablation-testphase >/dev/null && ok || bad "T2b" "тега нет в репо"
[ -f "$ABLATION_DIR/frozen-runtime-testphase.manifest" ] && ok || bad "T2c" "манифеста нет"
if ( echo test > "$ABLATION_DIR/frozen-runtime-testphase/CLAUDE.md" ) 2>/dev/null; then
    bad "T2d" "frozen runtime записываем — read-only не сработал"
else ok; fi
assert_contains "$(tail -1 "$ABLATION_DIR/journal.jsonl")" '"e":"phase_frozen"' "T2e: событие фазы"

# --- T3: вторая фаза при активной — отказ; после close — грязное дерево — отказ ---
OUT=$(CLAUDSOUL_RUNTIME="$TMP/rt" bash "$AB/freeze-policy.sh" phase2 "$TMP/crepo" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3" "вторая фаза при активной прошла"
assert_contains "$OUT" "уже идёт фаза" "T3a: причина — активная фаза"
bash "$AB/phase.sh" close testphase >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_ablation_finish.sh:$LINENO" >&2; exit 1; }
echo dirty >> "$TMP/crepo/f"
OUT=$(CLAUDSOUL_RUNTIME="$TMP/rt" bash "$AB/freeze-policy.sh" phase2 "$TMP/crepo" 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3b" "заморозка грязного дерева прошла"
assert_contains "$OUT" "грязное" "T3c: причина названа"

# --- T4: verify-pulse — честная связка OK, сфабрикованная ловится ---
SIG="ab"; for i in 1 2 3 4 5 6; do SIG="$SIG$SIG"; done   # 128 hex = 64 байта
OVOK=$(python3 -c "import hashlib;print(hashlib.sha512(bytes.fromhex('$SIG')).hexdigest())")
printf '{"outputValue":"%s","signatureValue":"%s","timeStamp":"x","statusCode":0}' "$OVOK" "$SIG" > "$ABLATION_DIR/beacon-t1.json"
python3 "$AB/sampler.py" verify-pulse >/dev/null 2>&1 && ok || bad "T4" "честный pulse не прошёл"
printf '{"outputValue":"%s","signatureValue":"%s","timeStamp":"x","statusCode":0}' "deadbeef" "$SIG" > "$ABLATION_DIR/beacon-t2.json"
OUT=$(python3 "$AB/sampler.py" verify-pulse 2>&1); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T4b" "сфабрикованный outputValue прошёл"
assert_contains "$OUT" "РАСХОЖДЕНИЕ" "T4c: расхождение названо"

echo "test_ablation_finish: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
