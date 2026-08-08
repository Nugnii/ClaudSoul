#!/usr/bin/env bash
# test_session_collector.sh — характеризующий тест Stop-финализатора.
# Хук центральный (финализация сессии, напоминания /learn, pending-alerts, silence debt),
# но был без своего теста (F8). Полный прогон зависит от реестра/activity-flush, поэтому
# тест проверяет безопасный инвариант: на пустых transcript/cwd хук завершает Stop без
# падения (rc=0) и при наличии/отсутствии session_id. Изоляция STATE_DIR.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/session-collector.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_rc0() { if [ "$1" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

run() {  # $1=session_id — пустые transcript/cwd → activity_flush пропускается
    printf '{"session_id":"%s","transcript_path":"","cwd":""}' "$1" \
        | STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
}

# Stop с session_id (fresh, без накопленных алертов) → завершает без падения
run "stop-sid-fresh"; assert_rc0 "$?" "T1 Stop with SID → rc=0"

# Stop без session_id → завершает без падения
run ""; assert_rc0 "$?" "T2 Stop without SID → rc=0"

# повторный Stop той же сессии → без падения (idempotent finalize)
run "stop-sid-fresh"; assert_rc0 "$?" "T3 repeat Stop → rc=0"

# === T4-T6: долг проекта всплывает из BACKLOG.md (v1.14.0) ===
#
# Зачем. За одну сессию накопилось 30 незакрытых пунктов, и при сборке списка выяснилось:
# большинство были названы вслух в тот же момент, когда пропущены. `BACKLOG.md` существовал,
# но его не читал ни один хук — только скилл упоминал текстом. Отложенное испарялось не
# потому, что его не записывали, а потому что записанное некому было поднять.
#
# Обе стороны обязательны: есть открытые → видно; нет открытых или нет файла → тишина.
#
# Путь к BACKLOG.md — абсолютный, а не от каталога сессии (v1.15.1). До этого хук читал
# `${PAYLOAD_CWD}/BACKLOG.md`, и весь контур долга существовал только пока работа шла
# внутри самого ClaudSoul; из любого другого проекта долг молчал. Развёртка D38 назвала
# это тем же классом, что и всё остальное в ней: обязанность есть, а наступить не может.
# Поэтому фикстура подаётся через `CLAUDSOUL_BACKLOG`, а не через `cwd`, — прежний ввод
# и был дефектом.
assert_contains() {
    if printf '%s' "$1" | grep -qF -- "$2"; then PASS=$((PASS + 1))
    else FAIL=$((FAIL + 1)); echo "FAIL [$3]: не найдено '$2' в: $(printf '%s' "$1" | head -c 160)"; fi
}
assert_no() {
    if printf '%s' "$1" | grep -qF -- "$2"; then FAIL=$((FAIL + 1)); echo "FAIL [$3]: неожиданно найдено '$2'"
    else PASS=$((PASS + 1)); fi
}
_backlog_run() { # содержимое BACKLOG.md (пусто = файла нет)
    local proj="$TMP/proj-$RANDOM"
    mkdir -p "$proj"
    [ -n "$1" ] && printf '%s\n' "$1" > "$proj/BACKLOG.md"
    # cwd подаётся ЧУЖОЙ (пустой каталог) — так проверяется, что долг виден из любого
    # проекта, а не только из ClaudSoul. Замер идёт по несуществующему пути, чтобы
    # строка о просроченных не смешивалась со строкой о долге.
    jq -cn --arg s "bl$RANDOM" '{session_id:$s, cwd:"/nonexistent-project"}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_BACKLOG="$proj/BACKLOG.md" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
          bash "$HOOK" 2>/dev/null
}
OUT=$(_backlog_run '- ☐ **D1** раз
- ☐ **D2** два
- ☑ **D0** сделано')
assert_contains "$OUT" "2 открытых пункт" "T4: два открытых пункта → показаны, закрытый не считается"
assert_contains "$OUT" "BACKLOG.md" "T4b: назван источник"

OUT=$(_backlog_run '- ☑ **D1** сделано')
assert_no "$OUT" "открытых пункт" "T5: всё закрыто → про долг молчит"

OUT=$(_backlog_run "")
assert_no "$OUT" "открытых пункт" "T6: BACKLOG.md нет (чужой проект) → молчит"

# T7: пункт «в работе» (◐) считается открытым. По легенде BACKLOG.md обе метки означают
# «не сделано», но хук считал только ☐ — и перевод пункта в работу ГАСИЛ алерт. Долг
# умолкал ровно тогда, когда за него взялись и остановились: худший момент для тишины.
OUT=$(_backlog_run '- ☐ **D1** раз
- ◐ **D2** взят в работу
- ☑ **D0** сделано')
assert_contains "$OUT" "2 открытых пункт" "T7: ◐ считается наравне с ☐"

# T8: отрицательный контроль на сам счёт — пункт в работе БЕЗ открытых всё равно виден.
# Без этого случая T7 проходил бы и при подсчёте одного лишь ☐.
OUT=$(_backlog_run '- ◐ **D2** только в работе
- ☑ **D0** сделано')
assert_contains "$OUT" "1 открытых пункт" "T8: один только ◐ — долг не молчит"

# === T9-T12: долг инициированного проекта (локальный BACKLOG.md по cwd, 2026-08-07)
# и архивная секция (правка параллельной сессии — здесь получает тест).
_backlog_run2() { # $1 ClaudSoul-BACKLOG, $2 локальный BACKLOG, $3 cwd_mode(local|claudsoul)
    local cs="$TMP/cs-$RANDOM" loc="$TMP/loc-$RANDOM" cwd
    mkdir -p "$cs" "$loc"
    [ -n "$1" ] && printf '%s\n' "$1" > "$cs/BACKLOG.md"
    [ -n "$2" ] && printf '%s\n' "$2" > "$loc/BACKLOG.md"
    case "$3" in claudsoul) cwd="$cs" ;; *) cwd="$loc" ;; esac
    jq -cn --arg s "bl$RANDOM" --arg c "$cwd" '{session_id:$s, cwd:$c}' \
        | STATE_DIR="$TMP/state" \
          CLAUDSOUL_ROOT="$cs" \
          CLAUDSOUL_BACKLOG="$cs/BACKLOG.md" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" \
          bash "$HOOK" 2>/dev/null
}

# T9: оба долга видны одновременно — кросс-проектный И локальный.
OUT=$(_backlog_run2 '- ☐ **D1** системный' '- ☐ **L1** локальный
- ☐ **L2** локальный два' local)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md — долг проекта" "T9a: ClaudSoul-долг виден из чужого проекта"
assert_contains "$OUT" "2 открытых пункт(ов) в BACKLOG.md этого проекта" "T9b: локальный долг проекта виден"

# T10: сессия в самом ClaudSoul → локальный не дублирует системный.
OUT=$(_backlog_run2 '- ☐ **D1** системный' '' claudsoul)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md — долг проекта" "T10a: системный долг есть"
assert_no "$OUT" "этого проекта" "T10b: двойного счёта в ClaudSoul нет"

# T11: у локального проекта нет BACKLOG.md → локальной строки нет (не инициирован).
OUT=$(_backlog_run2 '- ☐ **D1** системный' '' local)
assert_no "$OUT" "этого проекта" "T11: без BACKLOG.md локальный контур молчит"

# T12: архивная секция не считается — в обоих файлах (тест правки параллельной сессии).
OUT=$(_backlog_run2 '- ☐ **D1** открыт
## Архив
- ☐ **D9** лежит в архиве' '- ☐ **L1** открыт
## Archive
- ◐ **L9** в архиве' local)
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md — долг проекта" "T12a: архив ClaudSoul не считается"
assert_contains "$OUT" "1 открытых пункт(ов) в BACKLOG.md этого проекта" "T12b: архив локального не считается"

# T13: подсказка про устаревший свод — если в ClaudSoul-бэклоге след project-health.
OUT=$(_backlog_run2 '- ☐ **D1** раз (см. docs/project-health-2026-06-21.md)' '' local)
assert_contains "$OUT" "Свод мог устареть" "T13: подсказка ре-аудита при маркере project-health"

echo ""
echo "session-collector tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
