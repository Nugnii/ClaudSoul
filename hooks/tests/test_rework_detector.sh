#!/usr/bin/env bash
# test_rework_detector.sh — детектор третьего захода на тот же файл.
#
# Отрицательный контроль обязателен по построению (правило v1.12.4): проверка,
# про которую не показано, что она способна упасть, ничего не доказывает. Поэтому
# у каждого случая есть пара — вход, на котором детектор ОБЯЗАН молчать.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/rework-detector.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_contains() {
    if grep -qF -- "$2" <<< "$1"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 200)"; fi
}
assert_empty() {
    if [ -z "$1" ] || [ "$1" = "{}" ]; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$2]: ожидалась тишина, получено: $(printf '%s' "$1" | head -c 200)"; fi
}

edit() { # sid, path
    jq -cn --arg s "$1" --arg p "$2" \
        '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$p}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
run() { # sid
    jq -cn --arg s "$1" '{session_id:$s, tool_name:"Bash", tool_input:{command:"bash test.sh"}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}
mkdir -p "$TMP/state"

# === T1: правка → прогон → правка → прогон → правка = третий заход, горит ===
OUT=$(edit s1 /repo/test_x.sh); assert_empty "$OUT" "T1a: первая правка → тишина"
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh); assert_empty "$OUT" "T1b: вторая правка → тишина"
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T1c: третья правка в цепочке → горит"
assert_contains "$OUT" "test_x.sh" "T1d: назван файл"
# Проверяется НАЛИЧИЕ доктрины разбора, а не её формулировка. Прежде здесь стоял кусок
# собственной редакции хука («Почему предыдущая правка не сработала») — пять готовых
# «почему», то есть фикс-глубина, отменённая /retro 3.1. Тест на дословный текст своей
# редакции держал её же: он был бы зелёным ровно до тех пор, пока хук расходится с каноном.
# Единственность текста держит test_root_cause_doctrine_drift; здесь — что текст доехал.
assert_contains "$OUT" "НИ ОДНИМ путём" "T1e: дана доктрина разбора (признак корня)"

# === T2: три правки ПОДРЯД без прогонов — обычное дописывание, не переработка ===
OUT=$(edit s2 /repo/doc.md); assert_empty "$OUT" "T2a: первая → тишина"
OUT=$(edit s2 /repo/doc.md); assert_empty "$OUT" "T2b: вторая подряд → тишина"
OUT=$(edit s2 /repo/doc.md)
assert_empty "$OUT" "T2c: третья подряд без прогонов → тишина (не переработка)"

# === T3: правки РАЗНЫХ файлов с прогонами — не цепочка ===
edit s3 /repo/a.sh >/dev/null; run s3 >/dev/null
edit s3 /repo/b.sh >/dev/null; run s3 >/dev/null
OUT=$(edit s3 /repo/c.sh)
assert_empty "$OUT" "T3: разные файлы → тишина"

# === T4: новый цикл переделки того же файла говорит снова; повтор без прогона — молчит ===
# Троттл — по (файл, число циклов), а не по файлу: первый прогон замера detection-share
# (30 августа 2026) показал, что после первого напоминания файл переделывался дальше, а страж
# молчал — «повтор уплывает» (поправка владельца 27 августа). Правки без прогона между ними
# число циклов не меняют — та же подпись, тишина.
run s1 >/dev/null
OUT=$(edit s1 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T4a: четвёртый цикл того же файла — новое событие, страж говорит"
OUT=$(edit s1 /repo/test_x.sh)
assert_empty "$OUT" "T4b: правка без прогона — та же подпись, тишина (throttle)"

# === T5: другая сессия считается независимо ===
edit s5 /repo/test_x.sh >/dev/null; run s5 >/dev/null
edit s5 /repo/test_x.sh >/dev/null; run s5 >/dev/null
OUT=$(edit s5 /repo/test_x.sh)
assert_contains "$OUT" "Переработка" "T5: новая сессия — свой счёт"

# === T6: порог настраивается ===
OUT=$(jq -cn '{session_id:"s6", tool_name:"Edit", tool_input:{file_path:"/repo/z.sh"}}' \
    | env STATE_DIR="$TMP/state" REWORK_THRESHOLD=1 bash "$HOOK" 2>/dev/null)
assert_contains "$OUT" "Переработка" "T6: порог 1 → горит с первой правки"

# === T8: файлы-хроники исключены (калибровка D18) ===
edit s8 /repo/CHANGELOG.md >/dev/null; run s8 >/dev/null
edit s8 /repo/CHANGELOG.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/CHANGELOG.md)
assert_empty "$OUT" "T8: CHANGELOG.md — хроника, детектор молчит"
edit s8 /repo/sub/SESSION.md >/dev/null; run s8 >/dev/null
edit s8 /repo/sub/SESSION.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/sub/SESSION.md)
assert_empty "$OUT" "T8b: SESSION.md во вложенной папке — тоже хроника"
OUT=$(jq -cn '{session_id:"s8", tool_name:"Edit", tool_input:{file_path:"/repo/BACKLOG-archive.md"}}' \
    | env STATE_DIR="$TMP/state" REWORK_THRESHOLD=1 bash "$HOOK" 2>/dev/null)
assert_empty "$OUT" "T8c: BACKLOG-archive.md исключён даже при пороге 1"
# Разметка выборки D23 (2026-08-11): документы состояния попали в сигнал как шум —
# CLAUDE.md дважды, META.md один раз. Повторная правка в них — норма жанра, как append
# в хронике: картина уточняется по ходу сессии.
edit s8 /repo/CLAUDE.md >/dev/null; run s8 >/dev/null
edit s8 /repo/CLAUDE.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/CLAUDE.md)
assert_empty "$OUT" "T8d: CLAUDE.md — документ состояния, детектор молчит"
# Отрицательный контроль к T8d: рядом стоящий .md БЕЗ роли документа состояния обязан
# сигналить, иначе исключение расширилось до «любой markdown» и сигнала не осталось.
edit s8 /repo/case-2026-08-11-x.md >/dev/null; run s8 >/dev/null
edit s8 /repo/case-2026-08-11-x.md >/dev/null; run s8 >/dev/null
OUT=$(edit s8 /repo/case-2026-08-11-x.md)
assert_contains "$OUT" "Переработка" "T8e: обычный .md по-прежнему сигналит (иначе исключение съело сигнал)"

# === T7: мусор на входе не роняет хук ===
OUT=$(printf 'not-json' | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null); RC=$?
assert_empty "$OUT" "T7a: мусор → тишина"
if [ "$RC" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [T7b]: rc=$RC"; fi

# === D91: правка через оболочку — такая же правка ===
# До 27 августа 2026 ветка Bash писала только «прогон», и в сессии, где файлы правят
# через heredoc и sed, цепочка не набирала ни шага: замер по живой сессии — 156 записей
# в логе, из них 16 правок, все от субагентов через Write, а переписанный больше десяти
# раз через оболочку hook-input-lib.sh отсутствовал полностью.
# Цель — ВНЕ /tmp намеренно: детектор отбрасывает `*/tmp/*` как временное, а `mktemp -d` на
# Linux даёт именно /tmp — на macOS (/var/folders/…) фикстура молчала о дефекте, и CI покраснел
# 30 августа 2026 (case-2026-08-29-fixture-easier-than-world-hides-the-defect, второй случай).
BASH_DIR=$(mktemp -d "${HOME}/.claudsoul-test-rework.XXXXXX"); trap 'rm -rf "$TMP" "$BASH_DIR"' EXIT
BASH_TARGET="$BASH_DIR/target_file.sh"
printf '#!/usr/bin/env bash\necho x\n' > "$BASH_TARGET"

sh_edit() { # sid, команда
    jq -cn --arg s "$1" --arg c "$2" \
        '{session_id:$s, tool_name:"Bash", tool_input:{command:$c}}' \
        | env STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null
}

# затравка: цепочка создаётся только если в сессии уже была правка
edit s9 /repo/seed.sh >/dev/null

OUT=$(sh_edit s9 "cat > $BASH_TARGET <<'EOF'
one
EOF"); assert_empty "$OUT" "D91a: первая правка через оболочку → тишина"
run s9 >/dev/null
OUT=$(sh_edit s9 "sed -i '' 's/one/two/' $BASH_TARGET"); assert_empty "$OUT" "D91b: вторая → тишина"
run s9 >/dev/null
OUT=$(sh_edit s9 "python3 - <<'PY'
import io
p='$BASH_TARGET'
io.open(p,'w').write('three')
PY")
assert_contains "$OUT" "Переработка" "D91c: третья правка через оболочку → горит"
assert_contains "$OUT" "target_file.sh" "D91d: назван файл, правленный через оболочку"

# Запуск файла — не правка: адресат записи другой
edit s10 /repo/seed.sh >/dev/null
OUT=$(sh_edit s10 "bash $BASH_TARGET > $TMP/out.log 2>&1"); assert_empty "$OUT" "D91e: запуск с редиректом в лог → тишина"
run s10 >/dev/null
OUT=$(sh_edit s10 "bash $BASH_TARGET > $TMP/out.log 2>&1"); assert_empty "$OUT" "D91f: второй запуск → тишина"
run s10 >/dev/null
OUT=$(sh_edit s10 "bash $BASH_TARGET > $TMP/out.log 2>&1")
assert_empty "$OUT" "D91g: третий запуск не считается переработкой"

echo ""
echo "=================================="
echo "rework-detector: $PASS passed, $FAIL failed"
echo "=================================="
[ "$FAIL" -eq 0 ]
