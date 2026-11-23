#!/usr/bin/env bash
# СУДИТ: hooks/backfill-compliance.sh
# test_backfill_compliance.sh — восстановление зависимой переменной из транскриптов.
#
# Зачем тест жёсткий: на выходе этого скрипта строятся ВСЕ последующие утверждения
# о том, меняет ли правило поведение. Ошибка парсера здесь не падает, а тихо
# производит правдоподобные числа — самый дорогой класс отказа в проекте.
# Отдельно фиксируем три реальные грабли, пойманные при разработке: каталог,
# начинающийся с «-», дубли attachment на один toolUseID, битая строка в JSONL.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ORCH="$HOOKS_DIR/backfill-compliance.sh"
WORKER="$HOOKS_DIR/lib/backfill-compliance-one.py"
[ -f "$ORCH" ] || { echo "FAIL: $ORCH not found"; exit 1; }
[ -f "$WORKER" ] || { echo "FAIL: $WORKER not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }

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
    if grep -qF "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2'"; fi
}

# --- конструктор синтетического транскрипта ---
T=""
reset_t() { T="$TMP/t.jsonl"; : > "$T"; }
edit() {  # $1 — file_path, $2 — tool_use id, [$3 — tool name]
    jq -cn --arg fp "$1" --arg id "$2" --arg n "${3:-Edit}" \
      '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",
        message:{role:"assistant",content:[{type:"tool_use",name:$n,id:$id,input:{file_path:$fp}}]}}' >> "$T"
}
read_file() {  # $1 — file_path, [$2 — offset]
    if [ -n "${2:-}" ]; then
        jq -cn --arg fp "$1" --argjson off "$2" \
          '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",
            message:{role:"assistant",content:[{type:"tool_use",name:"Read",id:"r",input:{file_path:$fp,offset:$off,limit:20}}]}}' >> "$T"
    else
        jq -cn --arg fp "$1" \
          '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",
            message:{role:"assistant",content:[{type:"tool_use",name:"Read",id:"r",input:{file_path:$fp}}]}}' >> "$T"
    fi
}
marker() {  # $1 — текст, $2 — toolUseID
    jq -cn --arg txt "$1" --arg tu "$2" \
      '{type:"attachment",timestamp:"2026-07-01T00:00:00Z",
        attachment:{type:"hook_additional_context",hookName:"PreToolUse:Edit",toolUseID:$tu,content:[$txt]}}' >> "$T"
}
turn() {  # $1 — текст ответа агента
    jq -cn --arg tx "$1" \
      '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",
        message:{role:"assistant",content:[{type:"text",text:$tx}]}}' >> "$T"
}
run_worker() { python3 "$WORKER" "$T" "$@" 2>/dev/null; }

# === T1: нет файла → пусто, rc=1 ===
# До D1246 здесь стоял rc=0: «аргумент не файл» и «наблюдений нет» шли одним каналом, и реплей не видел отказа воркера.
OUT=$(python3 "$WORKER" "$TMP/нет-такого.jsonl" 2>/dev/null); RC=$?
assert_eq "1" "$RC" "T1a: несуществующий транскрипт → rc=1 (отказ, а не «наблюдений нет»)"
assert_eq "" "$OUT" "T1b: и пустой вывод"

# === T2: маркер + перечитывание целиком → compliant ===
reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/CHANGELOG.md" "t1"
read_file "/p/CHANGELOG.md"
edit "/p/CHANGELOG.md" "t2"
R=$(run_worker --classes A)
assert_eq "treated" "$(printf '%s' "$R" | jq -r 'select(.cls=="A").arm')" "T2a: arm=treated"
assert_eq "FRESH" "$(printf '%s' "$R" | jq -r 'select(.cls=="A").exposure')" "T2b: exposure=FRESH"
assert_eq "true" "$(printf '%s' "$R" | jq -r 'select(.cls=="A").v_main')" "T2c: v_main=true"
assert_eq "compliant" "$(printf '%s' "$R" | jq -r 'select(.cls=="A").outcome')" "T2d: outcome=compliant"

# === T3: тот же случай без перечитывания → violated ===
reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/CHANGELOG.md" "t1"
edit "/p/CHANGELOG.md" "t2"
assert_eq "violated" "$(run_worker --classes A | jq -r '.outcome')" "T3: без чтения → violated"

# === T4: три правки → два интервала, FRESH и STALE ===
reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/PLAN.md" "t1"; edit "/p/PLAN.md" "t2"; edit "/p/PLAN.md" "t3"
R=$(run_worker --classes A)
assert_eq "2" "$(printf '%s' "$R" | jq -s 'length')" "T4a: два интервала"
assert_eq "FRESH STALE" "$(printf '%s' "$R" | jq -r '.exposure' | tr '\n' ' ' | sed 's/ $//')" "T4b: FRESH затем STALE"

# === T5: файл не из списка сигнала → placebo ===
reset_t
edit "/p/notes.md" "t1"; edit "/p/notes.md" "t2"
assert_eq "placebo" "$(run_worker --classes A | jq -r '.arm')" "T5: placebo"

# === T6: имя матчит, маркера нет → treated_unknown, НЕ placebo ===
reset_t
edit "/p/PLAN.md" "t1"; edit "/p/PLAN.md" "t2"
assert_eq "treated_unknown" "$(run_worker --classes A | jq -r '.arm')" "T6: treated_unknown отделён от placebo"

# === T7: частичное чтение → loose да, main нет, strict нет ===
reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/README.md" "t1"
read_file "/p/README.md" 10
edit "/p/README.md" "t2"
R=$(run_worker --classes A)
assert_eq "true"  "$(printf '%s' "$R" | jq -r '.v_loose')"  "T7a: v_loose=true"
assert_eq "false" "$(printf '%s' "$R" | jq -r '.v_main')"   "T7b: v_main=false"
assert_eq "false" "$(printf '%s' "$R" | jq -r '.v_strict')" "T7c: v_strict=false"

# === T8: класс B — расстояние от инжекта ===
reset_t
marker "📚 Relevant knowledge from previous sessions:
1. [principle-verify-before-acting] (confidence:5, impact:4): x" "k1"
read_file "/p/a.md"
edit "/p/a.md" "e1"
edit "/p/a.md" "e2"
R=$(run_worker --classes B)
assert_eq "1 2" "$(printf '%s' "$R" | jq -r '.dist' | tr '\n' ' ' | sed 's/ $//')" "T8a: dist 1 затем 2"
assert_eq "compliant violated" "$(printf '%s' "$R" | jq -r '.outcome' | tr '\n' ' ' | sed 's/ $//')" "T8b: исходы"
assert_contains "$(printf '%s' "$R" | jq -r '.kn_ids[]' | head -1)" "principle-verify-before-acting" "T8c: id знания извлечён"

# === T9: класс C — негативный контроль ===
reset_t
marker "🔤 Output language check: в предыдущем ответе смешение" "c1"
turn "тут был коммit и dev-БД"
R=$(run_worker --classes C)
assert_eq "true" "$(printf '%s' "$R" | jq -r '.warned')" "T9a: ход помечен как warned"
assert_eq "1" "$(printf '%s' "$R" | jq -r '.tokens_total')" "T9b: композит не считается нарушением"
assert_eq "1" "$(printf '%s' "$R" | jq -r '.tokens_intraword')" "T9c: внутрисловное считается"

# === T9d-T9f: род дефекта B — отказ ДЕТЕКТОРА отличается от чистого хода ===
# Пустой список токенов означает «нарушений в ходе нет» и уходит в строку свидетельством
# (outcome=compliant, tokens_total=0). Тот же пустой список выдавался, когда детектор
# УПАЛ: отрицательный контроль наполнялся нулями в ОБОИХ плечах и отвечал «маркер не
# влияет» — неотличимо от настоящего результата опыта. Теперь отказ — отдельный исход.
cat > "$TMP/broken-detect.py" <<'PYD'
def main():
    raise RuntimeError("детектор сломан")
PYD
reset_t
marker "🔤 Output language check: в предыдущем ответе смешение" "c1"
turn "тут был коммit и dev-БД"
R=$(COMPLIANCE_LANG_DETECT="$TMP/broken-detect.py" run_worker --classes C)
assert_eq "null" "$(printf '%s' "$R" | jq -r '.outcome')" "T9d: отказ детектора не выдаётся за compliant"
assert_eq "detector_failed" "$(printf '%s' "$R" | jq -r '.na_reason')" "T9e: причина отказа названа"
assert_eq "null" "$(printf '%s' "$R" | jq -r '.tokens_total')" "T9f: счёт токенов не выдуман нулём"

# === T10: битая строка посреди транскрипта не обрывает разбор ===
reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/PLAN.md" "t1"
echo '{"type":"assistant" БИТАЯ СТРОКА' >> "$T"
edit "/p/PLAN.md" "t2"
assert_eq "1" "$(run_worker --classes A | jq -s 'length')" "T10: битая строка пропущена, интервал найден"

# === T11: content строкой вместо массива, role на верхнем уровне ===
reset_t
edit "/p/PLAN.md" "t1"
echo '{"type":"assistant","role":"assistant","content":"плоская строка","timestamp":"2026-07-01T00:00:00Z"}' >> "$T"
edit "/p/PLAN.md" "t2"
assert_eq "1" "$(run_worker --classes A | jq -s 'length')" "T11: смешанные формы content не роняют"

# === T12: дубли attachment на один toolUseID → одно событие ===
reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/PLAN.md" "t1"
assert_eq "1" "$(run_worker --events | grep -c '')" "T12: дедуп по toolUseID"

# === T13: каталог, начинающийся с дефиса (реальная грабля) ===
mkdir -p "$TMP/projects/-Dash-Proj"
cp "$T" "$TMP/projects/-Dash-Proj/sess.jsonl"
OUT=$(python3 "$WORKER" "$TMP/projects/-Dash-Proj/sess.jsonl" --events 2>/dev/null)
assert_eq "1" "$(printf '%s' "$OUT" | grep -c '')" "T13: путь с ведущим дефисом обработан"

# === T14-T16: оркестратор ===
OUT=$(BACKFILL_PROJECTS_DIR="$TMP/projects" COMPLIANCE_OUT="$TMP/out.jsonl" \
      bash "$ORCH" --dry-run 2>&1)
assert_contains "$OUT" "транскриптов: 1" "T14a: dry-run считает транскрипты"
assert_eq "0" "$([ -f "$TMP/out.jsonl" ] && echo 1 || echo 0)" "T14b: dry-run ничего не пишет"

reset_t
marker "🛑 Blocker: long_lived_markdown_doc_edit" "t1"
edit "/p/PLAN.md" "t1"; read_file "/p/PLAN.md"; edit "/p/PLAN.md" "t2"
cp "$T" "$TMP/projects/-Dash-Proj/sess.jsonl"
OUT=$(BACKFILL_PROJECTS_DIR="$TMP/projects" COMPLIANCE_OUT="$TMP/out.jsonl" \
      bash "$ORCH" 2>&1)
assert_contains "$OUT" "наблюдений:" "T15a: полный прогон отработал"
# «Все строки валидны» истинно тождественно при нуле строк — и не только при нуле.
# Чем это ложно: 7 сентября 2026 в оркестратор внесено `sed 's/.*/{}/'` на сборе выхода
# (одна замена), после которого out.jsonl наполнялся пустыми объектами вместо наблюдений;
# каждая строка оставалась валидным JSON, и весь файл дал 35/35 passed. Вариант с нулём
# строк ловился не этой ногой, а соседней (T16b требует непустой файл под бэкап) — то есть
# случайно. Контроль привязан к ВЕЛИЧИНЕ: собранное обязано содержать то самое наблюдение,
# ради которого построена фикстура — интервал класса A по /p/PLAN.md с исходом compliant.
BAD=0; OBS_A=0
while IFS= read -r l; do
    [ -z "$l" ] && continue
    printf '%s' "$l" | jq -e . >/dev/null 2>&1 || { BAD=$((BAD+1)); continue; }
    printf '%s' "$l" | jq -e 'select(.cls=="A" and .file=="/p/PLAN.md" and .outcome=="compliant")' \
        >/dev/null 2>&1 && OBS_A=$((OBS_A+1))
done < "$TMP/out.jsonl"
assert_eq "0" "$BAD" "T15b: каждая строка выхода — валидный JSON"
assert_eq "1" "$OBS_A" "T15c: наблюдение фикстуры (класс A, /p/PLAN.md, compliant) действительно собрано"

# бэкап предыдущего прогона вместо дописывания
BACKFILL_PROJECTS_DIR="$TMP/projects" COMPLIANCE_OUT="$TMP/out.jsonl" bash "$ORCH" >/dev/null 2>&1; RC=$?
assert_eq "0" "$RC" "T16a: повторный прогон rc=0 (бэкап делается рано — смерть после него была невидима, D220)"
assert_eq "1" "$(ls "$TMP"/out.jsonl.bak.* 2>/dev/null | grep -c '')" "T16b: предыдущий выход забэкаплен"

# === T17: отказ детектора виден и в отчёте, а не растворён в среднем ===
printf '%s\n' \
  '{"cls":"C","exposure":"warned","tokens_total":2,"tokens_intraword":1,"outcome":"violated","na_reason":null}' \
  '{"cls":"C","exposure":"warned","tokens_total":null,"tokens_intraword":null,"outcome":null,"na_reason":"detector_failed"}' \
  > "$TMP/report.jsonl"
ROUT=$(COMPLIANCE_OUT="$TMP/report.jsonl" bash "$ORCH" --report 2>&1)
assert_contains "$ROUT" "не изм." "T17a: колонка непрочитанного есть в отчёте класса C"
assert_eq "1 1" "$(printf '%s\n' "$ROUT" | awk '$1=="warned"{print $2" "$5}')" \
    "T17b: измеренных 1, неизмеренных 1 — отказ не влился в число ходов"

# --- L: режим --live читает живой журнал реакций (D383, корень R2) ---
LS="$TMP/live"; mkdir -p "$LS/a" "$LS/b" "$LS/c"
SA="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"; SB="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
printf '{"date":"2026-09-12T10:00:00Z","signal":"x"}\n' > "$LS/a/blocker-fired-$SA.jsonl"
printf '{"date":"2026-09-12T10:00:00Z","signal":"y"}\n' > "$LS/a/blocker-fired-$SB.jsonl"
printf '{"ts":"2026-09-12T10:00:01Z","sid":"%s","tool":"Bash","file":"","after":"blocker"}\n{"ts":"2026-09-12T10:00:02Z","sid":"%s","tool":"Edit","file":"x","after":"both"}\nмусор\n' "$SA" "$SA" > "$LS/a/response-$SA.jsonl"
OUT=$(STATE_DIR="$LS/a" bash "$ORCH" --live 2>&1); RC=$?
assert_eq "0" "$RC" "L1: реакции записаны — код 0"
assert_contains "$OUT" "сессий со стимулом блокера: 2, из них с записанной реакцией: 1" "L1b: покрытие названо числом"
assert_contains "$OUT" "записей реакций всего: 2" "L1c: битая строка не посчитана реакцией"
assert_contains "$OUT" "Bash" "L1d: распределение по инструменту напечатано"
assert_contains "$OUT" "both" "L1e: распределение по виду стимула напечатано"
printf '{"date":"2026-09-12T10:00:00Z","signal":"x"}\n' > "$LS/b/blocker-fired-$SA.jsonl"
OUT=$(STATE_DIR="$LS/b" bash "$ORCH" --live 2>&1); RC=$?
assert_eq "1" "$RC" "L2: стимулы есть, реакций нет — код 1 (трекер мёртв)"
assert_contains "$OUT" "трекер реакций не пишет" "L2b: причина названа"
OUT=$(STATE_DIR="$LS/c" bash "$ORCH" --live 2>&1); RC=$?
assert_eq "2" "$RC" "L3: стимулов нет — код 2, а не «трекер работает»"

echo ""
echo "backfill-compliance tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
