#!/usr/bin/env bash
# test_knowledge_coverage.sh — «Проверка результата» knowledge-coverage.sh меряет объявленный результат.
#
# Результат: команда из шапки scripts/knowledge-coverage.sh красна на базе, где запись старше
#            недели не подавалась, не представлена родителем и стоит рангом выше медианы поданных,
#            — и называет её; зелена, когда каждая неподанная запись объяснена одной из трёх
#            причин, и печатает счёт по каждой причине; запись с `injected: false` в журнале
#            поданной не считается; битая строка журнала замер не роняет.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Единственный кандидат в свидетели —
# `test_defect_registry_counterexamples.sh` — зелен под заглушкой: он упоминает инструмент как
# носителя рода, а не гоняет его. Здесь база и журнал подкладываются через LESSONS_DIR и
# STATE_DIR, команда БЕРЁТСЯ из шапки инструмента, как в test_split_provenance_log.sh.
#
# Фикстура — пять записей operational-контура: served (подана журналом), child (имя стоит в
# тексте паттерна), young (дата в имени — сегодня), low (impact 1 — ранг ниже медианы),
# orphan (impact 5, confirmed 20 — выше медианы, нигде не объяснена). Сам паттерн-родитель —
# тоже запись контура: impact 1, и он ложится в «ранг ниже медианы».
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/knowledge-coverage.sh"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *knowledge-coverage.sh*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"
TODAY=$(date +%Y-%m-%d)

# Форма шапки — из мира: поле `name:` настоящих записей НЕ равно стему файла (57 из 58 родителей
# живой базы несут `name:`, и лишь 2 упоминают собственный стем — оба путём в другом поле).
rec() {   # имя impact confirmed
    printf -- '---\nname: %s\nimpact: %s\nconfirmed_count: %s\ncontradicted_count: 0\n---\nтело\n' "${1#*-}" "$2" "$3" > "$L/$1"
}
mk_fixture() {   # $1 = 1 — с необъяснённой записью, 0 — без
    rm -rf "$L" "$S"; mkdir -p "$L" "$S"
    rec case-2026-01-01-served.md 5 10
    rec case-2026-01-03-child.md 5 30
    rec "case-${TODAY}-young.md" 5 30
    rec case-2026-01-04-low.md 1 0
    [ "$1" -eq 1 ] && rec case-2026-01-02-orphan.md 5 20
    printf -- '---\nname: pattern-parent\nimpact: 1\nconfirmed_count: 0\ncontradicted_count: 0\nsource_cases:\n  - case-2026-01-03-child\n---\n' > "$L/pattern-parent.md"
    printf '{"file":"case-2026-01-01-served.md","injected":true}\n' > "$S/injection-log.jsonl"
}
run_tool() {
    OUT=$(cd "$REPO" && LESSONS_DIR="$L" STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
}

# --- T1: необъяснённая запись — красно, названа ------------------------------------------
mk_fixture 1; run_tool
[ "$RC" -eq 1 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'НЕОБЪЯСНЁННЫХ: 1'
has T1 '· case-2026-01-02-orphan.md'

# --- T2: все неподанные объяснены — зелено, счёт по причинам --------------------------------
mk_fixture 0; run_tool
[ "$RC" -eq 0 ] && ok || bad T2 "rc=$RC — $OUT"
has T2 'operational-записей 5'
has T2 'подавалось: 1'
has T2 'представлен родителем: 1'
has T2 'моложе недели: 1'
has T2 'ранг ниже медианы поданных: 2'
has T2 'НЕОБЪЯСНЁННЫХ: 0'

# --- T3: injected: false — не подача ---------------------------------------------------------
mk_fixture 1; printf '{"file":"case-2026-01-02-orphan.md","injected":false}\n' >> "$S/injection-log.jsonl"; run_tool
[ "$RC" -eq 1 ] && ok || bad T3 "запись с injected:false сошла за поданную: rc=$RC — $OUT"

# --- T4: подача журналом объясняет; битая строка журнала замер не роняет --------------------
mk_fixture 1; printf 'не json\n{"file":"case-2026-01-02-orphan.md","injected":true}\n' >> "$S/injection-log.jsonl"; run_tool
[ "$RC" -eq 0 ] && ok || bad T4 "rc=$RC — $OUT"
has T4 'подавалось: 2'

# --- T5: родитель — другой файл: паттерн, чей стем стоит лишь в собственном тексте (путём в поле,
# как у двух настоящих носителей живой базы), не объяснён ---------------------------------------
mk_fixture 0; rec pattern-lonely.md 5 40; printf 'trigger_case: %s/pattern-lonely.md\n' "$L" >> "$L/pattern-lonely.md"; run_tool
[ "$RC" -eq 1 ] && ok || bad T5 "самоупоминание сошло за родителя: rc=$RC — $OUT"
has T5 '· pattern-lonely.md'

# --- T6: базы нет — 2 «не измерено», не 0 «объяснено» ---------------------------------------------
OUT=$(cd "$REPO" && LESSONS_DIR="$TMP/nope" STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T6 "без базы rc=$RC — $OUT"
has T6 'нет базы знаний'

# --- T7: python3 нет в PATH — 2, не 0 ------------------------------------------------------------
BIN="$TMP/bin"; mkdir -p "$BIN"; ln -s "$(command -v bash)" "$BIN/bash"
mk_fixture 0; OUT=$(cd "$REPO" && PATH="$BIN" LESSONS_DIR="$L" STATE_DIR="$S" bash -c "$CMD" 2>&1); RC=$?
[ "$RC" -eq 2 ] && ok || bad T7 "без python3 rc=$RC — $OUT"
has T7 'нужен python3'

echo ""
echo "knowledge-coverage tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
