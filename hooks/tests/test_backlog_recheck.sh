#!/usr/bin/env bash
# СУДИТ: scripts/backlog-recheck.sh
# test_backlog_recheck.sh — перепроверка закрытых пунктов обязана краснеть на откате.
#
# Повод. Закрытия делятся на два вида, и держатся по-разному: за одним стоит тест, и он
# гоняется каждый прогон; за другим — разовое действие (лог вычищен, ссылки восстановлены,
# поле задокументировано), и оно не проверяет себя ничем. Замер 2026-07-29: из 28 закрытых
# пунктов долга 11 держались тестом, 17 — разовым действием. Второй вид может тихо
# откатиться, а пункт останется помеченным «сделано».
#
# Что проверяет этот тест: что сама перепроверка не декоративна. Каждый инвариант ставится
# в положение отката, и скрипт обязан это назвать. Без такой проверки зелёный итог
# «все держатся» означал бы либо порядок, либо неспособность заметить беспорядок —
# а различить их снаружи нельзя.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/backlog-recheck.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: не найден $SCRIPT"; exit 1; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Изолированная копия дерева: продукт и рабочая база не трогаются.
SANDBOX="$TMP/repo"
mkdir -p "$SANDBOX/scripts" "$SANDBOX/knowledge" "$SANDBOX/skills/entity" "$SANDBOX/skills/ingest"
cp "$SCRIPT" "$SANDBOX/scripts/"
# Инвариант D12 считается библиотекой `hooks/lib/link_symmetry.py` (D312). Без неё
# сверщик обязан сказать «НЕ ПРОВЕРЕН», а не «держится», — это отдельная нога T6 ниже.
mkdir -p "$SANDBOX/hooks/lib"
cp "$REPO/hooks/lib/link_symmetry.py" "$SANDBOX/hooks/lib/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }
cp "$REPO/knowledge/META.md" "$SANDBOX/knowledge/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }
cp "$REPO/skills/entity/SKILL.md" "$SANDBOX/skills/entity/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }
cp "$REPO/skills/ingest/SKILL.md" "$SANDBOX/skills/ingest/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }
printf '# BACKLOG\n\n- ☐ **X1** заглушка\n' > "$SANDBOX/BACKLOG.md"

LESS="$TMP/lessons"; STAT="$TMP/state"
mkdir -p "$LESS" "$STAT"
cp "$REPO/knowledge/META.md" "$LESS/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }
printf '{"date":"2026-07-01T10:00:00Z","file":"pattern-a.md","score":5}\n' > "$STAT/injection-log.jsonl"
cat > "$LESS/pattern-shell-portability.md" <<'SP'
---
name: проба
blocker: true
detection_signals: |
  [
    {
      "name": "probe",
      "all_of": [{"tool_matches": ["Edit"]}]
    }
  ]
---
тело
SP
cat > "$LESS/pattern-target.md" <<'PT'
---
name: мишень
source_cases:
  - case-linked.md
---
тело
PT
# Ребро объявляется полем `edges` ВНУТРИ frontmatter: с D319 инвариант читает обе стороны
# связи одним разбором поля, и строка `- confirms:` в теле файла ребром не является.
printf -- '---\nname: связанный\nedges:\n  - confirms: pattern-target.md\n---\n' > "$LESS/case-linked.md"

run() { CLAUDSOUL_REPO="$SANDBOX" LESSONS_DIR="$LESS" STATE_DIR="$STAT" bash "$SANDBOX/scripts/backlog-recheck.sh" 2>&1; }

# --- T1: на согласованном состоянии всё держится ---
OUT=$(run); RC=$?
if [ "$RC" -eq 0 ] && grep -q 'все держатся' <<< "$OUT"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T1]: ожидался зелёный итог, получено rc=$RC: $(printf '%s' "$OUT" | tail -2 | tr '\n' ' ')"; fi

# --- T2..T5: каждый инвариант ставится в положение отката и обязан быть назван ---
# Обе стороны обязательны: без этих случаев зелёный T1 не отличим от неспособности заметить.
break_and_check() { # $1=что ломаем (команда) $2=подстрока в отчёте $3=имя случая
    eval "$1"
    o=$(run); rc=$?
    if [ "$rc" -ne 0 ] && grep -qF "$2" <<< "$o"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: откат не назван (rc=$rc). Отчёт: $(printf '%s' "$o" | grep '✗' | head -1)"; fi
}

# лог инжектов снова содержит нечитаемую строку
break_and_check "printf 'не json\\n' >> '$STAT/injection-log.jsonl'" "нечитаемых строк" "T2 битая строка в логе"
python3 - "$STAT/injection-log.jsonl" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("".join(l for l in p.read_text().splitlines(True) if l.startswith("{")))
PY

# ссылка кейс → паттерн снова односторонняя
break_and_check "python3 -c \"
import pathlib
p = pathlib.Path('$LESS/pattern-target.md'); t = p.read_text()
p.write_text(t.replace('  - case-linked.md', '  - case-other.md'))\"" "односторонних ссылок" "T3 односторонняя ссылка"
python3 -c "
import pathlib
p = pathlib.Path('$LESS/pattern-target.md'); t = p.read_text()
p.write_text(t.replace('  - case-other.md', '  - case-linked.md'))"

# из описания скилла пропала фраза автовызова
break_and_check "python3 -c \"
import pathlib
p = pathlib.Path('$SANDBOX/skills/ingest/SKILL.md'); t = p.read_text()
p.write_text(t.replace('добавь в базу знаний', 'внеси'))\"" "пропала фраза" "T4 фраза автовызова вырезана"
cp "$REPO/skills/ingest/SKILL.md" "$SANDBOX/skills/ingest/" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }

# у блокера опустели сигналы детекции
break_and_check "python3 -c \"
import pathlib, re
p = pathlib.Path('$LESS/pattern-shell-portability.md'); t = p.read_text()
p.write_text(re.sub(r'detection_signals: \|\n(?:  .*\n)+', 'detection_signals: []\n', t))\"" "detection_signals" "T5 блокер без сигналов"

# --- T6: НЕСПОСОБНОСТЬ ПРОВЕРИТЬ не выдаётся за чистоту ---
# Прежде инвариант D12 считался кодом внутри самого скрипта, и вопрос «а чем считать»
# не стоял. С выносом в `hooks/lib/link_symmetry.py` (D312) появился новый способ
# ослепнуть: библиотеки нет — разбирать нечем. Молчаливый `skip` тут неотличим от
# «нарушений не найдено», поэтому исход обязан быть красным и названным.
# HOME подменяется намеренно: у сверщика ТРИ источника библиотеки — репозиторий, каталог
# рядом со скриптом и установка `$HOME/.claude/hooks/lib`. Песочница подменяла только
# первый, поэтому на машине с установленным ClaudSoul нога находила библиотеку в третьем
# и зеленела, ничего не проверив: одиночный прогон был зелёным, полный набор — красным,
# и разница была лишь в том, успели ли установить библиотеку.
mv "$SANDBOX/hooks/lib/link_symmetry.py" "$SANDBOX/hooks/lib/link_symmetry.py.off"
mkdir -p "$TMP/nohome"
o=$(HOME="$TMP/nohome" CLAUDSOUL_REPO="$SANDBOX" LESSONS_DIR="$LESS" STATE_DIR="$STAT" \
    bash "$SANDBOX/scripts/backlog-recheck.sh" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && grep -qF "НЕ ПРОВЕРЕН" <<< "$o"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T6 без библиотеки инвариант не считается проверенным]: rc=$rc, отчёт: $(printf '%s' "$o" | grep 'D12' | head -1)"; fi
mv "$SANDBOX/hooks/lib/link_symmetry.py.off" "$SANDBOX/hooks/lib/link_symmetry.py" 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:$LINENO" >&2; exit 1; }

# --- T7-T9 (D1098): расхождение META судится по НАПРАВЛЕНИЮ, а не по факту ---
# Установка кладёт META из репозитория, поэтому копия, не правленная после переноса, ждёт
# переноса — откатом это не грозит. Откатится только правка, сделанная в самой рабочей базе.
# Судит журнал переносов (`carry_diverged`, ADR-019). Повод: 24 и 25 октября 2026 сигнал
# старта дважды велел вернуть D27 пункту ☐, а рабочая копия отставала на непереносённый коммит.
mkdir -p "$SANDBOX/lib"
cp "$REPO/lib/carry-log.sh" "$SANDBOX/lib/" || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:T7 lib" >&2; exit 1; }
CL="$TMP/carry-log.tsv"
runc() { CARRY_LOG="$CL" CLAUDSOUL_REPO="$SANDBOX" LESSONS_DIR="$LESS" STATE_DIR="$STAT" bash "$SANDBOX/scripts/backlog-recheck.sh" 2>&1; }
d27() { printf '%s\n' "$1" | grep -E 'D27( |$)' | head -1; }   # номер целиком (D1294)
# T7: журнал о приёмнике не знает — направление не установить; это «не проверено», а не «откат».
printf '\nабзац, которого нет в рабочей базе\n' >> "$SANDBOX/knowledge/META.md"
o=$(runc)
if grep -qE '^  \? D27( |$)' <<< "$o" && ! grep -qE '^  ✗ D27( |$)' <<< "$o"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T7 журнал не знает приёмник — направление не установлено]: $(d27 "$o")"; fi
# T8: приёмник не правлен после переноса, репозиторий ушёл вперёд — ждёт переноса, D27 держится.
( . "$SANDBOX/lib/carry-log.sh"; CARRY_LOG="$CL" CARRY_REPO="$TMP" carry_record проба "$SANDBOX/knowledge/META.md" "$LESS/META.md" ) \
    || { echo "подготовка мира не удалась: hooks/tests/test_backlog_recheck.sh:T8 журнал" >&2; exit 1; }
o=$(runc)
if ! grep -qE '^  (✗|\?) D27( |$)' <<< "$o"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T8 отставание рабочей копии названо откатом]: $(d27 "$o")"; fi
# T9: приёмник правлен после переноса — настоящий откат, обязан быть назван.
printf '\nправка в рабочей базе\n' >> "$LESS/META.md"
o=$(runc); rc=$?
if [ "$rc" -ne 0 ] && grep -qE '^  ✗ D27( |$)' <<< "$o"; then PASS=$((PASS + 1))
else FAIL=$((FAIL + 1)); echo "FAIL [T9 правка в рабочей базе не названа]: rc=$rc $(d27 "$o")"; fi

echo ""
echo "backlog recheck tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
