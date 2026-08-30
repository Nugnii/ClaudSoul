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
trap 'rm -rf "$TMP"' EXIT
LESSONS="$TMP/global-lessons"
mkdir -p "$LESSONS"

run_hook() {  # $1 — файл, $2 — (опц.) CLAUDSOUL_ROOT, $3 — (опц.) CLAUDSOUL_PYTHON
    # Режим выбирается ТРЕТЬИМ аргументом, а не отсутствием venv: подстановка
    # несуществующего CLAUDSOUL_ROOT режим не выключала — хук доходил до системного
    # `python3`, и запасной путь оставался непроверенным (пойман 2026-08-11).
    printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" \
        | LESSONS_DIR="$LESSONS" CLAUDSOUL_ROOT="${2:-$ROOT}" CLAUDSOUL_PYTHON="${3:-}" \
          bash "$HOOK" 2>/dev/null
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

cat > "$LESSONS/case-healthy.md" << 'EOF'
---
name: здоровый
description: "Отрицательный контроль это не ловит: он проверяет вывод"
type: case
tags: [a, b]
---
тело
EOF

# Двоеточие только в комментарии — YAML его отбрасывает, тревоги быть не должно.
cat > "$LESSONS/case-comment.md" << 'EOF'
---
name: с комментарием
verdict: candidate   # сигнал невидим по конструкции: поле состояния его не несёт
type: case
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

# --- T1: полный режим (парсер) ---
assert_contains "$(run_hook "$LESSONS/case-broken.md")" "Битый YAML frontmatter" "T1: битый ловится"
assert_empty   "$(run_hook "$LESSONS/case-healthy.md")"                          "T1b: здоровый молчит"
assert_empty   "$(run_hook "$LESSONS/case-comment.md")"                          "T1c: двоеточие в комментарии не тревога"
assert_empty   "$(run_hook "$LESSONS/_draft-broken.md")"                         "T1d: черновики (_*) пропускаются"
assert_empty   "$(run_hook "$LESSONS/plain.md")"                                 "T1e: файл без frontmatter пропускается"

# --- T2: запасной режим (PyYAML недоступен) ---
assert_contains "$(run_hook "$LESSONS/case-broken.md" "$ROOT" /nonexistent)" "Возможен битый YAML" "T2: битый ловится regex'ом"
assert_contains "$(run_hook "$LESSONS/case-broken.md" "$ROOT" /nonexistent)" "description"          "T2b: назван ключ"
assert_empty   "$(run_hook "$LESSONS/case-healthy.md" "$ROOT" /nonexistent)"                        "T2c: здоровый молчит"
assert_empty   "$(run_hook "$LESSONS/case-comment.md" "$ROOT" /nonexistent)"                        "T2d: комментарий не тревога"

# --- T3: посторонние файлы вне базы не трогаются ---
printf -- '---\nbad: a: b\n---\n' > "$TMP/outside.md"
assert_empty "$(run_hook "$TMP/outside.md")" "T3: файл вне базы знаний игнорируется"

# --- T4: не тот инструмент — молчим ---
OUT=$(printf '{"tool_name":"Bash","tool_input":{"file_path":"%s"}}' "$LESSONS/case-broken.md" \
        | LESSONS_DIR="$LESSONS" bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T4: PostToolUse[Bash] не наш случай"

echo "knowledge-frontmatter-check: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
