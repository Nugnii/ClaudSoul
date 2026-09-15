#!/usr/bin/env bash
# test_completion_gate_open_fired.sh — у срабатывания канала #CG_OPEN есть ИСХОД, и ставит
# его механизм закрытия пункта, а не рука (D264). Журнал `cg-open-fired.jsonl` знает не
# только ЧТО сработало, но и чем кончилось: ☑ с зелёной «Проверкой» → confirmed,
# переписанная у открытого команда → rewritten, ⊘ → waived, унесённое в архив → confirmed.
#
# Ключ записи — ТРОЙКА (файл, пункт, команда), и резолвер трогает только записи своего
# файла. Гейт разбирает ДВА бэклога, и оба бывают доверенными (второй — через
# CG_LOCAL_BACKLOG, то есть акт владельца); без координаты файла второй бэклог с тем же
# D-номером ставил записям первого чужие исходы — портилась ровно та точность, ради
# которой журнал и заведён (T6).
#
# Сюда же — замер `open-check-precision` из scripts/measurements.tsv (T7): он читает этот
# журнал, и его зелень обязана зависеть от НАЛИЧИЯ ИСХОДОВ, а не от того, что журнала нет
# или что метку переименовали.
#
# ЭТОТ ФАЙЛ может исполняться из-под гейта («Проверка» пункта), поэтому run() поднимает
# хук через `env -u BACKLOG_CHECKS_NESTED` — как test_completion_gate_open_items.sh.
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HOOKS_DIR/.." && pwd)"
HOOK="$HOOKS_DIR/completion-gate.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/repo"
LOG="$TMP/state/cg-open-fired.jsonl"

# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний. Очередь и дроссель гейта чистятся перед вызовом.
_reset() { : > "$TMP/state/pending-alerts.txt" 2>/dev/null || true; rm -f "$TMP/state"/completion-gate-fired-*.jsonl 2>/dev/null || true; }
_queue() { cat "$TMP/state/pending-alerts.txt" 2>/dev/null; }
run() { # $1 backlog
    _reset
    printf '{"session_id":"cgf1","cwd":"/"}' \
      | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$1" CG_LOCAL_BACKLOG="" \
        STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
    _queue
}
run2() { # $1 главный бэклог, $2 локальный (оба доверенные: путь из окружения)
    _reset
    printf '{"session_id":"cgf1","cwd":"/"}' \
      | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$1" CG_LOCAL_BACKLOG="$2" \
        STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
    _queue
}
outcome() { # $1 item, $2 cmd → outcome записи
    jq -r --arg i "$1" --arg c "$2" 'select(.item==$i and .cmd==$c) | .outcome' "$LOG" 2>/dev/null
}
assert_contains() { # $1 haystack, $2 needle, $3 label
    if grep -q -- "$2" <<< "$1"; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет «$2» в: $1"; fi
}
assert_not_contains() { # $1 haystack, $2 needle, $3 label
    if grep -q -- "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: лишнее «$2» в: $1";
    else PASS=$((PASS+1)); fi
}

B="$TMP/repo/BACKLOG.md"
# Семь открытых пунктов, у всех «Проверка» зелёная либо неисполнимая: канал срабатывает
# на каждом; исходы потом разводятся по-разному.
cat > "$B" <<'EOF2'
# BACKLOG

### D500 ☐ закроется той же командой
**Проверка.** `true` → 0

### D501 ☐ команду перепишут, пункт останется открытым
**Проверка.** `true` → 0

### D502 ☐ уедет в архив
**Проверка.** `true` → 0

### D503 ☐ синтаксис починят
**Проверка.** `if [` → 0

### D504 ☐ закроется с переписанной командой
**Проверка.** `true` → 0

### D505 ☐ останется как есть
**Проверка.** `true` → 0

### D506 ☐ откажутся
**Проверка.** `true` → 0
EOF2

# --- T1: срабатывание оставляет запись с ключом (файл, пункт, команда) и исходом pending ---
OUT=$(run "$B")
assert_contains "$OUT" 'D500' "T1 канал не сработал"
assert_contains "$(outcome D500 true)" 'pending' "T1 запись D500 не pending"
assert_contains "$(outcome D503 'if [')" 'pending' "T1 запись синтаксиса не pending"
N1=$(wc -l < "$LOG" | tr -d ' ')
[ "$N1" = 7 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T1 записей $N1, ожидалось 7]"; }

# --- T2: единица счёта — тройка, не Stop: второй прогон на том же файле записей не множит ---
run "$B" >/dev/null
N2=$(wc -l < "$LOG" | tr -d ' ')
[ "$N2" = "$N1" ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T2 записей стало $N2]"; }

# --- T3: мир двинулся — исходы ставит механизм ---
cat > "$B" <<'EOF2'
# BACKLOG

### D500 ☑ закрыт той же командой
**Проверка.** `true` → 0

### D501 ☐ команда переписана, пункт открыт
**Проверка.** `false` → 0

### D503 ☐ синтаксис починен
**Проверка.** `false` → 0

### D504 ☑ закрыт с переписанной командой
**Проверка.** `true && true` → 0

### D505 ☐ как был
**Проверка.** `true` → 0

### D506 ⊘ отказ
**Вердикт.** цена названа
EOF2
cat > "$TMP/repo/BACKLOG-archive.md" <<'EOF2'
# BACKLOG — архив

## Перенесено

- ☑ **D502** уехал в архив
  **Проверка.** `true` → 0
EOF2
touch "$B"
run "$B" >/dev/null
assert_contains "$(outcome D500 true)" 'confirmed' "T3 ☑ с зелёной → confirmed"
assert_contains "$(outcome D501 true)" 'rewritten' "T3 переписанная у открытого → rewritten"
assert_contains "$(outcome D502 true)" 'confirmed' "T3 унесённое в архив → confirmed"
assert_contains "$(outcome D503 'if [')" 'confirmed' "T3 синтаксис починен → confirmed"
assert_contains "$(outcome D504 true)" 'confirmed' "T3 ☑ с переписанной → confirmed"
assert_contains "$(jq -r 'select(.item=="D504") | .cmd_changed' "$LOG")" 'true' "T3 D504 без пометки cmd_changed"
assert_contains "$(outcome D505 true)" 'pending' "T3 открытый с той же командой должен остаться pending"
assert_not_contains "$(outcome D505 true)" 'confirmed' "T3 pending подделан в confirmed"
assert_contains "$(outcome D506 true)" 'waived' "T3 ⊘ → waived"

# --- T4: ☑ с КРАСНОЙ «Проверкой» исход не получает (закрытие ещё не закрытие) ---
cat > "$B" <<'EOF2'
### D505 ☑ закрыт, но команда красная
**Проверка.** `false` → 0
EOF2
run "$B" >/dev/null
assert_contains "$(outcome D505 true)" 'pending' "T4 красное ☑ дало исход"

# --- T4b: исход ставит ПРОГОН, а не метка. Команда та же, покраснела от движения мира ---
# (флаг снят), метка ☑ — записи это исхода не даёт: иначе confirmed ставился бы по метке.
B2="$TMP/repo2/BACKLOG.md"; mkdir -p "$TMP/repo2"
touch "$TMP/flag"
cat > "$B2" <<EOF2
### D510 ☐ зелена, пока флаг на месте
**Проверка.** \`test -f $TMP/flag\` → 0
EOF2
run "$B2" >/dev/null
assert_contains "$(outcome D510 "test -f $TMP/flag")" 'pending' "T4b запись D510 не заведена"
rm -f "$TMP/flag"
cat > "$B2" <<EOF2
### D510 ☑ метка закрыта, а команда та же и теперь красная
**Проверка.** \`test -f $TMP/flag\` → 0
EOF2
touch "$B2"
run "$B2" >/dev/null
assert_not_contains "$(outcome D510 "test -f $TMP/flag")" 'confirmed' "T4b исход поставлен по метке, а не по прогону"

# --- T5: недоверенный бэклог (путь из cwd, D244) журнала не трогает: ни записи, ни исхода ---
mkdir -p "$TMP/evil"; printf '# Чужой проект\n' > "$TMP/evil/CLAUDE.md"
cat > "$TMP/evil/BACKLOG.md" <<'EOF2'
### D505 ☑ чужой файл объявляет закрытие
**Проверка.** `true` → 0

### D507 ☐ чужой открытый с зелёной
**Проверка.** `true` → 0
EOF2
printf '{"session_id":"cgf1","cwd":"%s"}' "$TMP/evil" \
  | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$TMP/none.md" CG_LOCAL_BACKLOG="" \
    STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
assert_contains "$(outcome D505 true)" 'pending' "T5 чужой файл поставил исход"
assert_not_contains "$(jq -r '.item' "$LOG")" 'D507' "T5 чужой файл записан в журнал"

# --- T6: два ДОВЕРЕННЫХ бэклога с одним D-номером. Записи главного файла — не предмет
# разбора локального: у ключа есть координата файла, и резолвер чужих записей не трогает.
B6="$TMP/repo6/BACKLOG.md"; mkdir -p "$TMP/repo6" "$TMP/local6"
cat > "$B6" <<'EOF2'
### D600 ☐ главный файл, зелёная
**Проверка.** `true` → 0

### D601 ☐ главный файл, зелёная
**Проверка.** `true` → 0
EOF2
run "$B6" >/dev/null
cat > "$TMP/local6/BACKLOG.md" <<'EOF2'
# Локальный долг проекта

- ☐ **D600** тот же номер, строки «Проверка» нет вовсе

- ⊘ **D601** тот же номер, отказ
  **Вердикт.** цена названа
EOF2
touch "$B6"
run2 "$B6" "$TMP/local6/BACKLOG.md" >/dev/null
assert_contains "$(outcome D600 true)" 'pending' "T6 локальный файл переписал исход D600 главного"
assert_contains "$(outcome D601 true)" 'pending' "T6 локальный файл переписал исход D601 главного"

# --- T8: номер, встреченный в файле ДВАЖДЫ, исхода не получает ---
# Прожарка 3 сентября 2026: строка, повторяющая форму заголовка пункта, законна в этом
# файле — пункты цитируют контракт. До правки by_id перетирался последним вхождением, и
# метка ВТОРОГО блока решала исход ПЕРВОГО: настоящий открытый D260 получал необратимый
# `confirmed`, оставаясь ☐. Дубль номера ловит backlog-vanish-check; здесь достаточно НЕ
# делать по нему необратимую запись.
B8="$TMP/b8.md"
cat > "$B8" <<'MD'
# BACKLOG

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D800 ☐ настоящий открытый пункт
  **Проверка.** `true` → 0
MD
run "$B8" >/dev/null
assert_contains "$(outcome D800 true)" 'pending' "T8 первый прогон завёл запись pending"
cat > "$B8" <<'MD'
# BACKLOG

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D800 ☐ настоящий открытый пункт
  **Проверка.** `true` → 0

### D801 ☑ чужой закрытый пункт
  **Проверка.** `true` → 0
### D800 ☑ цитата, повторяющая форму заголовка
  **Проверка.** `true` → 0
MD
run "$B8" >/dev/null
assert_contains "$(outcome D800 true)" 'pending' "T8 дубль номера проставил исход настоящему открытому пункту"

# --- T9: многосоставный ☑ подтверждается только когда зелены ВСЕ его команды ---
# Прожарка 3 сентября 2026: гейт печатал «закрытие расходится со своим же критерием» и в
# том же прогоне ставил `confirmed` — телеметрия точности признака получала подтверждение
# от закрытия, которое сама же объявила несостоявшимся.
B9="$TMP/b9.md"
cat > "$B9" <<'MD'
# BACKLOG

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D900 ☐ пункт
  **Проверка.** `true` → 0
MD
run "$B9" >/dev/null
assert_contains "$(outcome D900 true)" 'pending' "T9 первый прогон завёл запись pending"
cat > "$B9" <<'MD'
# BACKLOG

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D900 ☑ пункт с двумя строками, вторая красная
  **Проверка.** `true` → 0
  **Проверка.** `false` → 0
MD
OUT9=$(run "$B9")
assert_contains "$(outcome D900 true)" 'pending' "T9 красная вторая «Проверка» не помешала исходу confirmed"
assert_contains "$OUT9" 'расходится' "T9 гейт промолчал о красном закрытии"
cat > "$B9" <<'MD'
# BACKLOG

**Легенда статусов:** ☐ todo · ◐ in-progress · ☑ done · ⊘ waived

### D900 ☑ пункт, обе строки зелёные
  **Проверка.** `true` → 0
  **Проверка.** `true; true` → 0
MD
run "$B9" >/dev/null
assert_contains "$(outcome D900 true)" 'confirmed' "T9 честное закрытие исхода не получило"

# --- T7: замер `open-check-precision` (scripts/measurements.tsv) читает ЭТОТ журнал.
# Команда берётся из реестра, а не переписывается здесь: судится строка реестра.
MCMD=$(awk -F'\t' '$1=="open-check-precision"{print $3}' "$REPO/scripts/measurements.tsv")
mkfix() { # $1 каталог-HOME, $2 сколько записей, $3 исход последней
    mkdir -p "$TMP/$1/.claude/hooks/state"
    : > "$TMP/$1/.claude/hooks/state/cg-open-fired.jsonl"
    local i=1 o
    while [ "$i" -le "$2" ]; do
        o=confirmed; [ "$i" = "$2" ] && o="$3"
        printf '{"ts":"t","session":"s","file":"/f","item":"D%d","kind":"green","cmd":"c%d","outcome":"%s","seen":1}\n' \
            "$i" "$i" "$o" >> "$TMP/$1/.claude/hooks/state/cg-open-fired.jsonl"
        i=$((i+1))
    done
}
mrc() { HOME="$TMP/$1" eval "$MCMD" >/dev/null 2>&1; echo $?; }
mkfix m_full 20 confirmed
mkfix m_pend 20 pending
mkfix m_named 20 unresolved
mkdir -p "$TMP/m_none/.claude/hooks/state"
[ "$(mrc m_full)" = 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 20 исходов из словаря дали не 0]"; }
[ "$(mrc m_pend)" != 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 одна pending прошла зелёной]"; }
[ "$(mrc m_none)" != 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 отсутствие журнала прошло зелёным: замер зеленеет от пустоты]"; }
[ "$(mrc m_named)" != 0 ] && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T7 переименованная метка исхода прошла зелёной]"; }

echo "completion-gate open fired: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
