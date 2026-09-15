#!/usr/bin/env bash
# test_adv3_kia_frontmatter_boundary.sh
#
# АТАКА: шапка не распознана — знание исчезает целиком, и замер об этом молчит.
#
# `frontmatter()` (строка 84): `if not text.startswith("---"): return ""`. Три обычных
# входа мимо этого условия:
#   1. BOM перед `---` (файл прошёл через редактор, пишущий BOM) — глазами не видно,
#      `yaml.safe_load` такой файл читает штатно (проверено);
#   2. пустая строка перед `---`;
#   3. шапка не закрыта вторым `---` (обрыв записи).
#
# Во всех трёх ВСЕ поля читаются как пустые. Дальше `(field(...) or "0")` даёт
# `confirmed_count = 0` — и это молчаливая подстановка, ровно та, против которой заведён
# список `unreadable`: «подставленное всегда отвечает на вопрос замера, и всегда
# благоприятно (ноль подтверждений — не в очереди)». Знание с 40 подтверждениями и
# `outcome: error` исчезает из очереди, из «действует» и из «Не прочитано полей»,
# оставаясь при этом в ЗНАМЕНАТЕЛЕ `stored`, на который делятся все доли отчёта.
# Код возврата — 0, «находок нет».
#
# Ожидание: такое знание либо посчитано (шапка разбирается как её прочтёт yaml),
# либо названо нечитаемым. Молча пропасть оно не может.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"
SCRIPT="$REPO/scripts/knowledge-instrument-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
L="$TMP/lessons"; S="$TMP/state"; mkdir -p "$L" "$S"

FAIL=0
fail() { printf 'ПРОВАЛ: %s\n' "$*"; FAIL=1; }
ok()   { printf 'ok: %s\n' "$*"; }

printf '\xef\xbb\xbf---\ndescription: шапка за BOM\noutcome: error\nstatus: active\nconfirmed_count: 40\n---\nтело\n' > "$L/pattern-bom.md"
printf '\n---\ndescription: пустая строка перед шапкой\noutcome: error\nstatus: active\nconfirmed_count: 41\n---\nтело\n' > "$L/pattern-blank-line.md"
printf -- '---\ndescription: шапка не закрыта\noutcome: error\nstatus: active\nconfirmed_count: 42\n' > "$L/pattern-unclosed.md"
cat > "$L/pattern-normal.md" <<'EOF'
---
description: контроль, шапка обычная
outcome: error
status: active
confirmed_count: 43
---
тело
EOF

out="$(LESSONS_DIR="$L" STATE_DIR="$S" bash "$SCRIPT" 2>&1)"; rc=$?
report="$(cat "$S/knowledge-instrument.md" 2>/dev/null)"

printf -- '--- вывод замера (rc=%s) ---\n%s\n' "$rc" "$out"

grep -q 'pattern-normal' <<< "$report" \
  && ok "контрольное знание в очереди" \
  || fail "контроль сломан: обычное знание не попало в очередь"

for stem in pattern-bom pattern-blank-line pattern-unclosed; do
    if grep -q "$stem" <<< "$report"; then
        ok "$stem назван в отчёте"
    else
        fail "$stem исчез из отчёта целиком: ни в очереди, ни в «Не прочитано полей», но в знаменателе stored=$(grep -o 'хранится [0-9]*' <<< "$out") он есть"
    fi
done

if [ "$rc" -ne 0 ]; then
    ok "замер вернул находку (rc=$rc)"
else
    fail "rc=0 — «отработал, находок нет», хотя три знания из четырёх прочитать не смог; measurement-due.sh поставит отметку прогона и не вернётся сюда 7 дней"
fi

exit "$FAIL"
