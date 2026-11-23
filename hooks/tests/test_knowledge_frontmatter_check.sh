#!/usr/bin/env bash
# test_knowledge_frontmatter_check.sh — страж битого YAML frontmatter в базе знаний.
#
# Что защищаем. Хук работает в двух режимах: полным парсером (если доступен python с PyYAML)
# и regex'ом (если нет). Regex-режим уже дважды ломался при написании, и оба раза молча:
#   · условие `/: /` проверяло ВСЮ строку и совпадало с самим разделителем ключа —
#     срабатывало на каждой строке подряд;
#   · двоеточие в хвостовом комментарии YAML (`verdict: x   # …по конструкции: …`)
#     принималось за поломку — 6 ложных тревог на 317 файлах живой базы.
# Тревога, которая врёт, хуже отсутствия тревоги: к ней быстро привыкают. Поэтому здесь
# проверяется не только «ловит битое», но и «молчит на здоровом» — обе стороны.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/knowledge-frontmatter-check.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' нет в: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "ожидалась тишина, получено: $1"; fi; }

TMP=$(mktemp -d)
# Реестр сессий — тоже боевой каталог: `session-registry-lib` выводит его из $HOME,
# и без подмены прогон дописывает фикстуры в ~/.claude/sessions (D271).
export SR_SESSIONS_DIR="$TMP/sessions"
trap 'rm -rf "$TMP"' EXIT
LESSONS="$TMP/global-lessons"
mkdir -p "$LESSONS"

run_hook() {  # $1 — файл, $2 — (опц.) CLAUDSOUL_ROOT, $3 — (опц.) CLAUDSOUL_PYTHON
    # Режим выбирается ТРЕТЬИМ аргументом, а не отсутствием venv: подстановка
    # несуществующего CLAUDSOUL_ROOT режим не выключала — хук доходил до системного
    # `python3`, и запасной путь оставался непроверенным (пойман 2026-08-11).
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | LESSONS_DIR="$LESSONS" CLAUDSOUL_ROOT="${2:-$ROOT}" CLAUDSOUL_PYTHON="${3:-}" \
          bash "$HOOK" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_knowledge_frontmatter_check.sh:$LINENO" >&2; exit 1; }
}

# --- фикстуры ---
cat > "$LESSONS/case-broken.md" << 'EOF'
---
name: битый
description: Отрицательный контроль это не ловит: он проверяет вывод
type: case
---
тело
EOF

# Здоровые фикстуры несут ПОЛНУЮ шапку: с 12 сентября 2026 хук судит и полноту (D347), и
# минимальная шапка «имя, описание, тип» — уже не «здоровая», а неполная.
cat > "$LESSONS/case-healthy.md" << 'EOF'
---
name: здоровый
description: "Отрицательный контроль это не ловит: он проверяет вывод"
type: case
outcome: error
confidence: 1
impact: 3
intensity: 0
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-12
source_cases: []
source_session: ""
status: active
tags: [a, b]
---
тело
EOF

# Двоеточие только в комментарии — YAML его отбрасывает, тревоги быть не должно.
cat > "$LESSONS/case-comment.md" << 'EOF'
---
name: с комментарием
description: "двоеточие живёт в хвостовом комментарии, не в значении"
verdict: candidate   # сигнал невидим по конструкции: поле состояния его не несёт
type: case
outcome: error
confidence: 1
impact: 3
intensity: 0
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-12
source_cases: []
source_session: ""
status: active
---
тело
EOF

cat > "$LESSONS/_draft-broken.md" << 'EOF'
---
description: черновик тоже битый: и это не наше дело
---
тело
EOF

printf 'файл без frontmatter: просто текст\n' > "$LESSONS/plain.md"

# Форма ребра (D1032): полная здоровая шапка, но ребро словарём — разборщик связей его не читает.
sed 's/^tags: \[a, b\]$/tags: [a, b]\
edges:\
  - {type: confirms, target: pattern-x.md}\
  - similar_to: case-y.md/' "$LESSONS/case-healthy.md" > "$LESSONS/case-edge-dict.md"
sed 's/^tags: \[a, b\]$/tags: [a, b]\
edges:\
  - confirms: pattern-x.md\
  - similar_to: case-y.md   # пояснение комментарием/' "$LESSONS/case-healthy.md" > "$LESSONS/case-edge-pair.md"

# --- T1: полный режим (парсер) ---
assert_contains "$(run_hook "$LESSONS/case-broken.md")" "Битый YAML frontmatter" "T1: битый ловится"
assert_empty   "$(run_hook "$LESSONS/case-healthy.md")"                          "T1b: здоровый молчит"
assert_empty   "$(run_hook "$LESSONS/case-comment.md")"                          "T1c: двоеточие в комментарии не тревога"
assert_empty   "$(run_hook "$LESSONS/_draft-broken.md")"                         "T1d: черновики (_*) пропускаются"
assert_contains "$(run_hook "$LESSONS/case-edge-dict.md")" "Ребро не парой" "T1e: ребро словарём {type, target} названо (D1032)"
assert_contains "$(run_hook "$LESSONS/case-edge-dict.md")" "элемент 1" "T1f: названа позиция элемента"
assert_empty   "$(run_hook "$LESSONS/case-edge-pair.md")"                        "T1g: пары «вид: цель» с комментарием — тишина"

# --- D347: ПОЛНОТА шапки — набор обязательных полей выводится из шаблона контура и блока
# «Обязательные» META, а не из перечня в хуке. Неполная запись называется при записи.
cat > "$LESSONS/case-incomplete.md" << 'EOF'
---
name: неполный
description: "без outcome и счётчиков"
type: case
---
тело
EOF
cat > "$LESSONS/case-complete.md" << 'EOF'
---
name: полный
description: "все обязательные поля на месте"
type: case
outcome: error
confidence: 1
impact: 3
intensity: 0
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-09-12
source_cases: []
source_session: ""
status: active
---
тело
EOF
cat > "$LESSONS/entity-incomplete.md" << 'EOF'
---
name: сущность
description: "без created и last_updated"
---
тело
EOF
cat > "$LESSONS/entity-ok.md" << 'EOF'
---
name: сущность
description: "полная"
created: 2026-09-12
last_updated: 2026-09-12
---
тело
EOF
OUT_INC=$(run_hook "$LESSONS/case-incomplete.md")
assert_contains "$OUT_INC" "Неполная шапка: case-incomplete.md" "T8: неполная запись названа при записи"
assert_contains "$OUT_INC" "outcome"                            "T8b: недостающее поле названо по имени"
assert_contains "$OUT_INC" "knowledge/META.md"                  "T8c: источник набора назван (шаблон + META), не перечень в коде"
assert_empty    "$(run_hook "$LESSONS/case-complete.md")"        "T8d: полная запись — тишина"
assert_contains "$(run_hook "$LESSONS/entity-incomplete.md")" "created" "T8e: второй контур — набор из СВОЕГО шаблона (entity.md.tmpl)"
assert_empty    "$(run_hook "$LESSONS/entity-ok.md")"            "T8f: полная сущность — тишина"
# Названный предел: без python (запасной awk-путь) полнота не судится — тишина, не ложное «полно».
# Условие снятия: запасной путь научится читать ключи шапки (awk по `^ключ:` между `---`) —
# тогда набор из шаблона сверяется и без PyYAML, и предел снимается.
assert_empty    "$(run_hook "$LESSONS/case-incomplete.md" "$ROOT" /nonexistent-python)" "T8g: запасной путь без python полноту не судит (предел назван)"
assert_empty   "$(run_hook "$LESSONS/plain.md")"                                 "T1e: файл без frontmatter пропускается"

# --- T2: запасной режим (PyYAML недоступен) ---
assert_contains "$(run_hook "$LESSONS/case-broken.md" "$ROOT" /nonexistent)" "Возможен битый YAML" "T2: битый ловится regex'ом"
assert_contains "$(run_hook "$LESSONS/case-edge-dict.md" "$ROOT" /nonexistent)" "Ребро не парой" "T2b: ребро словарём ловится и без PyYAML — по строке (D1032)"
assert_empty   "$(run_hook "$LESSONS/case-edge-pair.md" "$ROOT" /nonexistent)"                        "T2c: пары в запасном режиме — тишина"
assert_contains "$(run_hook "$LESSONS/case-broken.md" "$ROOT" /nonexistent)" "description"          "T2b: назван ключ"
assert_empty   "$(run_hook "$LESSONS/case-healthy.md" "$ROOT" /nonexistent)"                        "T2c: здоровый молчит"
assert_empty   "$(run_hook "$LESSONS/case-comment.md" "$ROOT" /nonexistent)"                        "T2d: комментарий не тревога"

# --- T3: посторонние файлы вне базы не трогаются ---
printf -- '---\nbad: a: b\n---\n' > "$TMP/outside.md"
assert_empty "$(run_hook "$TMP/outside.md")" "T3: файл вне базы знаний игнорируется"

# --- T4: посторонний инструмент — молчим ---
OUT=$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s"}}' "$LESSONS/case-broken.md" \
        | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T4: PostToolUse[Read] не наш случай"

# --- T5: предмет — ИЗМЕНЁННЫЙ ФАЙЛ, а не имя инструмента (D311) ---
# Оболочка правит те же файлы (heredoc, sed) и `file_path` не несёт. Повод измерен
# 5 сентября 2026: два кейса записаны `cat > … <<EOF`, проверка не срабатывала ни разу.
STATE="$TMP/state"
mkdir -p "$STATE"
STAMP="$STATE/frontmatter-scan.stamp"

run_bash() {  # прогон в режиме оболочки: адреса нет, предмет — база
    printf '{"session_id":"t5","tool_name":"Bash","tool_input":{"command":"cat > x <<EOF"}}' \
        | LESSONS_DIR="$LESSONS" CLAUDSOUL_STATE_DIR="$STATE" CLAUDSOUL_ROOT="$ROOT" \
          bash "$HOOK" 2>/dev/null
}

# T5a: отметки нет — первый вызов её заводит и МОЛЧИТ (файлы старше отметки не наше событие).
rm -f "$STAMP"
assert_empty "$(run_bash)" "T5a: первый вызов заводит отметку и молчит"
if [ -f "$STAMP" ]; then ok; else bad "T5a2" "отметка не заведена"; fi

# T5b: ничего не менялось после отметки — тишина (сторож отсекает полный проход).
assert_empty "$(run_bash)" "T5b: без свежих правок — тишина"

# T5c: битый файл тронут ПОСЛЕ отметки — ловится, хотя инструмент Bash.
sleep 1
touch "$LESSONS/case-broken.md"
OUT5=$(run_bash)
assert_contains "$OUT5" "Битый YAML frontmatter" "T5c: битое ловится в режиме оболочки"
assert_contains "$OUT5" "case-broken.md"          "T5c2: назван файл"

# T5d: отметка сдвинута проходом — повтор молчит (иначе полный проход на каждой команде).
assert_empty "$(run_bash)" "T5d: отметка сдвинута, повтор молчит"

# T5e: несколько целей за один проход — сообщение несёт ОБЕ, а не первую.
cat > "$LESSONS/case-broken2.md" << 'EOF'
---
name: второй битый
description: и здесь двоеточие: внутри значения
type: case
---
тело
EOF
sleep 1
touch "$LESSONS/case-broken.md" "$LESSONS/case-broken2.md"
OUT5E=$(run_bash)
assert_contains "$OUT5E" "case-broken.md"  "T5e: первая цель названа"
assert_contains "$OUT5E" "case-broken2.md" "T5e2: вторая цель названа"

# T5f: здоровый файл, тронутый после отметки, тревоги не даёт (отрицательный контроль).
sleep 1
touch "$LESSONS/case-healthy.md"
assert_empty "$(run_bash)" "T5f: здоровый в режиме оболочки молчит"

# --- T6: дельта знаний пишется и при оболочке (предел: род всегда updated) ---
# Целей ДВЕ намеренно: с одной нога зелена и на коде, который пишет только первую —
# мутация «дельта только KEPT[0]» проходила её насквозь (замер 5 сентября 2026).
sleep 1
touch "$LESSONS/case-healthy.md" "$LESSONS/case-comment.md"
run_bash >/dev/null 2>&1
DELTA=$(jq -r '.knowledge_delta.updated // [] | join(",")' "$SR_SESSIONS_DIR/active/t5.json" 2>/dev/null)
assert_contains "$DELTA" "case-healthy.md" "T6: запись знания оболочкой попала в реестр"
assert_contains "$DELTA" "case-comment.md" "T6b: вторая цель прохода тоже в реестре"

echo "knowledge-frontmatter-check: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
