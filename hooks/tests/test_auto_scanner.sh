#!/usr/bin/env bash
# СУДИТ: hooks/auto-scanner.sh
# test_auto_scanner.sh — характеризующий тест read-only сканера проектов.
# Полный прогон сканирует реальные проекты (side-effect), поэтому тест проверяет
# безопасные инварианты (F8): (1) gate «не чаще ~3ч» — при свежей метке скан
# пропускается; (2) read-only — в исходнике нет мутирующих команд (git commit/push,
# rm, edit). Комментарий хука: «КРИТИЧНО: только чтение».

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/auto-scanner.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }

PASS=0
FAIL=0
assert_rc0() { if [ "$1" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1"; fi; }
assert_true() { if [ "$1" = "1" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

# T1 — gate: свежая метка времени → скан пропускается, реальные проекты не трогаются
date +%s > "$TMP/state/last-scan-timestamp"
STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
rc=$?
assert_rc0 "$rc" "T1 gate skip → rc=0"
# при пропуске scan-results не должен появиться в изолированном STATE_DIR
[ ! -f "$TMP/state/scan-results.md" ] && SKIP_OK=1 || SKIP_OK=0
assert_true "$SKIP_OK" "T1 пропуск не пишет scan-results.md"

# T2 — read-only инвариант: в исходнике нет мутирующих команд
MUT=$(grep -nE "git (commit|push|add|reset|checkout)|[^-]rm -|>[^>]*\.(md|json)|Edit|Write" "$HOOK" \
    | grep -vE "scanner\.log|scan-results|last-scan|>> |LOG_FILE|RESULTS_FILE|2>/dev/null|# |echo " || true)
if [ -z "$MUT" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [T2 read-only]: подозрительные строки:"; echo "$MUT"; fi

# T3 — ЗНАМЕНАТЕЛЬ НАЗЫВАЕТСЯ. Обходчик молча выбывал на не-git, а такой проект попадал в
# счётчик «просканировано», хотя не осматривался ни одной проверкой: тишина «я не смотрел»
# неотличима от тишины «там чисто» (D351, замер 7 сентября 2026 — осмотрено 5 из 30).
# Каталог проектов подменяется, иначе нога шла бы по НАСТОЯЩИМ 30 каталогам памяти.
mkdir -p "$TMP/p/-tmp-net-takogo" "$TMP/state3"
rm -f "$TMP/state3/last-scan-timestamp"
# ЦЕНА СУЖЕНА В ТЕСТЕ, ПРОД НЕ ТРОНУТ (D460, 18 сентября 2026). В конце непрогейченного
# прогона хук зовёт `$HOME/.claude/hooks/metrics-collector.sh` (auto-scanner.sh:346-349) —
# НАСТОЯЩИЙ сборщик метрик по живой базе знаний в 613 файлов. По прибору реестра тест стоил
# 37 с CPU, и на этот вызов приходилось 99,7%: замер скептика 49,3 с CPU целиком против 0,16
# после снятия.
# Предмета ноги вызов не несёт и НИЧЕГО не различает — показано выпотрошенным сборщиком, а не
# рассуждением: `exit 1` с криком в stderr оставляет хук с кодом 0 (`|| true`, :348), отчёт
# получается побайтово тем же, а крик уходит в scanner.log, который этот тест не читает ни
# разу. HOME подменяется песочницей с ЗАГЛУШКОЙ, а не путём в никуда: в бою файл есть всегда,
# и ветка «файла нет» — единственная, которой в бою не бывает.
mkdir -p "$TMP/home/.claude/hooks"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/home/.claude/hooks/metrics-collector.sh"
chmod +x "$TMP/home/.claude/hooks/metrics-collector.sh"
HOME="$TMP/home" STATE_DIR="$TMP/state3" PROJECTS_DIR="$TMP/p" bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_auto_scanner.sh:$LINENO" >&2; exit 1; }
if grep -qi "НЕ ОСМОТРЕНО" "$TMP/state3/scan-results.md" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T3]: отчёт не называет непросмотренное:"; cat "$TMP/state3/scan-results.md" 2>/dev/null
fi
# T3b — причины считаются ПОРОЗНЬ: один общий счётчик слил бы их обратно в один канал.
if grep -q "путь не восстановлен" "$TMP/state3/scan-results.md" 2>/dev/null \
   || grep -q "знаменатель полон" "$TMP/state3/scan-results.md" 2>/dev/null; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL [T3b]: разбивки по причине нет"
fi

echo ""
echo "auto-scanner tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
