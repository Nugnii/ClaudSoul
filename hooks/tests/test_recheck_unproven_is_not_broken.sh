#!/usr/bin/env bash
# test_recheck_unproven_is_not_broken.sh — «проверить нечем» и «закрытие откатилось» —
# два разных исхода перепроверки долга, и потребитель обязан их различать.
#
# Результат: инвариант, который проверить НЕЧЕМ, даёт значок «?» и итог «все держатся», а не
#            «✗»; при этом отсутствие PyYAML непроверяемостью БОЛЬШЕ НЕ ЯВЛЯЕТСЯ.
# Проверка результата: bash hooks/tests/test_recheck_unproven_is_not_broken.sh даёт 0
#
# Повод (10 сентября 2026). Сигнал старта сессии сказал: «1 инвариант закрытых пунктов
# перестал держаться — закрытие откатилось: D12, верни пункту ☐». Прогон в моей оболочке
# отвечал «все держатся». Расхождение оказалось не в мире, а в ОКРУЖЕНИИ прогона: дайджест
# зовёт recheck из launchd, где нет PyYAML, разбор честно помечает все 341 родителя
# «не прочитан», а потребитель (knowledge-audit-digest.sh, счёт строк `^  ✗ `) переводил это
# в «откатилось». Корень R6 из ROOTS.md: два состояния мира отвечали одним значением канала.
# Молчать вместо этого нельзя (род B): отказ прибора не есть чистота — потому «?» печатается
# и считается отдельной строкой итога.
#
# Ноги держат ОБЕ стороны различения: T1 — отказ разбора НЕ выдаётся за откат; T2 — он и не
# исчезает молча. Без T2 тест зеленел бы у скрипта, который просто перестал говорить.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

command -v python3 >/dev/null 2>&1 || { echo "нет python3 — пропуск"; exit 0; }
# Условие теста — окружение БЕЗ PyYAML. Если он есть и там, различать нечего.
if env -i PATH=/usr/bin:/bin HOME="$HOME" python3 -c 'import yaml' 2>/dev/null; then
    echo "PyYAML доступен и в чистом окружении — предмет теста не воспроизводится, пропуск"
    exit 0
fi

OUT=$(cd "$REPO" && env -i PATH=/usr/bin:/bin HOME="$HOME" bash scripts/backlog-recheck.sh 2>&1)

# --- T1: «нечем проверить» не выдаётся за откат закрытия ---
if grep -q 'ПЕРЕСТАЛИ ДЕРЖАТЬСЯ' <<< "$OUT"; then
    bad T1 "отказ разбора объявлен откатом закрытия — потребитель велит открыть живой пункт"
else
    ok
fi

# --- T2: и не исчезает молча (положительный контроль) ---
# ФИКСТУРА СМЕНИЛАСЬ 13 сентября 2026 вместе с починкой, которую она иначе бы держала.
# Прежде непроверяемость воспроизводилась отсутствием PyYAML: `link_symmetry` вырождался в
# None, и «?» печатался. С этого дня модуль разбирает два своих поля на голом `re`, и та же
# рамка отвечает ПО ДЕЛУ — прежняя фикстура зеленела бы только на невылеченном дереве.
# Настоящая непроверяемость осталась одна и названа самим сверщиком (backlog-recheck.sh:117):
# библиотеки нет вовсе. Её и строим — в песочнице, без живого ~/.claude (D403).
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/repo/scripts" "$SB/repo/hooks/lib" "$SB/home/.claude/global-lessons" "$SB/home/.claude/hooks/state"
cp "$REPO/scripts/backlog-recheck.sh" "$SB/repo/scripts/"
# Сверщик читает и другие носители инвариантов: без них соседние пункты краснеют по
# ОТСУТСТВИЮ ФАЙЛА, и «все держатся» в песочнице стало бы недостижимо — положительный
# контроль T2б проверял бы тогда не предмет, а неполноту фикстуры.
mkdir -p "$SB/repo/knowledge"
cp "$REPO/BACKLOG.md" "$SB/repo/" 2>/dev/null || true
cp "$REPO/knowledge/META.md" "$SB/repo/knowledge/" 2>/dev/null || true
# hooks копируются БЕЗ link_symmetry.py — именно это и делает инвариант непроверяемым.
for f in "$REPO"/hooks/*.sh; do cp "$f" "$SB/repo/hooks/" 2>/dev/null || true; done
printf -- '---\nname: c\ntype: case\nedges:\n  - specializes: pattern-p.md\n---\n' \
    > "$SB/home/.claude/global-lessons/case-a.md"
printf -- '---\nname: p\ntype: pattern\nsource_cases: []\n---\n' \
    > "$SB/home/.claude/global-lessons/pattern-p.md"
OUT2=$(cd "$SB/repo" && env -i PATH=/usr/bin:/bin HOME="$SB/home" \
    CLAUDSOUL_REPO="$SB/repo" LESSONS_DIR="$SB/home/.claude/global-lessons" \
    STATE_DIR="$SB/home/.claude/hooks/state" bash scripts/backlog-recheck.sh 2>&1)
if grep -q '^  ? ' <<< "$OUT2"; then
    ok
else
    bad T2 "непроверенный инвариант пропал из отчёта — отказ прибора стал неотличим от чистоты"
fi
if grep -q 'ПЕРЕСТАЛИ ДЕРЖАТЬСЯ' <<< "$OUT2"; then
    bad T2б "отсутствие библиотеки объявлено откатом закрытия"
else
    ok
fi

# --- T3: ЗАМОК СЕГОДНЯШНЕЙ ПОЧИНКИ — без PyYAML инвариант ОТВЕЧАЕТ ---
# Прежде эта же рамка давала «? D12: 389 родителей не разобрать», то есть прибор молчал
# ровно там, где ходит по расписанию (все три задачи launchd идут с этим PATH).
if grep -q '^  ? D12' <<< "$OUT"; then
    bad T3 "D12 снова непроверяем без PyYAML — запасной разбор не действует"
else
    ok
fi

echo "recheck unproven: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
