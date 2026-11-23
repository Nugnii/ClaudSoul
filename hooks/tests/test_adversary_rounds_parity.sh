#!/usr/bin/env bash
# СУДИТ: skills/adversary/references/adversary-rounds.js
# test_adversary_rounds_parity.sh — цикл агентов /adversary (D485) не может пропустить шаги 3–6
# и говорит тем же промптом критика, что и скилл.
#
# Часть 1 — сверка копий: промпт критика и приёмы атаки в скрипте — копии блоков
# skills/adversary/SKILL.md (критик не читает ничего, кроме предмета, поэтому текст вшит). Две
# копии без сверки расходятся молча — у текста стало бы два владельца.
# Часть 2 — поведение: тело скрипта исполняется node на заглушке agent(), и проверяется, ЧЕМ
# кончается прогон: стоп по классу, а не по атакам; отказ критика — не «атак нет»; без нового
# класса правки нет. Нет node — часть 2 пропускается с названной причиной.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$REPO/skills/adversary/SKILL.md"
SCR="$REPO/skills/adversary/references/adversary-rounds.js"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
[ -f "$SKILL" ] && [ -f "$SCR" ] || { echo "FAIL: нет $SKILL или $SCR"; exit 1; }

# --- Часть 1: копии совпадают с источником ---
PARITY=$(python3 - "$SKILL" "$SCR" <<'PY'
import json, sys
s = open(sys.argv[1]).read().split("\n")
js = open(sys.argv[2]).read().split("\n")
i = next(k for k, l in enumerate(s) if l.startswith("## Step 1."))
a = next(k for k in range(i, len(s)) if s[k] == "```")
b = next(k for k in range(a + 1, len(s)) if s[k] == "```")
j = next(k for k, l in enumerate(s) if l.startswith("## Step 2."))
e = next(k for k in range(j + 1, len(s)) if s[k].startswith("## Step 3."))
want = {"CRITIC": s[a + 1:b], "TECHNIQUES": [l for l in s[j + 1:e] if l.startswith("- **")]}
for name, lines in want.items():
    o = js.index(f"const {name} = [")
    c = js.index("].join('\\n')", o)
    got = [json.loads(l.strip().rstrip(",")) for l in js[o + 1:c]]
    print(name, "OK" if got == lines else f"РАЗОШЛИСЬ (скилл {len(lines)} строк, скрипт {len(got)})")
PY
)
for n in CRITIC TECHNIQUES; do
    grep -q "^$n OK$" <<< "$PARITY" && ok || bad "копия $n разошлась со скиллом: $(grep "^$n" <<< "$PARITY")"
done

# --- Часть 2: исполнение на заглушке agent() ---
if ! command -v node >/dev/null 2>&1; then
    echo "SKIP часть 2: нет node — поведение цикла не проверено"
else
    # run <сценарий JSON: ответы агентов по меткам> → JSON итога и журнала вызовов
    run() {
        local W A="${2:-}"; W=$(mktemp -d)
        [ -n "$A" ] || A='{"subject":"S","testPath":"t-<раунд>.sh","runCmd":"bash t"}'
        { printf 'const SCEN = %s;\nconst CALLS = [];\n' "$1"
          printf 'const args = %s;\n' "$A"
          printf 'const log = () => {};\n'
          printf 'async function agent(p, o) { CALLS.push({label: o.label, model: o.model, agentType: o.agentType, prompt: p}); const v = SCEN[o.label]; return v === undefined ? null : v; }\n'
          printf '(async function(){\n'
          sed '1s/^export const meta/const meta/' "$SCR"
          printf '\n})().then(r => console.log(JSON.stringify({r, calls: CALLS.map(c => c.label), prompts: CALLS})), e => console.log(JSON.stringify({error: String(e)})));\n'
        } > "$W/run.js"
        node "$W/run.js" 2>&1
    }
    C1='{"attacks":"A","reproduced":2}'
    NEW='{"classes":"K","newClasses":1,"closedClassEntries":0,"fixPlan":"P"}'
    OLD='{"classes":"K","newClasses":0,"closedClassEntries":1,"fixPlan":"P"}'
    NONE='{"classes":"K","newClasses":0,"closedClassEntries":0,"fixPlan":""}'
    FIX='{"summary":"F","closedClasses":"К1"}'

    # 1) раунд 1 — новый класс, раунд 2 — только вход закрытого: правка корня, затем стоп
    OUT=$(run "{\"critic-r1\":$C1,\"classes-r1\":$NEW,\"rootfix-r1\":$FIX,\"critic-r2\":$C1,\"classes-r2\":$OLD,\"rootfix-r2\":$FIX}")
    L=$(jq -r '.calls | join(",")' <<< "$OUT" 2>/dev/null)
    [ "$L" = "critic-r1,classes-r1,rootfix-r1,critic-r2,classes-r2,rootfix-r2" ] && ok || bad "1: порядок шагов $L"
    grep -q 'нового класса нет' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok || bad "1: стоп не по классу: $(jq -r '.r.stop // .error' <<< "$OUT")"
    # закрытые классы раунда 1 названы критику раунда 2
    jq -e '.prompts[3].prompt | contains("К1")' <<< "$OUT" >/dev/null && ok || bad "1: критику раунда 2 не названы закрытые классы"
    # промпт критика заполнен, заготовок не осталось, приёмы атаки на месте
    jq -e '.prompts[0].prompt | (contains("<ПРЕДМЕТ>") or contains("<ПУТЬ ДЛЯ ТЕСТОВ>") or contains("<КОМАНДА ЗАПУСКА>") or contains("<раунд>")) | not' <<< "$OUT" >/dev/null && ok || bad "1: в промпте критика остались заготовки"
    jq -e '.prompts[0].prompt | contains("t-1.sh") and contains("Конкурентность")' <<< "$OUT" >/dev/null && ok || bad "1: путь раунда или приёмы атаки не подставлены"
    # роли (rules/CLAUDE.md, § «Модели агентов»): критик — финальный скептик, opus; разбор и правка — sonnet
    [ "$(jq -r '[.prompts[] | .model] | join(",")' <<< "$OUT")" = "opus,sonnet,sonnet,opus,sonnet,sonnet" ] && ok || bad "1: модели по ролям"
    # каждый агент — лёгкий тип: без CLAUDE.md, скиллов и MCP на старте
    [ "$(jq -r '[.prompts[] | .agentType] | unique | join(",")' <<< "$OUT")" = "lean" ] && ok || bad "1: тип агента не lean у всех вызовов"

    # 2) атак нет с покрытием — стоп после критика, ни разбора, ни правки; покрытие в строке стопа
    OUT=$(run '{"critic-r1":{"attacks":"","reproduced":0,"coverage":"COV1"}}')
    [ "$(jq -r '.calls | join(",")' <<< "$OUT")" = "critic-r1" ] && grep -q 'атак нет; покрытие: COV1' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok \
        || bad "2: «атак нет» не остановило прогон или потеряло покрытие: $(jq -r '.r.stop // .error' <<< "$OUT")"
    # 2b) «атак нет» без покрытия — названо «не смотрел», а не «чисто» (различающая нога к 2)
    OUT=$(run '{"critic-r1":{"attacks":"","reproduced":0}}')
    [ "$(jq -r '.calls | join(",")' <<< "$OUT")" = "critic-r1" ] && grep -q 'не смотрел' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok \
        || bad "2b: «атак нет» без покрытия принято за «чисто»: $(jq -r '.r.stop // .error' <<< "$OUT")"

    # 3) критик не вернул результат — это отказ инструмента, а не «атак нет»
    OUT=$(run '{}')
    grep -q 'отказ инструмента' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok || bad "3: отказ критика выдан за пустую находку: $(jq -r '.r.stop // .error' <<< "$OUT")"

    # 4) ни нового класса, ни входа в закрытый — правки нет
    OUT=$(run "{\"critic-r1\":$C1,\"classes-r1\":$NONE}")
    [ "$(jq -r '.calls | join(",")' <<< "$OUT")" = "critic-r1,classes-r1" ] && ok || bad "4: правка без нового класса"

    # 5) новый класс в каждом раунде — стоп по лимиту, раундов ровно args.rounds
    OUT=$(run "{\"critic-r1\":$C1,\"classes-r1\":$NEW,\"rootfix-r1\":$FIX,\"critic-r2\":$C1,\"classes-r2\":$NEW,\"rootfix-r2\":$FIX}" '{"subject":"S","testPath":"t","runCmd":"r","rounds":2}')
    grep -q 'лимит 2' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok || bad "5: лимит раундов: $(jq -r '.r.stop // .error' <<< "$OUT")"

    # 7) раунд 3 снова принёс тот же корень — стоп без разбора и правки, вопрос владельцу;
    #    тот же раунд 3 без метки «тот же корень» идёт обычным путём (различающая нога)
    S3='{"attacks":"A","reproduced":1,"sameRoot":1}'
    BASE="\"critic-r1\":$C1,\"classes-r1\":$NEW,\"rootfix-r1\":$FIX,\"critic-r2\":$C1,\"classes-r2\":$NEW,\"rootfix-r2\":$FIX"
    OUT=$(run "{$BASE,\"critic-r3\":$S3,\"classes-r3\":$NEW,\"rootfix-r3\":$FIX}")
    [ "$(jq -r '.calls | last' <<< "$OUT")" = "critic-r3" ] && grep -q 'вопрос владельцу' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok \
        || bad "7: тот же корень на раунде 3 не остановил прогон: $(jq -r '.r.stop // .error' <<< "$OUT")"
    OUT=$(run "{$BASE,\"critic-r3\":$C1,\"classes-r3\":$NEW,\"rootfix-r3\":$FIX}")
    [ "$(jq -r '.calls | last' <<< "$OUT")" = "rootfix-r3" ] && ok || bad "7b: раунд 3 без метки «тот же корень» остановлен"
    jq -e '.prompts[0].prompt | contains("[тот же корень R<N>]")' <<< "$OUT" >/dev/null && ok || bad "7c: метка корня не названа критику"

    # 8) атака вида rule_choice — ожидание задано правилом, которого данные не определяют (D523):
    #    в разбор и правку не идёт, следующего раунда нет. Различающая нога — сценарий 1: тот же
    #    критик без ruleChoice проходит в раунд 2.
    RC1='{"attacks":"A","reproduced":1,"sameRoot":0,"ruleChoice":1}'
    RC2='{"attacks":"A","reproduced":2,"sameRoot":0,"ruleChoice":1}'
    OUT=$(run "{\"critic-r1\":$RC1,\"classes-r1\":$NEW,\"rootfix-r1\":$FIX}")
    [ "$(jq -r '.calls | join(",")' <<< "$OUT")" = "critic-r1" ] && grep -q 'rule_choice.*вопрос владельцу' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok \
        || bad "8: раунд только из rule_choice ушёл в разбор: $(jq -r '(.calls | join(",")) + " / " + (.r.stop // .error)' <<< "$OUT")"
    OUT=$(run "{\"critic-r1\":$RC2,\"classes-r1\":$NEW,\"rootfix-r1\":$FIX,\"critic-r2\":$C1,\"classes-r2\":$NEW,\"rootfix-r2\":$FIX}")
    [ "$(jq -r '.calls | join(",")' <<< "$OUT")" = "critic-r1,classes-r1,rootfix-r1" ] && grep -q 'rule_choice' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok \
        || bad "8b: смешанный раунд — дефекты не починены или пошёл раунд 2: $(jq -r '(.calls | join(",")) + " / " + (.r.stop // .error)' <<< "$OUT")"
    jq -e '.prompts[1].prompt | contains("rule_choice")' <<< "$OUT" >/dev/null && ok || bad "8c: разборщику не сказано, что rule_choice в классы не входит"
    jq -e '.prompts[0].prompt | contains("Вид: rule_choice")' <<< "$OUT" >/dev/null && ok || bad "8d: вид rule_choice не назван критику"
    OUT=$(run "{\"critic-r1\":$RC2,\"classes-r1\":$NONE}")
    grep -q 'rule_choice' <<< "$(jq -r '.r.stop' <<< "$OUT")" && ok \
        || bad "8e: смешанный раунд без классов потерял вопрос о правиле: $(jq -r '.r.stop // .error' <<< "$OUT")"

    # 6) без обязательных аргументов — отказ, а не прогон вслепую
    OUT=$(run '{}' '{"subject":"S"}')
    grep -q 'нужны args' <<< "$(jq -r '.error // ""' <<< "$OUT")" && ok || bad "6: прогон без testPath/runCmd не отвергнут"
fi

echo "adversary rounds: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
