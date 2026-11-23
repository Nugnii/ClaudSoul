#!/usr/bin/env bash
# СУДИТ: hooks/tests/drift-check.sh
# test_drift_reg_handler_mode.sh — пара «регистрация хуков» видит режим записи (фон/синхронно).
#
# Результат: запись хука, у которой в установке другой режим исполнения, чем объявлен в
#            install.sh (`"async": true` против синхронной), — это DRIFT, а не «совпадает»
# Проверка результата: bash hooks/tests/test_drift_reg_handler_mode.sh даёт 0
#
# Зачем (D1001, 17 октября 2026). Единица сверки пары — «событие + набор инструментов» (D317),
# прочие поля записи в неё не входили. D1000 перевёл два хука Stop в фон полем `async` в
# install.sh, и сухой прогон переноса (`scripts/sync-drifted.sh --dry-run`) ответил «дрейф
# ТОЛЬКО в seed знаний»: смена режима невидима сверщику, значит и перенос её не применит —
# починка осталась бы в репозитории, а владелец ждал бы по-прежнему. Тот же род, что слепота
# к matcher 5 сентября 2026: единица сравнения уже предмета.
# Положительный контроль (нога T1) обязателен: без него «пара молчит» неотличимо от «пара
# сломана» (pattern-frame-without-a-positive-control).
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }
command -v python3 >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || { echo "SKIP: нужны python3 и jq"; exit 0; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

# Объявленная конфигурация — из install.sh, тем же извлечением, что у самой пары.
# Режим правится у ПЕРВОЙ объявленной записи Stop: от её имени нога не зависит.
_mk_settings() {  # <каталог> <режим: same | drop-async | add-async>
    mkdir -p "$1"
    python3 - "$REPO/install.sh" "$1/settings.json" "$2" <<'PY'
import json, re, sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.loads(re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", open(src).read(), re.S).group(1))
stop = [h for g in cfg["hooks"].get("Stop", []) for h in g.get("hooks", [])]
if mode == "drop-async":
    for h in cfg["hooks"].values():
        for g in h:
            for x in g.get("hooks", []):
                x.pop("async", None)
elif mode == "add-async":
    sync = [h for h in stop if not h.get("async")]
    sync[0]["async"] = True
json.dump(cfg, open(dst, "w"))
PY
}
_reg_status() {  # <CLAUDE_HOME> → статус пары «регистрация хуков»
    CLAUDE_HOME="$1" CLAUDSOUL_REPO="$REPO" bash "$DRIFT" 2>/dev/null \
        | LC_ALL=C awk -F'|' '$2 == "регистрация хуков" { print $1 }'
}

# --- T1: положительный контроль — установка равна объявленному → OK ---
_mk_settings "$TMP/same" same
S=$(_reg_status "$TMP/same")
if [ "$S" = "OK" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T1]: равная установка дала «${S}», ждали OK"; fi

# --- T2: объявлен фон, а в установке запись синхронная → DRIFT ---
if python3 -c "import re,json,sys; c=json.loads(re.search(r\"HOOKS_CONFIG='(\{.*?\n\})'\", open(sys.argv[1]).read(), re.S).group(1)); sys.exit(0 if any(x.get('async') for ev in c['hooks'].values() for g in ev for x in g.get('hooks', [])) else 1)" "$REPO/install.sh"; then
    _mk_settings "$TMP/drop" drop-async
    S=$(_reg_status "$TMP/drop")
    if [ "$S" = "DRIFT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T2]: фон объявлен, в установке нет — пара дала «${S}», ждали DRIFT"; fi
else
    echo "SKIP [T2]: в install.sh нет ни одной фоновой записи"
fi

# --- T3: в установке фон, а объявлена синхронная запись → DRIFT ---
_mk_settings "$TMP/add" add-async
S=$(_reg_status "$TMP/add")
if [ "$S" = "DRIFT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "FAIL [T3]: в установке фон, объявлено синхронно — пара дала «${S}», ждали DRIFT"; fi

echo "drift reg handler mode: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
