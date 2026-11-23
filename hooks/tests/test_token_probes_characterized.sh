#!/usr/bin/env bash
# СУДИТ: hooks/pending-alerts-surface.sh
# test_token_probes_characterized.sh — характеризующий тест проб P4–P6 аудита экономии токенов
#     (docs/token-efficiency-audit.ru.md §3): закрепляет НЫНЕШНЕЕ поведение, а не контракт.
#
# Результат: у двух механизмов, чью цену в токенах назвал аудит, нынешнее поведение записано
#            ногами; у каждой ноги-предела названы этап плана (E1/E2), который его снимает, и то,
#            во что нога тогда переворачивается; положительные контроли остаются при любом этапе.
# Проверка результата: bash hooks/tests/test_token_probes_characterized.sh даёт 0
#
# Зачем характеризующий тест ПЕРЕД правкой. Этапы E1/E2 меняют поведение обоих механизмов; без
# записанного «как есть» нельзя отличить «предел снят» от «сломали соседнее» — правило
# docs/development.md (характеризующий тест перед рефактором). Ноги-пределы по построению зелёные
# СЕГОДНЯ и обязаны покраснеть на этапе, который их снимает, — тогда их ПЕРЕВОРАЧИВАЮТ, а не
# удаляют. Положительные контроли (P4 «ничего не теряется», P6+ «короткое тело целое») — страховка
# от «удалили все строки и тест зелен».
#
# Без git: ни один из двух механизмов дерево не читает. Живой ~/.claude не читается: HOME и
# STATE_DIR подменены песочницей; очередь хук берёт из $STATE_DIR/pending-alerts.txt, замок
# кладёт рядом с ней.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO/hooks/pending-alerts-surface.sh"
STORAGE="$REPO/mcp-server/storage.py"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
NAME="test_token_probes_characterized"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; echo "$NAME: 0 passed, 0 failed"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; echo "$NAME: 0 passed, 0 failed"; exit 0; }
[ -f "$HOOK" ] || { echo "SKIP: нет $HOOK (неполное дерево)"; echo "$NAME: 0 passed, 0 failed"; exit 0; }
[ -f "$STORAGE" ] || { echo "SKIP: нет $STORAGE (неполное дерево)"; echo "$NAME: 0 passed, 0 failed"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" STATE_DIR="$TMP/state"
mkdir -p "$HOME" "$STATE_DIR"
QUEUE="$STATE_DIR/pending-alerts.txt"

# surface <N> → N_SEEN: сколько строк очереди дошло до additionalContext за ОДИН вызов хука;
# CTX_LEN: длина этого текста. Строки по 100 символов с номером — как в пробах P4/P5 аудита.
surface() {
    python3 -c 'import sys
for i in range(1, int(sys.argv[1]) + 1): print("Q%03d " % i + "x" * 95)' "$1" > "$QUEUE"
    local out ctx
    out=$(printf '{"prompt":"hi","session_id":"s-char"}' | bash "$HOOK" 2>/dev/null)
    ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
    N_SEEN=$(printf '%s\n' "$ctx" | grep -c '^Q[0-9][0-9][0-9] x' || true)
    CTX_LEN=${#ctx}
}

# --- P4 — ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ, остаётся при любом этапе: ничего не теряется ---------------
# Проба P4 аудита: 10 строк по 100 символов → наружу все 10 (1118 символов с оформлением).
# Это не предел, а контракт очереди: строка, дописанная session-collector, доходит до владельца.
# Этап E2 (бюджет показа на ход) его ДОПОЛНЯЕТ, а не отменяет: что не влезло — остаётся в очереди.
surface 10
[ "$N_SEEN" = 10 ] && ok || bad "P4" "из 10 строк очереди наружу вышло $N_SEEN — строки теряются"
[ ! -s "$QUEUE" ] && ok || bad "P4b" "очередь после показа не пуста — показ не «ровно один раз»"

# --- P5 — ПРЕДЕЛ (не контракт): бюджета на объём одного показа нет ----------------------------
# Проба P5 аудита: 100 строк → наружу все 100 за один ход, 10568 символов; общего лимита на этом
# пути нет. Нога закрепляет ОТСУТСТВИЕ бюджета. Снимает этап E2 (бюджет строк/символов на ход):
# тогда P5/P5b/P5c переворачиваются в «за один ход не больше бюджета, остаток лежит в очереди и
# выходит на следующих ходах, сумма по ходам — 100». Пока E2 не заявлен, красная P5 значит
# «показ стал терять строки», и это дефект, а не снятый предел.
surface 100
[ "$N_SEEN" = 100 ] && ok || bad "P5" "из 100 строк за один ход вышло $N_SEEN: бюджет появился (переверни ногу под E2) либо строки теряются"
[ "$CTX_LEN" -gt 10000 ] && ok || bad "P5b" "объём одного показа $CTX_LEN символов при 100 строках по 100 — предел изменился без переворота ноги"
[ ! -s "$QUEUE" ] && ok || bad "P5c" "после одного показа очередь не пуста — остаток появился без переворота ноги"

# --- P6 — ПРЕДЕЛ (не контракт): storage.search режет content до 500 символов ------------------
# Проба P6 аудита: тело 500 символов + существенное условие применения → наружу ровно 500,
# условие отсутствует целиком (`storage.py`, `content[:500]`). Функция извлекается через AST и
# исполняется на подставном курсоре: sqlite-vec и модель эмбеддингов не нужны и не трогаются.
# Снимает этап E1 (смысловой фрагмент вместо первых N символов): тогда P6/P6b переворачиваются в
# «условие применения в выдаче есть». Положительный контроль P6+: тело короче 500 отдаётся целиком
# — остаётся при любом этапе.
P6_OUT=$(python3 - "$STORAGE" <<'PY' 2>&1
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "search")
# НАСТОЯЩИЕ sqlite3 и Optional, А НЕ ЗАГЛУШКИ (17 сентября 2026, красный CI коммита b528a43).
# Сигнатура `search` несёт аннотацию `sqlite3.Connection`. Python 3.12 раннера вычисляет аннотации
# при определении функции, и заглушка `"sqlite3": None` падала AttributeError; локальный 3.14
# откладывает их вычисление, поэтому на своей машине нога была зелёной. Оба модуля — stdlib,
# базы нога по-прежнему не открывает: курсор подставной.
import sqlite3
from typing import Optional
ns = {"Optional": Optional, "_serialize_f32": lambda v: b"", "sqlite3": sqlite3}
exec(compile(ast.Module(body=[fn], type_ignores=[]), "storage.search", "exec"), ns)
COND = " НО НЕ ПРИМЕНЯТЬ, если файл под замком другой сессии"
class Cur:
    def __init__(self, rows): self.rows = rows
    def fetchall(self): return self.rows
class DB:
    def __init__(self, body): self.body = body
    def execute(self, *a, **k):
        return Cur([(1, 0.1, "k.md", "k", "pattern", 4, 3, "active", "d", "t", self.body)])
long_body = "A" * 500 + COND
short_body = "B" * 200 + COND
c_long = ns["search"](DB(long_body), [0.0], limit=5)[0]["content"]
c_short = ns["search"](DB(short_body), [0.0], limit=5)[0]["content"]
print("long_len", len(c_long))
print("long_cond", int("НЕ ПРИМЕНЯТЬ" in c_long))
print("short_whole", int(c_short == short_body))
PY
)
LONG_LEN=$(printf '%s\n' "$P6_OUT" | awk '$1 == "long_len" {print $2}')
LONG_COND=$(printf '%s\n' "$P6_OUT" | awk '$1 == "long_cond" {print $2}')
SHORT_WHOLE=$(printf '%s\n' "$P6_OUT" | awk '$1 == "short_whole" {print $2}')
[ -n "$LONG_LEN" ] && [ -n "$LONG_COND" ] && [ -n "$SHORT_WHOLE" ] || bad "P6-frame" "функция search не извлеклась или не исполнилась: $P6_OUT"
[ "${LONG_LEN:-}" = 500 ] && ok || bad "P6" "предел изменился: длина выдачи ${LONG_LEN:-?} при теле 500+условие (E1 ещё не заявлен — переверни ногу, если это он)"
[ "${LONG_COND:-}" = 0 ] && ok || bad "P6b" "условие применения после 500-го символа дошло до выдачи — предел снят без переворота ноги"
[ "${SHORT_WHOLE:-}" = 1 ] && ok || bad "P6+" "положительный контроль: тело короче 500 отдано не целиком"

echo "$NAME: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
