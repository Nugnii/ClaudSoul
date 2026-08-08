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
    if printf '%s' "$haystack" | grep -qF "$needle"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$label]: не найдено '$needle'"; fi
}

STATE="$TMP/home/.claude/hooks/state"
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
        CLAUDSOUL_ROOT="$REPO_ROOT" SKIP_MCP_FALLBACK=1 bash "$ACTIVATOR" >/dev/null 2>&1
}
run_collector() {  # $1 — session_id; печатает накопленные алерты
    printf '{"session_id":"%s","transcript_path":"","cwd":""}' "$1" | \
        STATE_DIR="$STATE" bash "$COLLECTOR" >/dev/null 2>&1
    cat "$STATE/pending-alerts.txt" 2>/dev/null || true
}
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
if printf '%s' "$OUT" | grep -qF "blocker-tier знание"; then
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
assert_eq "1" "$(grep -c 'kind: contradicted' "$LESSONS/pattern-bump.md")" "T10: запись в modification_history"
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-bump confirmed >/dev/null 2>&1
assert_eq "1" "$(grep -c '^confirmed_count: 2$' "$LESSONS/pattern-bump.md")" "T11a: confirmed_count 1 → 2"
assert_eq "1" "$(grep -c "^last_confirmed: $(date '+%Y-%m-%d')$" "$LESSONS/pattern-bump.md")" "T11b: last_confirmed обновлён"

# === T12: несуществующее знание → rc=1, ничего не создано ===
RC=0
LESSONS_DIR="$LESSONS" bash "$BUMP" pattern-nope confirmed >/dev/null 2>&1 || RC=$?
assert_eq "1" "$RC" "T12: неизвестное знание → rc=1"

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


echo ""
echo "disagreement-loop tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
