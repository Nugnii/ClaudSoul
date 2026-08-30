#!/usr/bin/env bash
# test_disagreement_loop.sh — контур опровержения: producer → читатель → закрытие.
#
# Зачем. Читатель pending-записей существует с v0.4.6, писателя не было ни одного
# дня: 0 файлов disagreement-pending на 1239 в state/, и как следствие
# contradicted_count = 0 во всех 265 знаниях. Отказ был тихим — ничего не падало,
# просто счётчик умел только расти. Тест фиксирует все три звена, включая то, на
# чём контур разошёлся бы снова: писатель и читатель обязаны собирать ОДНО имя файла
# (в session-collector сосуществуют payload-sid и PPID-версия).
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTIVATOR="$HOOKS_DIR/knowledge-activator.sh"
COLLECTOR="$HOOKS_DIR/session-collector.sh"
BUMP="$HOOKS_DIR/knowledge-counter-bump.sh"
REPO_ROOT="$(cd "$HOOKS_DIR/.." && pwd)"
for f in "$ACTIVATOR" "$COLLECTOR" "$BUMP"; do
    [ -f "$f" ] || { echo "FAIL: $f not found"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: ожидалось '$expected', получено '$actual'"; fi
}
assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if grep -qF "$needle" <<< "$haystack"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: не найдено '$needle'"; fi
}

STATE="$TMP/home/.claude/hooks/state"
# Экспорт, а не аргумент каждого вызова. Повод конкретный и свежий: пока ветка
# `confirmed` не трогала каталог состояния, звать её без `CLAUDE_STATE_DIR` было
# безвредно, и шесть вызовов ниже так и написаны. Как только у ветки появилась запись
# исхода, те же вызовы начали писать фикстуры (`pattern-bump`, `pattern-form-*`) в
# БОЕВОЙ `disagreement-outcomes.jsonl` — 25 строк мусора в измерении, которое существует
# ради честности счёта. Тест обязан быть неспособен дотянуться до боевого каталога, а не
# помнить про env в каждой строке (pattern-external-test-write-teardown).
export CLAUDE_STATE_DIR="$STATE"
LESSONS="$TMP/home/.claude/global-lessons"

# $1 — slug, $2 — confidence, $3 — blocker (true/false)
make_knowledge() {
    cat > "$LESSONS/pattern-$1.md" <<KF
---
name: $1 rule
description: desc $1
type: pattern
confidence: $2
impact: 4
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-01-01
status: active
blocker: $3
domain: [devops]
situation: deploying_to_production
trigger: deploy_command
tags: [deploy, rsync, database, exclude]
---
Body.
KF
}

setup() {
    rm -rf "$TMP/home"
    mkdir -p "$LESSONS" "$STATE"
}
reset_gate() { rm -f "$STATE"/knowledge_injected_* 2>/dev/null || true; }

run_activator() {  # $1 — session_id
    printf '{"session_id":"%s","tool_name":"Bash","cwd":"/tmp/proj","tool_input":{"command":"rsync deploy database to production server"}}' "$1" | \
    env HOME="$TMP/home" CLAUDE_CODE_SESSION_ID="$1" STATE_DIR="$STATE" \
        CLAUDSOUL_ROOT="$REPO_ROOT" SKIP_MCP_FALLBACK=1 bash "$ACTIVATOR" >/dev/null 2>"$STATE/act-err"
    local rc=$?
    # Зовётся напрямую — счётчик доживает. Смерть активатора раньше проходила как
    # «pending-записи нет» в T3/T4 (D220).
    [ "$rc" -eq 0 ] || { FAIL=$((FAIL + 1)); echo "FAIL [run_activator $1]: активатор умер rc=$rc: $(tail -c 200 "$STATE/act-err" 2>/dev/null)"; }
}
run_collector() {  # $1 — session_id; печатает накопленные алерты
    printf '{"session_id":"%s","transcript_path":"","cwd":""}' "$1" | \
        STATE_DIR="$STATE" bash "$COLLECTOR" >/dev/null 2>"$STATE/coll-err" || echo "$?" >> "$STATE/coll-rc"
    cat "$STATE/pending-alerts.txt" 2>/dev/null || true
}
# run_collector зовётся через $(…) — счётчики внутри не выживают; смерть копится
# флаг-файлом и предъявляется перед итогом (D220).
PLOG() { echo "$STATE/disagreement-pending-$1.jsonl"; }
lines() { { grep -c '' "$1" 2>/dev/null || echo 0; } | tr -d ' '; }

# === T1: blocker-tier знание с confidence>=4 → pending-запись ===
setup
make_knowledge blocked 5 true
run_activator s1
assert_eq "1" "$(lines "$(PLOG s1)")" "T1a: pending-запись создана"
assert_eq "pending" "$(jq -r '.outcome' "$(PLOG s1)")" "T1b: outcome=pending"
assert_eq "pattern-blocked" "$(jq -r '.key' "$(PLOG s1)")" "T1c: ключ = имя знания"
assert_eq "5" "$(jq -r '.confidence' "$(PLOG s1)")" "T1d: confidence записан"
assert_eq "Bash" "$(jq -r '.tool' "$(PLOG s1)")" "T1e: инструмент встречи записан"

# === T2: повторное срабатывание тем же знанием → дедуп ===
reset_gate
run_activator s1
assert_eq "1" "$(lines "$(PLOG s1)")" "T2: дедуп по знанию в пределах сессии"

# === T3: знание confidence>=4, но НЕ blocker-tier → записи нет (узкий режим) ===
setup
make_knowledge loud 5 false
run_activator s3
assert_eq "0" "$([ -f "$(PLOG s3)" ] && echo 1 || echo 0)" "T3: не-blocker знание не создаёт pending"

# === T4: blocker-tier, но confidence<4 → записи нет ===
setup
make_knowledge weak 3 true
run_activator s4
assert_eq "0" "$([ -f "$(PLOG s4)" ] && echo 1 || echo 0)" "T4: confidence<4 не создаёт pending"

# === T5: имя файла у писателя и читателя совпадает (payload-sid) ===
setup
make_knowledge blocked 5 true
run_activator "sid-shared-42"
assert_eq "1" "$(lines "$(PLOG sid-shared-42)")" "T5a: писатель использует payload-sid"
OUT=$(run_collector "sid-shared-42")
assert_contains "$OUT" "⚡ 1 blocker-tier" "T5b: читатель нашёл файл писателя"

# === T6: закрытие исхода снимает алерт ===
printf '{"date":"2026-07-25T00:00:00Z","key":"pattern-blocked","outcome":"outdated_knowledge"}\n' >> "$(PLOG sid-shared-42)"
: > "$STATE/pending-alerts.txt"
OUT=$(run_collector "sid-shared-42")
if grep -qF "blocker-tier знание" <<< "$OUT"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T6]: алерт остался после закрытия исхода"
else PASS=$((PASS + 1)); fi

# === T7: два знания, одно закрыто → счётчик 1, не 0 и не 2 ===
setup
make_knowledge blocked 5 true
make_knowledge other 5 true
run_activator "sid-two"
assert_eq "2" "$(lines "$(PLOG sid-two)")" "T7a: две pending-записи"
printf '{"date":"2026-07-25T00:00:00Z","key":"pattern-blocked","outcome":"confirmed_knowledge"}\n' >> "$(PLOG sid-two)"
: > "$STATE/pending-alerts.txt"
OUT=$(run_collector "sid-two")
assert_contains "$OUT" "⚡ 1 blocker-tier" "T7b: закрытое не считается, открытое считается"

# === T15: фильтр деталей по возрасту и происхождению записи (2026-08-09) ===
# Владелец видел «16 blocker-tier без исхода» и не мог отличить долг недели от
# следа соседней сессии, начатой 20 минут назад. Хуже: детально печатались ЧУЖИЕ
# записи с готовыми командами, а по чужой сессии честного исхода не вынести —
# единственная гасящая кнопка пишет confirmed, то есть сигнал давил завышать
# счётчик (дефект D60 с другой стороны).
setup
make_knowledge mine 5 true
# alien НЕ blocker-tier: иначе активатор заведёт для него запись и в СВОЕЙ сессии,
# и «чужая» деталь напечатается законно — тест поймает собственную фикстуру.
make_knowledge alien 5 false
run_activator "sid-mine" >/dev/null 2>&1
NOW_ISO=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
# 4 дня: больше порога «залежалось» (3), но меньше DISAGREEMENT_EXPIRE_DAYS (7) —
# иначе dis_expire_old погасит запись ДО подсчёта и проверять будет нечего.
OLD_ISO=$(date -u -v-4d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '4 days ago' '+%Y-%m-%dT%H:%M:%SZ')
printf '{"date":"%s","key":"pattern-alien","outcome":"pending","confidence":5,"tool":"Bash"}\n' "$NOW_ISO" \
    > "$STATE/disagreement-pending-sid-fresh-alien.jsonl"
: > "$STATE/pending-alerts.txt"
OUT=$(run_collector "sid-mine")
assert_contains "$OUT" "в этой сессии" "T15a: своя запись названа отдельно"
assert_contains "$OUT" "в других свежих сессиях" "T15b: чужая свежая названа отдельно"
if grep -qF "pattern-alien confirmed" <<< "$OUT"; then
    FAIL=$((FAIL + 1)); echo "FAIL [T15c]: чужая свежая запись напечатана детально"
else PASS=$((PASS + 1)); fi

# чужая ЗАЛЕЖАВШАЯСЯ печатается детально — иначе долг станет невидимым
printf '{"date":"%s","key":"pattern-alien","outcome":"pending","confidence":5,"tool":"Bash"}\n' "$OLD_ISO" \
    > "$STATE/disagreement-pending-sid-stale-alien.jsonl"
rm -f "$STATE/disagreement-pending-sid-fresh-alien.jsonl"
: > "$STATE/pending-alerts.txt"
OUT=$(run_collector "sid-mine")
assert_contains "$OUT" "залежалось" "T15d: залежавшаяся чужая названа отдельно"
assert_contains "$OUT" "pattern-alien" "T15e: залежавшаяся чужая печатается детально"

# === T8: читатель без файла не падает (регрессия на смену схемы имени) ===
setup
RC=0
run_collector "sid-nofile" >/dev/null || RC=$?
assert_eq "0" "$RC" "T8: нет pending-файла → rc=0, тишина"

# === T9-T11: механический инкремент счётчиков ===
setup
make_knowledge bump 5 true
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-bump contradicted "устарело" "case-x.md" >/dev/null 2>&1
assert_eq "1" "$(grep -c '^contradicted_count: 1$' "$LESSONS/pattern-bump.md")" "T9: contradicted_count 0 → 1"
assert_eq "1" "$(grep -c 'kind: contradicted' "$LESSONS/pattern-bump.md")" "T10: запись в provenance_log"
assert_eq "1" "$(grep -c '^provenance_log:$' "$LESSONS/pattern-bump.md")" "T10a: поле провенанса создано"
assert_eq "0" "$(grep -c 'modification_history' "$LESSONS/pattern-bump.md")" "T10b: modification_history НЕ тронута — она только для перекроек правила"
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-bump confirmed >/dev/null 2>&1
assert_eq "1" "$(grep -c '^confirmed_count: 2$' "$LESSONS/pattern-bump.md")" "T11a: confirmed_count 1 → 2"
assert_eq "1" "$(grep -c "^last_confirmed: $(date '+%Y-%m-%d')$" "$LESSONS/pattern-bump.md")" "T11b: last_confirmed обновлён"

# === T12: несуществующее знание → rc=1, ничего не создано ===
RC=0
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-nope confirmed >/dev/null 2>&1 || RC=$?
assert_eq "1" "$RC" "T12: неизвестное знание → rc=1"

# === T13: третий исход «не к месту» (D60) ===
# До него принимались только confirmed|contradicted, поэтому неприменимое знание
# нечем было снять с очереди: оно печаталось каждой сессией, а единственная
# гасящая кнопка писала confirmed — механизм подталкивал завышать счётчик.
setup
make_knowledge na 5 true
printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-na","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
    > "$STATE/disagreement-pending-sid-na.jsonl"
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-na not_applicable "всплыло мимо задачи" >/dev/null 2>&1
assert_eq "1" "$(grep -c '^confirmed_count: 1$' "$LESSONS/pattern-na.md")" "T13a: confirmed_count не тронут"
assert_eq "1" "$(grep -c '^contradicted_count: 0$' "$LESSONS/pattern-na.md")" "T13b: contradicted_count не тронут"
assert_eq "0" "$(grep -c 'provenance_log' "$LESSONS/pattern-na.md")" "T13c: записи провенанса не появилось"
assert_eq "0" "$(grep -c 'modification_history' "$LESSONS/pattern-na.md")" "T13c2: истории модификаций тоже не появилось"
assert_eq "1" "$(grep -c 'not_applicable' "$STATE/disagreement-outcomes.jsonl")" "T13d: исход в durable-журнале"
assert_eq "1" "$(grep -c 'not_applicable' "$STATE/disagreement-pending-sid-na.jsonl")" "T13e: pending погашен в файле своей сессии"
RC=0
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-na not_applicable >/dev/null 2>&1 || RC=$?
assert_eq "0" "$RC" "T13f: причина необязательна"

# === T14: четвёртый исход applicable_not_followed (D62) ===
# Отдельное значение, а не «тоже мимо»: это единственная метрика разрыва
# «знание → действие», слитая с not_applicable она перестаёт быть наблюдаемой.
setup
make_knowledge anf 5 true
printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-anf","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
    > "$STATE/disagreement-pending-sid-anf.jsonl"
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-anf applicable_not_followed "знание висело в контексте и не применилось" >/dev/null 2>&1
assert_eq "1" "$(grep -c '^confirmed_count: 1$' "$LESSONS/pattern-anf.md")" "T14a: confirmed_count не тронут"
assert_eq "1" "$(grep -c '^contradicted_count: 0$' "$LESSONS/pattern-anf.md")" "T14b: contradicted_count не тронут"
assert_eq "1" "$(grep -c '"outcome":"applicable_not_followed"' "$STATE/disagreement-outcomes.jsonl")" "T14c: исход в durable-журнале своим значением"
assert_eq "0" "$(grep -c '"outcome":"not_applicable"' "$STATE/disagreement-outcomes.jsonl")" "T14d: не подменён на not_applicable"
assert_eq "1" "$(grep -c 'applicable_not_followed' "$STATE/disagreement-pending-sid-anf.jsonl")" "T14e: pending погашен тем же значением"

# === T14b: confirmed/contradicted закрывают исход так же, как остальные два ===
# Асимметрия стоила измерения. Гашение pending и запись в durable-журнал появились в D60
# вместе с `not_applicable` и достались только новым веткам; `confirmed`/`contradicted`
# остались на инструкции «агент допишет строку руками» (/learn Step 4e). Кто звал скрипт
# и полагался на него, инкрементировал счётчик знания, но в журнал не попадал, алерт не
# гасил, и через семь дней запись гасла истечением как `not_applicable`. Полный
# автоматический цикл имел ровно тот исход, который в статистике и лидирует — 81
# `not_applicable` против 54 `confirmed_knowledge` на 2026-08-26.
setup
make_knowledge sym 5 true
printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-sym","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
    > "$STATE/disagreement-pending-sid-sym.jsonl"
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-sym confirmed "сработало по делу" >/dev/null 2>&1
assert_eq "1" "$(grep -c '^confirmed_count: 2$' "$LESSONS/pattern-sym.md")" "T14b1: счётчик инкрементирован"
assert_eq "1" "$(grep -c '"outcome":"confirmed_knowledge"' "$STATE/disagreement-outcomes.jsonl")" "T14b2: исход в durable-журнале"
assert_eq "1" "$(grep -c '"outcome":"confirmed_knowledge"' "$STATE/disagreement-pending-sid-sym.jsonl")" "T14b3: pending погашен"
assert_eq "0" "$(tail -1 "$STATE/disagreement-pending-sid-sym.jsonl" | grep -c '"outcome":"pending"')" "T14b4: последняя строка по ключу — не pending"

# Опровержение — тем же путём, но своим значением: outdated_knowledge, не confirmed.
setup
make_knowledge sym2 5 true
printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-sym2","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
    > "$STATE/disagreement-pending-sid-sym2.jsonl"
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-sym2 contradicted "разошлось с делом" >/dev/null 2>&1
assert_eq "1" "$(grep -c '^contradicted_count: 1$' "$LESSONS/pattern-sym2.md")" "T14b5: contradicted_count инкрементирован"
assert_eq "1" "$(grep -c '"outcome":"outdated_knowledge"' "$STATE/disagreement-outcomes.jsonl")" "T14b6: в журнале outdated_knowledge, не confirmed"
assert_eq "1" "$(grep -c 'outdated_knowledge' "$STATE/disagreement-pending-sid-sym2.jsonl")" "T14b7: pending погашен значением опровержения"

# === T14c: уже закрытая запись не гасится повторно (D85) ===
# Гашение брало любую строку `pending` в файле, включая перекрытую более поздним исходом,
# — а очередь (`dis_scan_open`) считает состояние ключа по ПОСЛЕДНЕЙ строке. Расхождение
# двух правил давало растущие файлы и лживый отчёт: живой прогон 2026-08-26 сообщил
# «погашено записей: 10» при нуле таких записей в активной очереди.
setup
make_knowledge closed 5 true
{
    printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-closed","outcome":"pending","confidence":5,"tool":"Bash"}\n'
    printf '{"date":"2026-01-02T00:00:00Z","key":"pattern-closed","outcome":"not_applicable"}\n'
} > "$STATE/disagreement-pending-sid-closed.jsonl"
BEFORE=$(grep -c '' "$STATE/disagreement-pending-sid-closed.jsonl")
OUT=$(LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-closed confirmed "второй вердикт" 2>&1)
AFTER=$(grep -c '' "$STATE/disagreement-pending-sid-closed.jsonl")
assert_eq "$BEFORE" "$AFTER" "T14c1: закрытая запись не получает второй строки гашения"
assert_eq "1" "$(printf '%s' "$OUT" | grep -c 'погашено записей: 0')" "T14c2: отчёт называет ноль, а не выдуманное число"
assert_eq "1" "$(grep -c '^confirmed_count: 2$' "$LESSONS/pattern-closed.md")" "T14c3: счётчик знания при этом инкрементирован"

# === T14d: DIS_SESSION сужает гашение до одной сессии (D85) ===
# Вердикт в сессии Y ничего не говорит об исходе в сессии X. Живой повод: у
# `pattern-defensive-misdiagnosis` было 8 открытых записей из восьми разных сессий, и одно
# суждение закрывало все восемь. Без переменной поведение прежнее — это проверяется тоже,
# иначе правка тихо поменяла бы умолчание для существующих вызовов.
setup
make_knowledge multi 5 true
for sid in one two three; do
    printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-multi","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
        > "$STATE/disagreement-pending-$sid.jsonl"
done
DIS_SESSION=two LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-multi confirmed "судил об этой сессии" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'confirmed_knowledge' "$STATE/disagreement-pending-two.jsonl")" "T14d1: названная сессия погашена"
assert_eq "0" "$(grep -c 'confirmed_knowledge' "$STATE/disagreement-pending-one.jsonl")" "T14d2: соседняя сессия не тронута"
assert_eq "0" "$(grep -c 'confirmed_knowledge' "$STATE/disagreement-pending-three.jsonl")" "T14d3: и вторая соседняя тоже"

# Без переменной — прежнее поведение: гасятся все открытые записи ключа.
setup
make_knowledge multi2 5 true
for sid in one two; do
    printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-multi2","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
        > "$STATE/disagreement-pending-$sid.jsonl"
done
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-multi2 confirmed "без сессии" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'confirmed_knowledge' "$STATE/disagreement-pending-one.jsonl")" "T14d4: без DIS_SESSION умолчание прежнее (1/2)"
assert_eq "1" "$(grep -c 'confirmed_knowledge' "$STATE/disagreement-pending-two.jsonl")" "T14d5: без DIS_SESSION умолчание прежнее (2/2)"

# Несуществующая сессия — не падаем и ничего не гасим.
setup
make_knowledge multi3 5 true
printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-multi3","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
    > "$STATE/disagreement-pending-real.jsonl"
RC=0
DIS_SESSION=nosuchsession LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-multi3 confirmed "мимо" >/dev/null 2>&1 || RC=$?
assert_eq "0" "$RC" "T14d6: несуществующая сессия не роняет скрипт"
assert_eq "0" "$(grep -c 'confirmed_knowledge' "$STATE/disagreement-pending-real.jsonl")" "T14d7: чужая запись при этом не погашена"

# === T14e: провенанс запоминает сессию (D81) ===
# Без сессии независимость подтверждений непроверяема машинно: замер 2026-08-26 дал
# 234 заявленных подтверждения против 118 записанных поводов, и даже записанные не
# позволяли отличить пять наблюдений от пяти проявлений одного случая.
setup
make_knowledge withsid 5 true
CLAUDE_CODE_SESSION_ID="sess-abc-123" LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" \
    bash "$BUMP" pattern-withsid confirmed "повод" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'session: sess-abc-123' "$LESSONS/pattern-withsid.md")" "T14e1: сессия записана в provenance_log"

# Без переменной окружения строки быть не должно — пустое поле хуже отсутствующего.
setup
make_knowledge nosid 5 true
env -u CLAUDE_CODE_SESSION_ID LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" \
    bash "$BUMP" pattern-nosid confirmed "повод" >/dev/null 2>&1
assert_eq "0" "$(grep -c 'session:' "$LESSONS/pattern-nosid.md")" "T14e2: без сессии поле не появляется пустым"

# === T14f: DIS_SESSION и защита от повторного гашения действуют во ВСЕХ ветках ===
# Обе правки D85 сперва прошли мимо `not_applicable`/`applicable_not_followed`: они чинили
# `dis_close_outcome`, а в этой ветке лежала своя копия цикла. Живой случай 2026-08-26 —
# вызов с `DIS_SESSION` отчитался «погашено записей: 37» вместо одной.
setup
make_knowledge branch 5 true
for sid in alpha beta; do
    printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-branch","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
        > "$STATE/disagreement-pending-$sid.jsonl"
done
DIS_SESSION=alpha LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" \
    bash "$BUMP" pattern-branch applicable_not_followed "висело и не применилось" >/dev/null 2>&1
assert_eq "1" "$(grep -c 'applicable_not_followed' "$STATE/disagreement-pending-alpha.jsonl")" "T14f1: названная сессия погашена и в этой ветке"
assert_eq "0" "$(grep -c 'applicable_not_followed' "$STATE/disagreement-pending-beta.jsonl")" "T14f2: соседняя сессия не тронута"

# И повторное гашение уже закрытой записи — тоже во всех ветках.
setup
make_knowledge branch2 5 true
{
    printf '{"date":"2026-01-01T00:00:00Z","key":"pattern-branch2","outcome":"pending","confidence":5,"tool":"Bash"}\n'
    printf '{"date":"2026-01-02T00:00:00Z","key":"pattern-branch2","outcome":"confirmed_knowledge"}\n'
} > "$STATE/disagreement-pending-closed.jsonl"
BEFORE=$(grep -c '' "$STATE/disagreement-pending-closed.jsonl")
LESSONS_DIR="$LESSONS" CLAUDE_STATE_DIR="$STATE" bash "$BUMP" pattern-branch2 not_applicable "мимо" >/dev/null 2>&1
assert_eq "$BEFORE" "$(grep -c '' "$STATE/disagreement-pending-closed.jsonl")" "T14f3: закрытая запись не гасится повторно и в этой ветке"

# === T15: три формы поля provenance_log + неприкосновенность modification_history ===
# Скрипт обрабатывает поле в трёх состояниях (отсутствует / `[]` / блочный список), но до
# 2026-08-11 тестами была покрыта только первая: фикстура make_knowledge поля не содержит.
# Две непокрытые формы встречаются в 38 реальных знаниях — правка awk-блока ломала бы их
# молча, при зелёных тестах. Заодно держим границу полей: подтверждение не должно попадать
# в историю перекроек, ради чего поля и разнесли (см. scripts/split-provenance-log.py).
setup

# форма 1: поля нет вовсе
make_knowledge form-absent 5 true
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-form-absent confirmed "форма absent" >/dev/null 2>&1
assert_eq "1" "$(grep -c '^provenance_log:$' "$LESSONS/pattern-form-absent.md")" "T15a: поле создано, когда его не было"
assert_eq "1" "$(grep -c 'reason: "форма absent"' "$LESSONS/pattern-form-absent.md")" "T15b: запись на месте"

# форма 2: `provenance_log: []` — должен развернуться в блок, соседнее поле уцелеть
make_knowledge form-empty 5 true
printf 'provenance_log: []\nfragile: false\n' > "$TMP/ins"
awk '/^---$/{n++} n==2 && !done {while ((getline l < "'"$TMP/ins"'") > 0) print l; done=1} {print}' \
    "$LESSONS/pattern-form-empty.md" > "$TMP/f2" && mv "$TMP/f2" "$LESSONS/pattern-form-empty.md"
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-form-empty confirmed "форма empty" >/dev/null 2>&1
assert_eq "0" "$(grep -c '^provenance_log: \[\]$' "$LESSONS/pattern-form-empty.md")" "T15c: пустой список развёрнут в блок"
assert_eq "1" "$(grep -c 'reason: "форма empty"' "$LESSONS/pattern-form-empty.md")" "T15d: запись добавлена"
assert_eq "1" "$(grep -c '^fragile: false$' "$LESSONS/pattern-form-empty.md")" "T15e: соседнее поле не затёрто"

# форма 3: непустой блок + отдельная modification_history с перекройкой правила
make_knowledge form-block 5 true
printf 'modification_history:\n  - date: 2026-01-01\n    kind: narrowed\n    reason: "сузили scope"\nprovenance_log:\n  - date: 2026-02-02\n    kind: reinforced\n    reason: "прошлое подтверждение"\n' > "$TMP/ins"
awk '/^---$/{n++} n==2 && !done {while ((getline l < "'"$TMP/ins"'") > 0) print l; done=1} {print}' \
    "$LESSONS/pattern-form-block.md" > "$TMP/f3" && mv "$TMP/f3" "$LESSONS/pattern-form-block.md"
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-form-block confirmed "форма block" >/dev/null 2>&1
assert_eq "2" "$(grep -c 'kind: reinforced' "$LESSONS/pattern-form-block.md")" "T15f: запись дописана в конец непустого блока"
assert_eq "1" "$(grep -c 'reason: "прошлое подтверждение"' "$LESSONS/pattern-form-block.md")" "T15g: старая запись не потеряна"
assert_eq "1" "$(grep -c 'kind: narrowed' "$LESSONS/pattern-form-block.md")" "T15h: перекройка правила в истории не тронута"
assert_eq "1" "$(grep -c '^modification_history:$' "$LESSONS/pattern-form-block.md")" "T15i: история осталась отдельным полем"

# ============================================================================
# v1.12.0 — disagreement-lib: кросс-сессионный обзор, автогашение, второй продюсер
#
# Разрыв, который эти тесты держат закрытым: алерт считался кросс-сессионным, а
# закрытие — сессионным. Агент видел «N знаний без исхода», шёл в /learn, тот читал
# файл СВОЕЙ сессии, где записей прошлых сессий нет. Закрыть было нечего и нечем;
# из 5 живых записей закрылась одна — та, что успела внутри своей же сессии.
# ============================================================================
DIS_LIB="$HOOKS_DIR/disagreement-lib.sh"
if [ -f "$DIS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$DIS_LIB"
    DS="$TMP/dis-state"
    mkdir -p "$DS"

    # Две разные сессии, в каждой по открытой записи.
    printf '{"date":"2026-07-01T10:00:00Z","key":"pattern-a","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
        > "$DS/disagreement-pending-sess1.jsonl"
    printf '{"date":"2026-07-02T10:00:00Z","key":"pattern-b","outcome":"pending","confidence":4,"tool":"Edit"}\n{"date":"2026-07-02T10:05:00Z","key":"pattern-b","outcome":"confirmed_knowledge"}\n' \
        > "$DS/disagreement-pending-sess2.jsonl"

    # === T13: обзор идёт по ВСЕМ сессиям, а не по текущей ===
    OPEN=$(dis_scan_open "$DS")
    assert_eq "1" "$(printf '%s\n' "$OPEN" | grep -c 'pattern-a')" "T13: открытая запись чужой сессии видна"
    assert_eq "0" "$(printf '%s\n' "$OPEN" | grep -c 'pattern-b')" "T13b: закрытая запись не считается открытой"

    # === T14: статистика closed/expired/open ===
    read -r C E O <<EOF
$(dis_stats "$DS")
EOF
    assert_eq "1" "$C" "T14: closed=1"
    assert_eq "0" "$E" "T14: expired=0"
    assert_eq "1" "$O" "T14: open=1"

    # === T15: автогашение просроченных, счётчики знаний НЕ трогаются ===
    BEFORE_CNT=$(grep -c '^contradicted_count:' "$LESSONS/pattern-bump.md" 2>/dev/null || echo 0)
    BEFORE_VAL=$(grep '^contradicted_count:' "$LESSONS/pattern-bump.md" 2>/dev/null || echo "")
    EXPIRED=$(dis_expire_old 1 "$DS")
    assert_eq "1" "$EXPIRED" "T15: одна просроченная запись погашена"
    read -r C2 E2 O2 <<EOF
$(dis_stats "$DS")
EOF
    assert_eq "1" "$E2" "T15b: expired=1"
    assert_eq "0" "$O2" "T15c: открытых не осталось"
    assert_eq "$BEFORE_VAL" "$(grep '^contradicted_count:' "$LESSONS/pattern-bump.md" 2>/dev/null || echo "")" \
        "T15d: истечение НЕ трогает счётчики знания"

    # === T16: свежая запись не гасится ===
    printf '{"date":"%s","key":"pattern-fresh","outcome":"pending","confidence":5,"tool":"Bash"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DS/disagreement-pending-sess3.jsonl"
    assert_eq "0" "$(dis_expire_old 7 "$DS")" "T16: свежая запись переживает гашение"

    # === T17: второй продюсер — поправка в окне после видимого инжекта ===
    HS="$TMP/harvest-state"; mkdir -p "$HS"
    HSID="hsid"
    {
        printf '{"date":"2026-07-28T10:00:00Z","file":"pattern-hit.md","confidence":4,"injected":true,"session_id":"%s","rank":1}\n' "$HSID"
        printf '{"date":"2026-07-28T10:00:00Z","file":"pattern-rank5.md","confidence":3,"injected":false,"session_id":"%s","rank":5}\n' "$HSID"
        printf '{"date":"2026-07-28T04:00:00Z","file":"pattern-stale.md","confidence":5,"injected":true,"session_id":"%s","rank":2}\n' "$HSID"
        printf '{"date":"2026-07-28T10:00:00Z","file":"pattern-other.md","confidence":5,"injected":true,"session_id":"other","rank":1}\n'
    } > "$HS/injection-log.jsonl"
    printf '{"date":"2026-07-28T10:10:00Z","hash":"h1","snippet":"не то"}\n' > "$HS/correction-fired-$HSID.jsonl"

    MADE=$(dis_harvest_corrections "$HSID" "$HS" 30 3)
    HARVEST=$(cat "$HS/disagreement-pending-$HSID.jsonl" 2>/dev/null || true)
    assert_eq "1" "$MADE" "T17: создан один кандидат"
    assert_contains "$HARVEST" '"key":"pattern-hit"' "T17b: инжект в окне стал кандидатом"
    assert_contains "$HARVEST" '"class":"correction_after_injection"' "T17c: класс проставлен"
    # Ранги 4-6 агент не видел — реакцией на них поправка быть не может.
    assert_eq "0" "$(printf '%s' "$HARVEST" | grep -c 'pattern-rank5')" "T17d: невидимый ранг пропущен"
    # Инжект за 6 часов до поправки — вне окна.
    assert_eq "0" "$(printf '%s' "$HARVEST" | grep -c 'pattern-stale')" "T17e: инжект вне окна пропущен"
    # Чужая сессия не должна протекать.
    assert_eq "0" "$(printf '%s' "$HARVEST" | grep -c 'pattern-other')" "T17f: чужая сессия не протекает"

    # === T18: повторный прогон не плодит дубли ===
    assert_eq "0" "$(dis_harvest_corrections "$HSID" "$HS" 30 3)" "T18: повторный сбор не дублирует"

    # === T19: две шкалы времени — локальная без Z и UTC с Z ===
    # injection-log до v1.12.0 писал локальное время без суффикса; смешение шкал
    # сдвинуло бы окно на смещение пояса и молча испортило бы выборку.
    Z_EPOCH=$(_dis_epoch "2026-07-28T10:00:00Z")
    LOCAL_EPOCH=$(_dis_epoch "2026-07-28T10:00:00")
    assert_eq "0" "$([ "$Z_EPOCH" -gt 0 ] && echo 0 || echo 1)" "T19: UTC-время разобрано"
    assert_eq "0" "$([ "$LOCAL_EPOCH" -gt 0 ] && echo 0 || echo 1)" "T19b: локальное время разобрано"
    OFFSET_S=$(( LOCAL_EPOCH - Z_EPOCH ))
    EXPECTED_OFFSET=$(( -1 * $(date +%z | awk '{h=substr($0,2,2); m=substr($0,4,2); s=(h*3600+m*60); print ($0 ~ /^-/ ? -s : s)}') ))
    assert_eq "$EXPECTED_OFFSET" "$OFFSET_S" "T19c: шкалы различаются ровно на смещение пояса"
fi

# ============================================================================
# T20: четвёртый исход — знание было уместно и не применено
# ============================================================================
# Трёх исходов не хватало ровно на случай, ради которого проект существует: правило
# о поведении агента бывает не только верным, неверным или посторонним — оно бывает
# УМЕСТНЫМ И ПРОИГНОРИРОВАННЫМ. Раньше такой случай приходилось записывать как
# `not_applicable` («не относилось»), что прямая неправда, либо как `confirmed`
# («применялось»), что завышает счётчик. Первый живой случай: две долгие проверки
# запущены без ориентира при знании, висевшем в контексте.
_T20="$TMP/t20"; mkdir -p "$_T20"
printf '{"date":"2026-08-01T00:00:00Z","key":"k1","outcome":"pending","confidence":2}\n' \
    > "$_T20/disagreement-pending-s20.jsonl"
printf '{"date":"2026-08-01T00:01:00Z","key":"k1","outcome":"applicable_not_followed"}\n' \
    >> "$_T20/disagreement-pending-s20.jsonl"
# T20a/T20b проходят и против прежней версии библиотеки: закрытие срабатывает при ЛЮБОМ
# значении исхода, и это свойство здесь просто закрепляется. Новизну проверяют T20c-T20e —
# словарь и прибор; против HEAD падают именно они.
# T20a: запись с четвёртым исходом ЗАКРЫВАЕТ заявку — иначе алерт горел бы вечно
_st=$(dis_stats "$_T20" 2>/dev/null)
case "$_st" in "1 0 0") PASS=$((PASS+1)) ;; *) FAIL=$((FAIL+1)); echo "FAIL [T20a]: заявка не закрыта, dis_stats=[$_st]" ;; esac
# T20b: открытых не осталось
_open=$(dis_scan_open "$_T20" 2>/dev/null | grep -c '.' || true)
[ "${_open:-0}" -eq 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T20b]: осталось открытых: $_open"; }
# T20c: словарь исходов описан в библиотеке — иначе четвёртое значение останется устной договорённостью
grep -q 'applicable_not_followed' "$DIS_LIB" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T20c]: четвёртый исход не описан в disagreement-lib"; }
# T20d: у него есть ПРИБОР — иначе главный вопрос проекта снова без измерения
grep -q 'applicable_not_followed' "$HOOKS_DIR/metrics-collector.sh" && PASS=$((PASS+1)) \
    || { FAIL=$((FAIL+1)); echo "FAIL [T20d]: пропуски не считает metrics-collector"; }
# T20f: исход не считается ДВАЖДЫ. `/learn` пишет его и в посессионный
# `disagreement-pending-*`, и в durable `disagreement-outcomes`; счёт по обоим удваивал
# каждую запись текущей сессии. Обнаружено на живой метрике: записал один случай — увидел
# два. Соседний счётчик опровержений болел тем же и починен вместе.
if grep -qE 'disagreement-outcomes.*disagreement-pending' "$HOOKS_DIR/metrics-collector.sh"; then
    FAIL=$((FAIL+1)); echo "FAIL [T20f]: исход считается по обоим файлам — записи текущей сессии удвоятся"
else PASS=$((PASS+1)); fi

# T20e: счётчики знания НЕ трогаются — пропуск не подтверждает и не опровергает
grep -q 'applicable_not_followed.*confirmed++\|confirmed++.*applicable_not_followed' "$DIS_LIB" \
    && { FAIL=$((FAIL+1)); echo "FAIL [T20e]: пропуск инкрементит счётчик подтверждений"; } \
    || PASS=$((PASS+1))


if [ -f "$STATE/coll-rc" ]; then
    FAIL=$((FAIL + 1))
    echo "FAIL [run_collector: коллектор падал, rc: $(tr '\n' ' ' < "$STATE/coll-rc"), stderr: $(tail -c 200 "$STATE/coll-err" 2>/dev/null)]"
fi

echo ""
echo "disagreement-loop tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
