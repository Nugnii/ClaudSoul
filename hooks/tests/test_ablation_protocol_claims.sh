#!/usr/bin/env bash
# test_ablation_protocol_claims.sh — у числовых утверждений протокола ablation есть сверщик:
# число берётся ИЗ ДОКУМЕНТА, поведение — у кода, расхождение краснеет.
#
# Результат: каждое число протокола (docs/ablation-protocol.md), у которого есть исполнитель
#            в scripts/ablation/, совпадает с ПОВЕДЕНИЕМ исполнителя на фикстуре; величины
#            без исполнителя названы здесь поимённо, а не забыты
# Проверка результата: bash hooks/tests/test_ablation_protocol_claims.sh даёт 0
#
# Направление истины здесь ОБРАТНОЕ реестру scripts/doc-claims.tsv: prereg-протокол —
# источник, код обязан ему соответствовать, и `docs-refresh-claims.sh run` переписывать
# протокол из мира не имеет права (он затёр бы δ значением кода — ровно то, что prereg
# запрещает). Поэтому сверщик — тест, который читает документ и краснеет, а не реестр,
# который подставляет. Число извлекается из документа регулярным выражением по месту
# употребления; выражение, не нашедшее места, — находка («утверждение исчезло»), не тишина.
#
# Повод (D283, 2 сентября 2026): расхождение двух якорей заморозки (D276) прожило шесть
# дней, «не построены» в §15 — восемнадцать, вердикт у описательного Δ_memory — до правки
# руками: протокол не читал ни один тест, и каждое расхождение находил человек.
#
# Величины БЕЗ исполнителя, названные, чтобы отсутствие проверки не читалось как проверка:
# «не более одной пары в день» (§5), потолок 500k токенов (§11: парсер считает, не
# отсекает), якорь заморозки (§6/§11: правило о МОМЕНТЕ; его держит «Проверка» D276 через
# backlog-recheck). Условие снятия: у величины появится исполнитель — она переезжает сюда.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DOC="${ABLATION_PROTOCOL:-$ROOT/docs/ablation-protocol.md}"
AB="${ABLATION_SCRIPTS:-$ROOT/scripts/ablation}"
[ -f "$DOC" ] || { echo "FAIL: нет $DOC"; exit 1; }
for f in pair-analyze.py sampler.py journal.sh phase.sh pair.sh; do
    [ -f "$AB/$f" ] || { echo "FAIL: нет $AB/$f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
assert_contains() {
    if grep -Fq -- "$2" <<< "$1"; then ok; else bad "$3" "'$2' not in: $1"; fi
}
assert_empty() { if [ -z "$1" ]; then ok; else bad "$2" "expected empty: $1"; fi; }

# Число из документа по месту употребления: первая группа выражения. Пусто — утверждение
# исчезло из текста, и это находка, а не молчаливый пропуск: `need` считает её провалом
# ВНЕ подстановки команды (счётчик в $(...) терялся бы вместе с подоболочкой).
claim() { grep -oE "$1" "$DOC" | head -1 | sed -E "s/$1/\\1/"; }
need()  { [ -n "$2" ] && return 0; bad "$1" "утверждение не найдено в документе: $3"; return 1; }
# Словесное числительное → число. Классы символов с кириллицей в выражениях запрещены
# (GNU grep в C.UTF-8 отвергает `[а-я]`, docs/development.md), поэтому слово берётся как
# «непробельный хвост» и разбирается здесь точным сравнением.
word2num() { case "$1" in два|две|вторая) echo 2 ;; три|третья) echo 3 ;; четыре|четвёртая) echo 4 ;; пять|пятая) echo 5 ;; шесть|шестая) echo 6 ;; *) printf '%s' "$1" | sed -E 's/-.*$//' ;; esac; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export ABLATION_DIR="$TMP/abl"
mkdir -p "$ABLATION_DIR"

# --------------------------------------------- §12: глубина извлечения плеча Core
# Повод (D293). `scripts/ablation/core/inject.py` берёт глубину из переменной окружения
# `CORE_INJECT_K` с умолчанием 5 и применяет её к ранжированному списку. Это параметр САМОГО
# лечения в измеряемом плече: значит плечо Core определялось не протоколом, а окружением
# того, кто запустил прогон, и §11 о заморозке параметров этого не покрывала — числа k в
# документе не было ни разу.
K_DOC=$(claim 'глубина извлечения плеча Core: k = ([0-9]+)')
need "k плеча Core" "$K_DOC" 'глубина извлечения плеча Core: k = N'
if [ -n "$K_DOC" ]; then
    K_CODE=$(grep -oE 'CORE_INJECT_K", *"([0-9]+)"' "$ROOT/scripts/ablation/core/inject.py" \
             | grep -oE '[0-9]+' | head -1)
    if [ "$K_DOC" = "$K_CODE" ]; then ok
    else bad "k плеча Core" "протокол говорит k=$K_DOC, код — k=$K_CODE"; fi
fi

# ---------------------------------------------------------------- §11: δ и CI
DELTA_DOC=$(claim '^δ  = ([0-9.]+) '); need "δ" "$DELTA_DOC" '^δ  = N'
CI_DOC=$(claim '^CI = ([0-9]+)%'); need "CI" "$CI_DOC" '^CI = N%'
if [ -n "$DELTA_DOC" ] && [ -n "$CI_DOC" ]; then
    # n=100 троек: b «Full+/Vanilla−» ровно δ·100 → Δ̂ = δ, нижняя граница CI > 0 → «польза»;
    # b−1 → Δ̂ < δ при той же положительной нижней границе → «неразрешающий». Так решает
    # именно δ, а не CI.
    B_AT=$(python3 -c "print(round(float('$DELTA_DOC') * 100))")
    mk_pairs() {  # mk_pairs <файл> <b> [surface_n]
        python3 - "$1" "$2" "${3:-0}" <<'EOF'
import json, sys
path, b, surf = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(path, "w") as f:
    for i in range(100):
        full, van = (1, 0) if i < b else (1, 1)
        f.write(json.dumps({"task_id": f"t-{i}", "full": full, "core": 1, "vanilla": van,
                            "stratum_surface": i < surf}) + "\n")
EOF
    }
    mk_pairs "$TMP/at.jsonl" "$B_AT"; OUT_AT=$(python3 "$AB/pair-analyze.py" "$TMP/at.jsonl")
    mk_pairs "$TMP/below.jsonl" $((B_AT - 1)); OUT_BELOW=$(python3 "$AB/pair-analyze.py" "$TMP/below.jsonl")
    DELTA_CODE=$(printf '%s' "$OUT_AT" | jq -r '.delta')
    python3 -c "import sys; sys.exit(0 if float('$DELTA_CODE') == float('$DELTA_DOC') else 1)" \
        && ok || bad "P1" "δ в документе $DELTA_DOC, в отчёте анализа $DELTA_CODE"
    assert_contains "$(printf '%s' "$OUT_AT" | jq -c '.primary_all.outcome')" '"польза"' "P1b: Δ̂ = δ при нижней границе > 0 — польза"
    assert_contains "$(printf '%s' "$OUT_BELOW" | jq -c '.primary_all.outcome')" '"неразрешающий"' "P1c: Δ̂ на 0.01 ниже δ — неразрешающий"
    # CI: уровень из документа, метод — Agresti–Min (+0.5 к клетке), пересчёт независимый.
    EXP_CI=$(python3 - "$B_AT" "$CI_DOC" <<'EOF'
import math, sys
from statistics import NormalDist
b, level = int(sys.argv[1]), int(sys.argv[2]); c, n = 0, 100
z = NormalDist().inv_cdf(1 - (1 - level / 100) / 2)
bp, cp, np_ = b + 0.5, c + 0.5, n + 2
d = (bp - cp) / np_; se = math.sqrt((bp + cp) - (bp - cp) ** 2 / np_) / np_
print(f"[{round(d - z * se, 4)}, {round(d + z * se, 4)}]")
EOF
    )
    GOT_CI=$(printf '%s' "$OUT_AT" | jq -c '.primary_all.ci95' | tr -d ' ')
    [ "$GOT_CI" = "$(printf '%s' "$EXP_CI" | tr -d ' ')" ] && ok \
        || bad "P2" "CI ${CI_DOC}% Agresti–Min по документу $EXP_CI, в отчёте $GOT_CI"
fi

# ---------------------------------------------------------------- §5: сэмплер
MOD_DOC=$(claim 'r mod ([0-9]+) == 0'); need "mod" "$MOD_DOC" 'r mod N == 0'
P_DOC=$(claim '# p = ([0-9.]+);'); need "p" "$P_DOC" '# p = N;'
COMMIT_DOC=$(claim '^SHA256\(salt\) = ([0-9a-f]{64})$'); need "commitment" "$COMMIT_DOC" 'SHA256(salt) = hex'
if [ -n "$MOD_DOC" ] && [ -n "$P_DOC" ]; then
    python3 -c "import sys; sys.exit(0 if abs(1/int('$MOD_DOC') - float('$P_DOC')) < 1e-9 else 1)" \
        && ok || bad "P3" "в документе r mod $MOD_DOC и p = $P_DOC — не одно и то же число"
    printf 'testsalt\n' > "$TMP/salt.txt"
    OV=$(python3 -c "print('ab'*32)")
    printf '{"pulse":{"outputValue":"%s","timeStamp":"2026-08-08T16:00:00.000Z","statusCode":0}}' "$OV" > "$TMP/pulse.json"
    FIX_COMMIT=$(python3 -c "import hashlib;print(hashlib.sha256(b'testsalt').hexdigest())")
    MISMATCH=0
    for i in 1 2 3 4 5 6; do
        ID=$(bash "$AB/journal.sh" register "задача $i")
        bash "$AB/journal.sh" classify "$ID" eligible "тест" bugfix low
        GOT=$(ABLATION_SALT="$TMP/salt.txt" ABLATION_COMMITMENT="$FIX_COMMIT" \
              python3 "$AB/sampler.py" decide --task-id "$ID" --snapshot-ts "2026-08-08T15:00:00Z" --beacon-file "$TMP/pulse.json" | jq -r '.selected')
        EXP=$(python3 - "$ID" "$OV" "$MOD_DOC" <<'EOF'
import hmac, hashlib, sys
tid, ov, mod = sys.argv[1], sys.argv[2], int(sys.argv[3])
r = hmac.new(b"testsalt", b"claudsoul-ablation-v1\x00" + tid.encode() + b"\x00" + bytes.fromhex(ov), hashlib.sha256).digest()
print("true" if int.from_bytes(r, "big") % mod == 0 else "false")
EOF
        )
        [ "$GOT" = "$EXP" ] || MISMATCH=$((MISMATCH + 1))
    done
    [ "$MISMATCH" -eq 0 ] && ok || bad "P3b" "решение сэмплера разошлось с формулой документа (r mod $MOD_DOC) в $MISMATCH случаях из 6"
fi
if [ -n "$COMMIT_DOC" ]; then
    # Соль с чужим sha256 и БЕЗ подмены commitment: сэмплер обязан отказать и назвать
    # ожидаемый commitment — тот же, что напечатан в протоколе.
    ID=$(bash "$AB/journal.sh" register "задача commitment")
    bash "$AB/journal.sh" classify "$ID" eligible "тест" bugfix low
    ERR=$(env -u ABLATION_COMMITMENT ABLATION_SALT="$TMP/salt.txt" \
          python3 "$AB/sampler.py" decide --task-id "$ID" --snapshot-ts "2026-08-08T15:00:00Z" --beacon-file "$TMP/pulse.json" 2>&1); RC=$?
    [ "$RC" -ne 0 ] && ok || bad "P4" "соль с чужим sha256 прошла commitment"
    assert_contains "$ERR" "!= $COMMIT_DOC" "P4b: сэмплер ждёт commitment из протокола"
fi

# ---------------------------------------------------------------- шапка: ссылка на строку кода
LINE_DOC=$(claim 'sampler\.py:([0-9]+)'); need "sampler-line" "$LINE_DOC" 'sampler.py:N'
# Труба заменена на herestring: `producer | grep -q` под pipefail отдаёт 141, когда grep
# выходит по первому совпадению, и утверждение читает найденное как ненайденное
# (test_assert_no_sigpipe.sh, D59). Строка кода берётся в переменную заранее.
[ -n "$LINE_DOC" ] && { SRC_LINE=$(sed -n "${LINE_DOC}p" "$AB/sampler.py"); grep -q '"e": "queue"' <<< "$SRC_LINE" && ok \
    || bad "P5" "sampler.py:$LINE_DOC не пишет событие queue: $SRC_LINE"; }

# ---------------------------------------------------------------- §9: повторы тройки
RETRY_DOC=$(word2num "$(claim 'Максимум ([^ ]+) повтора')"); need "retries" "$RETRY_DOC" 'Максимум N повтора'
if [ -n "$RETRY_DOC" ]; then
    ID=$(bash "$AB/journal.sh" register "задача повторов")
    i=0; while [ "$i" -lt "$RETRY_DOC" ]; do bash "$AB/pair.sh" annul "$ID" сбой >/dev/null; i=$((i + 1)); done
    grep -q '"e":"pair_excluded"' "$ABLATION_DIR/journal.jsonl" && bad "P6" "тройка исключена уже после $RETRY_DOC повторов" || ok
    bash "$AB/pair.sh" annul "$ID" сбой >/dev/null
    grep -q '"e":"pair_excluded"' "$ABLATION_DIR/journal.jsonl" && ok || bad "P6b" "тройка не исключена после $((RETRY_DOC + 1))-го повтора"
fi

# ---------------------------------------------------------------- §13: часы enrollment
ENROLL_N=$(claim 'принято ([0-9]+) задач либо \(б\) прошло [0-9]+ недель'); need "enroll-n" "$ENROLL_N" 'принято N задач либо (б) прошло W недель'
ENROLL_W=$(claim 'принято [0-9]+ задач либо \(б\) прошло ([0-9]+) недель'); need "enroll-w" "$ENROLL_W" 'прошло W недель'
EXT_W7=$(claim 'до квоты, но не дольше \+([0-9]+) недель'); need "ext-§7" "$EXT_W7" '§7: не дольше +N недель'
EXT_W13=$(claim 'только для Δ_surface, не дольше \+([0-9]+) недель'); need "ext-§13" "$EXT_W13" '§13: не дольше +N недель'
[ -n "$EXT_W7" ] && [ -n "$EXT_W13" ] && { [ "$EXT_W7" = "$EXT_W13" ] && ok || bad "P7" "срок добора страты в §7 (+$EXT_W7) и §13 (+$EXT_W13) разошёлся"; }
if [ -n "$ENROLL_N" ] && [ -n "$ENROLL_W" ]; then
    status_with() {  # status_with <число queue> <ts первой>
        local d="$TMP/ph-$1-$RANDOM"; mkdir -p "$d"
        printf '{"phase":"p","tag":"t","since":"2026-01-01T00:00:00Z"}' > "$d/active-phase.json"
        local i=1; while [ "$i" -le "$1" ]; do
            printf '{"e":"queue","id":"t-%s","ts":"%s"}\n' "$i" "$2" >> "$d/journal.jsonl"; i=$((i + 1)); done
        ABLATION_DIR="$d" bash "$AB/phase.sh" status | tail -n +2
    }
    NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    assert_contains "$(status_with "$ENROLL_N" "$NOW")" '"stop_condition_met": true'  "P8: $ENROLL_N в очереди — остановка"
    assert_contains "$(status_with $((ENROLL_N - 1)) "$NOW")" '"stop_condition_met": false' "P8b: $((ENROLL_N - 1)) в очереди — идёт"
    AGO_OVER=$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(weeks=$ENROLL_W, days=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    AGO_UNDER=$(python3 -c "import datetime as d; print((d.datetime.now(d.timezone.utc)-d.timedelta(weeks=$ENROLL_W)+d.timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    assert_contains "$(status_with 1 "$AGO_OVER")" '"stop_condition_met": true'  "P8c: $ENROLL_W недель + день с первой принятой — остановка"
    assert_contains "$(status_with 1 "$AGO_UNDER")" '"stop_condition_met": false' "P8d: $ENROLL_W недель − день — идёт"
    if [ -n "$EXT_W7" ]; then
        # Добор страты: срок = закрытие enrollment + N недель (§7/§13)
        T20="2026-03-01T00:00:00Z"
        EXP_EXT=$(python3 -c "import datetime as d; print((d.datetime(2026,3,1)+d.timedelta(weeks=$EXT_W7)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
        assert_contains "$(status_with "$ENROLL_N" "$T20")" "\"surface_extension_until\": \"$EXP_EXT\"" "P9: добор страты не дольше +$EXT_W7 недель после $ENROLL_N-й принятой"
    fi
    # P9b/P9c: «что раньше» — МИНИМУМ двух сроков (D299, 12 сентября 2026). Первая задача
    # 1 января, 20-я — 1 апреля: закрытие обязано быть по календарю (t0 + ENROLL_W недель),
    # а не по 20-й. Прежняя редакция брала 20-ю безусловно, и окно добора уезжало на 95 дней.
    status_min() {  # status_min <ts первой> <ts остальных>
        local d="$TMP/ph-min-$RANDOM"; mkdir -p "$d"
        printf '{"phase":"p","tag":"t","since":"2026-01-01T00:00:00Z"}' > "$d/active-phase.json"
        printf '{"e":"queue","id":"t-1","ts":"%s"}\n' "$1" >> "$d/journal.jsonl"
        local i=2; while [ "$i" -le "$ENROLL_N" ]; do
            printf '{"e":"queue","id":"t-%s","ts":"%s"}\n' "$i" "$2" >> "$d/journal.jsonl"; i=$((i + 1)); done
        ABLATION_DIR="$d" bash "$AB/phase.sh" status | tail -n +2
    }
    EXP_CAL=$(python3 -c "import datetime as d; print((d.datetime(2026,1,1)+d.timedelta(weeks=$ENROLL_W)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    assert_contains "$(status_min 2026-01-01T00:00:00Z 2026-04-01T00:00:00Z)" "\"enrollment_closes_at\": \"$EXP_CAL\"" "P9b: 20-я позже календаря — закрытие по календарю ($EXP_CAL)"
    # КОНТРПРИМЕР: 20-я задача РАНЬШЕ календаря — закрытие по ней, календарь не тянет вперёд.
    assert_contains "$(status_min 2026-01-01T00:00:00Z 2026-01-10T00:00:00Z)" '"enrollment_closes_at": "2026-01-10T00:00:00Z"' "P9c: 20-я раньше календаря — закрытие по 20-й"

    # P13: принадлежность набору — в САМИХ ДАННЫХ пары (D299; §13, §7). Журнал: 20 задач
    # приняты 10 января (закрытие по 20-й), задача late — 20 января; у обеих три плеча.
    d="$TMP/pair-enr"; mkdir -p "$d"
    { i=1; while [ "$i" -le "$ENROLL_N" ]; do printf '{"e":"queue","id":"t-%s","ts":"2026-01-10T00:00:00Z"}\n' "$i"; i=$((i + 1)); done
      printf '{"e":"queue","id":"late","ts":"2026-01-20T00:00:00Z"}\n'
      for id in t-1 late; do for a in full core vanilla; do printf '{"e":"arm_result","id":"%s","arm":"%s","outcome":"success"}\n' "$id" "$a"; done; done
    } > "$d/journal.jsonl"
    ABLATION_DIR="$d" bash "$AB/pair.sh" complete t-1 >/dev/null 2>&1
    ABLATION_DIR="$d" bash "$AB/pair.sh" complete late >/dev/null 2>&1
    assert_contains "$(jq -r 'select(.task_id=="t-1") | .enrolled' "$d/pairs.jsonl" 2>/dev/null)" 'primary'   "P13: задача до закрытия — primary"
    assert_contains "$(jq -r 'select(.task_id=="late") | .enrolled' "$d/pairs.jsonl" 2>/dev/null)" 'extension' "P13b: задача после закрытия — extension (добор)"
    # P13c: анализ primary считает только набор — добранная тройка названа, но не входит.
    assert_contains "$(python3 "$AB/pair-analyze.py" "$d/pairs.jsonl" 2>/dev/null | jq -c '.primary_all.enrollment' 2>/dev/null)" '"primary":1,"extension":1' "P13c: primary — 1 в наборе, 1 добрана и не в счёте"
fi

# ---------------------------------------------------------------- §7: квота страты
QUOTA_DOC=$(claim 'минимум \*\*([0-9]+) завершённых пар\*\*'); need "quota" "$QUOTA_DOC" 'минимум **N завершённых пар**'
if [ -n "$QUOTA_DOC" ] && [ -n "${B_AT:-}" ]; then
    mk_pairs "$TMP/q-at.jsonl" "$B_AT" "$QUOTA_DOC";       OUT_Q=$(python3 "$AB/pair-analyze.py" "$TMP/q-at.jsonl")
    mk_pairs "$TMP/q-below.jsonl" "$B_AT" $((QUOTA_DOC - 1)); OUT_QB=$(python3 "$AB/pair-analyze.py" "$TMP/q-below.jsonl")
    assert_contains "$(printf '%s' "$OUT_Q" | jq -c '.key_secondary_surface.quota')" "\"required\":$QUOTA_DOC" "P10: квота страты названа числом протокола"
    assert_contains "$(printf '%s' "$OUT_Q" | jq -c '.key_secondary_surface.quota.met')" 'true' "P10b: $QUOTA_DOC пар — квота добрана"
    assert_contains "$(printf '%s' "$OUT_QB" | jq -c '.key_secondary_surface.quota.met')" 'false' "P10c: $((QUOTA_DOC - 1)) пар — не добрана"
    assert_contains "$(printf '%s' "$OUT_QB" | jq -r '.key_secondary_surface.reading')" 'неразрешающий' "P10d: недобор — результат по центральной заявке неразрешающий (§7)"
    # P10e: НОЛЬ наблюдений — не «недобор», а «нет данных». Прожарка 3 сентября 2026: при
    # пустом pairs.jsonl (нынешнее состояние замера) отчёт объявлял центральную заявку
    # неразрешающей, то есть выносил чтение там, где нет ни одной тройки. Ветка та же, что
    # у analyze() на n == 0, и по той же причине: вердикт без наблюдений — не вердикт.
    : > "$TMP/q-zero.jsonl"
    OUT_QZ=$(python3 "$AB/pair-analyze.py" "$TMP/q-zero.jsonl")
    assert_contains "$(printf '%s' "$OUT_QZ" | jq -r '.key_secondary_surface.reading')" 'нет данных' "P10e: ноль троек — чтение «нет данных», а не «недобор»"
fi

# ---------------------------------------------------------------- §10: репликации
EVERY_DOC=$(word2num "$(claim 'Каждая \*\*([^ *]+) задача по порядку включения в очередь')"); need "every" "$EVERY_DOC" 'Каждая **N-я задача по порядку включения в очередь'
if [ -n "$EVERY_DOC" ]; then
    d="$TMP/rep"; mkdir -p "$d"
    i=1; while [ "$i" -lt "$EVERY_DOC" ]; do printf '{"e":"queue","id":"t-%s","ts":"2026-01-0%sT00:00:00Z"}\n' "$i" "$i" >> "$d/journal.jsonl"; i=$((i + 1)); done
    assert_empty "$(ABLATION_DIR="$d" bash "$AB/journal.sh" replication-due)" "P11: $((EVERY_DOC - 1)) в очереди — повтор никому не положен"
    printf '{"e":"queue","id":"t-%s","ts":"2026-01-09T00:00:00Z"}\n' "$EVERY_DOC" >> "$d/journal.jsonl"
    assert_contains "$(ABLATION_DIR="$d" bash "$AB/journal.sh" replication-due)" "\"id\":\"t-$EVERY_DOC\"" "P11b: $EVERY_DOC-я по порядку очереди — повтор положен ей"
    # порядок ОЧЕРЕДИ, не завершения: pair_done у другой задачи графика не сдвигает
    printf '{"e":"pair_done","id":"t-1","ts":"2026-01-10T00:00:00Z"}\n' >> "$d/journal.jsonl"
    [ "$(ABLATION_DIR="$d" bash "$AB/journal.sh" replication-due | wc -l | tr -d ' ')" = "1" ] && ok || bad "P11c" "завершение сдвинуло график репликаций"
fi

# ---------------------------------------------------------------- §11: описательные контрасты без вердикта
# Правило, не число: Δ_memory «описательный, без правила решения». До 2 сентября 2026 код
# печатал ему «польза»/«вред» (CHANGELOG). Пока фраза стоит в протоколе — поля outcome у
# secondary_memory быть не должно; исчезнет фраза (amendment) — проверка снимется сама и
# назовёт это, а не промолчит.
if grep -q "описательный, без правила решения" "$DOC"; then
    [ -n "${OUT_AT:-}" ] && { [ "$(printf '%s' "$OUT_AT" | jq -r '.secondary_memory | has("outcome")')" = "false" ] && ok \
        || bad "P12" "Δ_memory описательный по §11, а отчёт печатает ему outcome"; }
else
    bad "P12" "фраза «описательный, без правила решения» исчезла из протокола — правило Δ_memory перечитать"
fi

echo "test_ablation_protocol_claims: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
