#!/usr/bin/env bash
# test_completion_gate_open_items.sh — у ОТКРЫТОГО пункта «Проверка» обязана быть
# исполнимой и КРАСНОЙ (D263). Зелёная значит одно из двух и оба дефект: проблема уже
# решена — пункт пора закрывать; либо команда не о ней. Неисполнимая по оболочечному
# синтаксису — третий дефект: строка не проверяет ничего.
#
# ЗАЧЕМ ОТДЕЛЬНЫМ ФАЙЛОМ. Прежний предмет гейта (☑ обязана быть зелёной) держит
# test_completion_gate.sh, и его фикстуры остаются в силе — новое правило их не ломает.
# Здесь закрепляется ПРОТИВОПОЛОЖНЫЙ по знаку предмет и его контрпримеры.
#
# ЭТОТ ФАЙЛ — «Проверка» пункта D263, то есть его запускают completion-gate и
# scripts/backlog-archive.sh, а они ставят исполняемым командам BACKLOG_CHECKS_NESTED=1.
# По этому маркеру гейт выходит на строке 38 сразу. Поэтому run() поднимает хук через
# `env -u BACKLOG_CHECKS_NESTED`: без этого тест был бы зелёным из рук и красным из-под
# гейта, а пункт D263 после закрытия навсегда застрял бы в BACKLOG (архиватор не переносит
# ☑ с красной «Проверкой»).
set -uo pipefail
. "$(dirname "$0")/alerts-read.sh"

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/completion-gate.sh"
PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

# Доставка с 12 сентября 2026 — только очередь pending-alerts.txt (systemMessage снят: в
# мобильном клиенте он рендерится построчно). run() отдаёт очередь, чтобы ноги проверяли
# предмет, а не канал.
run() { # $1 backlog, $2 cwd (необязательно)
    # Очередь и дроссель чистятся перед вызовом: ноги читают то, что добавил именно он.
    # Дроссель гейта гасит повтор одного состава в сессии, а ноги T6 проверяют, что у
    # открытого пункта НЕТ кэша — без сброса они мерили бы дроссель, а не кэш.
    alerts_clear "$TMP/state" || true
    rm -f "$TMP/state"/completion-gate-fired-*.jsonl 2>/dev/null || true
    printf '{"session_id":"cgo1","cwd":"%s"}' "${2:-/}" \
      | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$1" CG_LOCAL_BACKLOG="" \
        STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_completion_gate_open_items.sh:$LINENO" >&2; exit 1; }
    alerts_of "$TMP/state"
}

assert_contains() { # $1 haystack, $2 needle, $3 label
    if grep -q -- "$2" <<< "$1"; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo "FAIL [$3]: нет «$2» в: $1"; fi
}
assert_not_contains() { # $1 haystack, $2 needle, $3 label
    if grep -q -- "$2" <<< "$1"; then FAIL=$((FAIL+1)); echo "FAIL [$3]: лишнее «$2» в: $1";
    else PASS=$((PASS+1)); fi
}
assert_empty() { # $1 out, $2 label
    if [ -z "$1" ]; then PASS=$((PASS+1));
    else FAIL=$((FAIL+1)); echo "FAIL [$2]: ожидалась тишина, получено: $1"; fi
}

# Преамбула с ```-блоком контракта: строка `**Проверка.** `команда`` внутри него —
# ШАБЛОН, а не команда пункта. Разбор пофайловый, преамбула не принадлежит ни одному
# пункту, и слово «команда» исполняться не должно (иначе rc=127 у несуществующей).
cat > "$TMP/BACKLOG.md" <<'EOF'
# BACKLOG

Контракт пункта:

```
**Результат.** <состояние мира>
**Проверка.** `команда` → 0
```

### D400 ☐ красная у открытого — норма
**Результат.** дефект ещё жив
**Проверка.** `false` → 0

### D401 ☐ зелёная у открытого — дефект
**Результат.** заявлено несделанным, а команда зелена
**Проверка.** `true` → 0

### D402 ◐ зелёная у взятого в работу — дефект
**Проверка.** `true` → 0

### D403 ☑ зелёная у закрытого — норма, прежний предмет не сломан
**Результат.** Фикстура: предмет ноги иной, строка добавлена для контракта закрытия.
**Проверка.** `true` → 0

### D404 ☐ неисполнимая по оболочечному синтаксису
**Проверка.** `touch d404-ran; if [` → 0

### D405 ☐ команда про ещё не написанный скрипт — законно
**Проверка.** `bash ./nope-xyz-not-written.sh` → 0

### D150 ☐ историческое, ниже CG_MIN_ID — контракт не вменяется задним числом
**Проверка.** `true` → 0

### D406 ☐ без строки «Проверка»
**Результат.** есть только результат
EOF

OUT=$(run "$TMP/BACKLOG.md")

# --- T1: зелёная у ☐ и у ◐ названа ---
assert_contains "$OUT" 'D401' "T1 зелёная у ☐ не названа"
assert_contains "$OUT" 'D402' "T1 зелёная у ◐ не названа"
assert_contains "$OUT" 'зелёная у открытого' "T1 нет объяснения канала"

# --- T2: контрпримеры молчат ---
assert_not_contains "$OUT" 'D400' "T2 красная у ☐ — норма"
assert_not_contains "$OUT" 'D403' "T2 зелёная у ☑ — норма"
assert_not_contains "$OUT" 'D405' "T2 rc=127 у ☐ — норма"
assert_not_contains "$OUT" 'D150' "T2 ниже CG_MIN_ID"
# Контракт перевернулся с закрытием D291: открытый пункт БЕЗ канонической строки
# «Проверка» теперь называется, а не проходит молча. Требование к ◐ существовало и
# раньше, но исполнителя у него не было ни одного: гейт делал `continue`, а архиватор
# до открытых пунктов не доходит. Нога кодировала прежнее поведение.
assert_contains "$OUT" 'D406' "T2 без строки «Проверка» — называется (D291)"

# --- T3: неисполнимая названа как синтаксис И НЕ ИСПОЛНЕНА ---
assert_contains "$OUT" 'D404' "T3 неисполнимая не названа"
assert_contains "$OUT" 'синтаксис' "T3 не назван род дефекта"
if [ -e "$TMP/d404-ran" ]; then
    FAIL=$((FAIL+1)); echo "FAIL [T3 неисполнимая ИСПОЛНИЛАСЬ]"
else PASS=$((PASS+1)); fi

# --- T4: шаблон контракта из преамбулы не исполняется и не называется ---
# Ищем ИМЕННО показ команды (в обратных кавычках), а не слово: слово «команда» стоит и в
# самом тексте сообщения («либо команда не о ней»), и утверждение на голое слово было бы
# ложно-красным — предмет замера не тот.
assert_not_contains "$OUT" '`команда`' "T4 шаблон преамбулы принят за команду"

# --- T5: канал открытых пунктов отделён от канала закрытых ---
cat > "$TMP/BOTH.md" <<'EOF'
### D410 ☑ красное закрытие
**Результат.** Фикстура: предмет ноги иной, строка добавлена для контракта закрытия.
**Проверка.** `false` → 0

### D411 ☐ зелёная у открытого
**Проверка.** `true` → 0
EOF
OUT2=$(run "$TMP/BOTH.md")
assert_contains "$OUT2" 'закрытие расходится' "T5 канал ☑ пропал"
assert_contains "$OUT2" 'ОТКРЫТОГО пункта не красная' "T5 канал ☐ пропал"
# Канал с 12 сентября 2026 — очередь, а не JSON с systemMessage (он рендерился у владельца
# построчно). Нога стала про ДОСТАВКУ: сообщение непусто и содержит оба канала выше.
[ -n "$OUT2" ] \
    && PASS=$((PASS+1)) || { FAIL=$((FAIL+1)); echo "FAIL [T5 очередь пуста]: $OUT2"; }

# --- T6: файл, чья единственная беда — зелёная у ☐, кэша НЕ получает ---
# У открытого пункта архиватор второго рубежа не даёт: напоминание каждый Stop и есть
# единственная неотвратимость. Канал #CG_OPEN вырезается из $_out, и без явного условия
# файл получал бы зелёный кэш — предупреждение прозвучало бы РОВНО ОДИН раз.
rm -f "$TMP/state"/completion-gate-*.ok
cat > "$TMP/ONLYOPEN.md" <<'EOF'
### D420 ☐ зелёная у открытого
**Проверка.** `true` → 0
EOF
OUT3=$(run "$TMP/ONLYOPEN.md")
assert_contains "$OUT3" 'D420' "T6 первый Stop"
OUT4=$(run "$TMP/ONLYOPEN.md")
assert_contains "$OUT4" 'D420' "T6 второй Stop — кэш отравлен зелёным"

# --- T7: ФОРМАТ живого BACKLOG проекта гейт разбирает целиком — на КОПИИ с подменёнными командами ---
# Прогон по настоящему файлу, а не по фикстуре: фикстура доказывает способность загореться, живой формат — что
# предмет тот же (класс test_guards_live). До D1231 нога судила САМ живой файл — «у открытых нет зелёной» и «покрытие
# в бюджете» — то есть состояние мира, а не механизм: набор краснел всякий раз, когда открытый пункт уже починен, но
# ждёт скептика, либо его «Проверка» дороже срока гейта (2 ноября 2026: D408 одна шла 68 с при CG_TIMEOUT 60). Эти
# состояния гейт называет СВОИМИ каналами на границе хода («зелёная у открытого», «не хватило бюджета»); здесь
# судится разбор: на копии, где каждая «Проверка» открытого пункта — `true`, гейт обязан назвать КАЖДЫЙ из них
# (зелёная у открытого либо ждёт скептика), а где `false` — ни одного; команды мгновенные, и цена живых пунктов
# вердикт не решает. Покрытие по бюджету и сроку одной команды судит фикстура `test_completion_gate_open_coverage.sh`.
REPO="$(cd "$HOOKS_DIR/.." && pwd)"
if [ -f "$REPO/BACKLOG.md" ]; then
    rm -f "$TMP/state"/completion-gate-*.ok
    # Питон — вне `$( … )`: bash 3.2 разбирает тело heredoc внутри подстановки и спотыкается о кавычки.
    python3 - "$REPO/BACKLOG.md" "$TMP/live-true.md" "$TMP/live-false.md" > "$TMP/live-ids.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
item = re.compile(r"^- ([☐◐☑⊘]) \*\*([A-Za-z]+-?[0-9][A-Za-z0-9.-]*)\*\*", re.M)
bq = chr(96)
check = re.compile(r"^(\s*\*\*Проверка\.\*\*\s*)" + bq + "[^" + bq + r"\n]*" + bq, re.M)
heads = list(item.finditer(text))
ids, outs = [], {"true": [], "false": []}
pos = 0
for i, m in enumerate(heads):
    stop = heads[i + 1].start() if i + 1 < len(heads) else len(text)
    block = text[m.start():stop]
    for k in outs:
        outs[k].append(text[pos:m.start()])
    # Подмена — у ВСЕХ пунктов (скептик opus по bffb0be7, M6): ☑ гейт исполняет без бюджета, и дорогая «Проверка»
    # закрытого, ждущего архиватора, иначе решала бы цену и исход ноги. Перечень для сверки — только открытые.
    if m.group(1) in "☐◐" and check.search(block):
        ids.append(m.group(2))
    for k in outs:
        outs[k].append(check.sub(lambda c, k=k: c.group(1) + bq + k + bq, block) if check.search(block) else block)
    pos = stop
for k in outs:
    outs[k].append(text[pos:])
open(sys.argv[2], "w", encoding="utf-8").write("".join(outs["true"]))
open(sys.argv[3], "w", encoding="utf-8").write("".join(outs["false"]))
print(" ".join(ids))
PY
    LIVE_N=$(cat "$TMP/live-ids.txt" 2>/dev/null)
    OUT5=$(CG_BUDGET_OPEN=600 run "$TMP/live-true.md")
    NAMED=$(printf '%s\n' "$OUT5" | sed -n 's/^\([A-Za-z]*-\{0,1\}[0-9][A-Za-z0-9.-]*\) (зелёная у открытого).*/\1/p'; \
            printf '%s\n' "$OUT5" | sed -n 's/.*ждёт финального скептика: \(.*\)\.$/\1/p' | tr ' ' '\n')
    MISS=""
    for _id in $LIVE_N; do grep -qx "$_id" <<< "$NAMED" || MISS="$MISS $_id"; done
    if [ -n "$LIVE_N" ] && [ -z "$MISS" ]; then PASS=$((PASS+1))
    else FAIL=$((FAIL+1)); echo "FAIL [T7 гейт не разобрал живой формат]: открытых с «Проверкой» ${LIVE_N:-0}, не названы на копии с true:${MISS:- (перечень пуст)}"; fi
    OUT6=$(CG_BUDGET_OPEN=600 run "$TMP/live-false.md")
    assert_not_contains "$OUT6" 'ОТКРЫТОГО пункта не красная' "T7b на копии с false гейт назвал открытый пункт зелёным"
    # Пропуск по ограде кольца — неполное покрытие (D503, раунд 3, атака 3): гейт, ничего не исполнивший, иначе
    # читался бы этой ногой как «ни одного зелёного».
    assert_not_contains "$OUT6" 'кольцо' "T7c гейт не исполнил «Проверки» (ограда кольца) — вердикт T7b ни о чём"
else
    PASS=$((PASS+1))
    PASS=$((PASS+1))
    PASS=$((PASS+1))
fi

# --- T9: ☑ пункта защитного слоя ждёт финального скептика (D1137) — не дефект, а свой канал ---
# Одно свойство меняется в каждой паре: путь `hooks/` против `scripts/`, каталог `hooks/` в корне против его отсутствия.
# Признак — у библиотеки (`backlog_needs_skeptic`), страж записи отбивает такое ☑ без строки «Скептик.».
for d in sk nosk; do mkdir -p "$TMP/$d"; done; mkdir -p "$TMP/sk/hooks"
sk_bl() { # $1 каталог, $2 адрес. Кэш гейта ключуется временем файла с точностью до секунды — сброс, как у T7: иначе
    # перезапись в ту же секунду читается «уже проверен» (нога T9c молчала через раз).
    rm -f "$TMP/state"/completion-gate-*.ok
    printf '%s\n\n' '# BACKLOG' "- ◐ **D9001** починка" "  **Повод.** \`$2\` пропускает запись." '  **Проверка.** `true` → 0' > "$1/BACKLOG.md"
}
sk_bl "$TMP/sk" 'hooks/x-guard.sh:10'; OUT=$(run "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ждёт финального скептика: D9001' "T9 ◐ защитного слоя с проходящей «Проверкой» не назван ожиданием скептика"
assert_not_contains "$OUT" 'ОТКРЫТОГО пункта не красная' "T9b ожидание скептика названо дефектом"
sk_bl "$TMP/sk" 'scripts/report.sh:5'; OUT=$(run "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ОТКРЫТОГО пункта не красная' "T9c ◐ вне hooks/ с проходящей «Проверкой» не назван дефектом"
assert_not_contains "$OUT" 'ждёт финального скептика' "T9d пункт вне hooks/ назван ожиданием скептика"
sk_bl "$TMP/nosk" 'hooks/usePay.ts:9'; OUT=$(run "$TMP/nosk/BACKLOG.md")
assert_contains "$OUT" 'ОТКРЫТОГО пункта не красная' "T9e дерево без hooks/ в корне: ожидание скептика вместо дефекта"
# T9f–T9l: второй круг скептика D1137. Ожидание решается ПУНКТОМ (M1): ◐, все строки «Проверки» зелены; один раз (L2).
sk_raw() { rm -f "$TMP/state"/completion-gate-*.ok; printf '%s\n' '# BACKLOG' '' "$@" > "$TMP/sk/BACKLOG.md"; }
sk_raw "- ☐ **D9001** починка" '  **Повод.** `hooks/x-guard.sh:10` пропускает запись.' '  **Проверка.** `true` → 0'
OUT=$(run "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ОТКРЫТОГО пункта не красная' "T9f невзятый ☐ защитного слоя с зелёной «Проверкой» не назван дефектом (M1)"
assert_not_contains "$OUT" 'ждёт финального скептика' "T9f2 невзятый ☐ назван ожиданием скептика (M1)"
sk_raw "- ◐ **D9001** починка" '  **Повод.** `hooks/x-guard.sh:10` пропускает запись.' '  **Проверка.** `true` → 0' '  **Проверка.** `false` → 0'
OUT=$(run "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ОТКРЫТОГО пункта не красная' "T9g зелёная строка рядом с красной не названа дефектом (M1)"
assert_not_contains "$OUT" 'ждёт финального скептика' "T9g2 пункт с красной строкой назван готовым к скептику (M1)"
# Свой номер: D9001 законно лёг в журнал срабатываний ногами T9f и T9g, и нога по нему судила бы фикстуру, а не гейт.
sk_raw "- ◐ **D9005** починка" '  **Повод.** `hooks/x-guard.sh:10` пропускает запись.' '  **Проверка.** `true` → 0' '  **Проверка.** `: ok` → 0'
OUT=$(run "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ждёт финального скептика: D9005\.' "T9h две зелёные строки ◐ — ожидание названо один раз (L2): $OUT"
grep -q '"item": *"D9005"' "$TMP/state/cg-open-fired.jsonl" 2>/dev/null \
    && { FAIL=$((FAIL+1)); echo "FAIL [T9i]: ожидание скептика записано в журнал срабатываний #CG_OPEN (Mi)"; } || PASS=$((PASS+1))
sk_raw '- ◐ **D9001** починка `hooks/x-guard.sh:10`' '  **Проверка.** `true` → 0' '' \
       '- ◐ **D9002** починка `hooks/y-guard.sh:3`' '  **Проверка.** `true` → 0'
OUT=$(run "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ждёт финального скептика: D9001 D9002\.' "T9j путь только в голове пункта не судится (Mh) либо назван не каждый пункт (Mj): $OUT"
# T9k (L1): новый ожидающий рядом с прежним #CG_OPEN не гаснет дросселем как повтор — состав несёт и канал ожидания.
rm -f "$TMP/state"/completion-gate-fired-*.jsonl
sk_raw '- ☐ **D9003** скрипт `scripts/r.sh:5`' '  **Проверка.** `true` → 0'
run_keep() { rm -f "$TMP/state"/completion-gate-*.ok; alerts_clear "$TMP/state"
    printf '{"session_id":"cgo1","cwd":"/"}' | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$1" CG_LOCAL_BACKLOG="" \
        STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_completion_gate_open_items.sh:$LINENO" >&2; exit 1; }; alerts_of "$TMP/state"; }
run_keep "$TMP/sk/BACKLOG.md" >/dev/null
sk_raw '- ☐ **D9003** скрипт `scripts/r.sh:5`' '  **Проверка.** `true` → 0' '' '- ◐ **D9004** починка `hooks/x-guard.sh:10`' '  **Проверка.** `true` → 0'
OUT=$(run_keep "$TMP/sk/BACKLOG.md")
assert_contains "$OUT" 'ждёт финального скептика: D9004' "T9k ожидание рядом с прежним #CG_OPEN погашено дросселем (L1)"
# T9l (Mj): ожидания копятся по ФАЙЛАМ — бэклог ClaudSoul и локальный бэклог проекта названы оба.
mkdir -p "$TMP/sk2/hooks"; rm -f "$TMP/state"/completion-gate-*.ok
sk_raw '- ◐ **D9006** починка `hooks/x-guard.sh:10`' '  **Проверка.** `true` → 0'
printf '%s\n' '# BACKLOG' '' '- ◐ **D9007** починка `hooks/y-guard.sh:3`' '  **Проверка.** `true` → 0' > "$TMP/sk2/BACKLOG.md"
alerts_clear "$TMP/state"; rm -f "$TMP/state"/completion-gate-fired-*.jsonl
printf '{"session_id":"cgo1","cwd":"/"}' | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$TMP/sk/BACKLOG.md" CG_LOCAL_BACKLOG="$TMP/sk2/BACKLOG.md" \
    STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_completion_gate_open_items.sh:$LINENO" >&2; exit 1; }
OUT=$(alerts_of "$TMP/state")
assert_contains "$OUT" 'ждёт финального скептика: D9006 D9007\.' "T9l ожидание из второго файла бэклога вытеснило первое (Mj)"

# --- T8: тихая деградация ---
OUT=$(run "$TMP/nope.md"); RC=$?
[ "$RC" -eq 0 ] && assert_empty "$OUT" "T8 нет файла" || { FAIL=$((FAIL+1)); echo "FAIL [T8 rc]"; }

echo "completion-gate open items: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
