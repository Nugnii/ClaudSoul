#!/usr/bin/env bash
set -u
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1214 — причины отказа стража разбора — только открытые поводы с правом на отказ. Стоячий вид (`FWG_STANDING`)
#   отказа не держит и исхода не требует; в скобках «пока у повода нет названного исхода (…)» он звал писать исход поводу,
#   который отказа не держал (1 ноября 2026: четыре вызова на `outcome.sh … event`, ни один не снял отказ). Тот же вред у
#   вида с правом, чей исход уже принят (`chain-ok|`, скептик opus по 3106709e, M1: 58 из 64 отказов).
#   Случаи: на КАЖДЫЙ стоячий вид стража (перечень — `FWG_STANDING` стража; новый вид без фразы в пробе даёт 2) — полоса
#   упавших команд плюс этот вид: отказ есть (страж, упавший на стоячем виде, — дефект, а не рамка), строка причин называет
#   полосу и не называет вид, вид назван строкой со словами «отказа не держ…» и «исхода не требуют», предмет повода в
#   журнале исходов (`ref`) у `question` несёт и вид — общий перечень `WHAT` прежний. Два вида с правом и событие — в скобках оба вида,
#   поправка не в строке стоячих. Полоса, покрытая зачтённой цепочкой, и открытая поправка — в скобках только поправка.
#   0 — причины чисты; 1 — дефект; 2 — нет стража/jq, контроль (одна полоса) без отказа, вид журналом не принят.
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
H="$PWD/hooks/five-whys-gate.sh"
[ -f "$H" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
ST=$(sed -n 's/^FWG_STANDING="\${FWG_STANDING:-\([^}]*\)}".*$/\1/p' "$H")
# Умолчание стража указывает на владельца перечня (D1256: `RC_STANDING_KINDS` в root-cause-lib) — читаем у него.
case "$ST" in '$RC_STANDING_KINDS') ST=$(bash -c '. "$1" >/dev/null 2>&1 && printf "%s" "${RC_STANDING_KINDS:-}"' _ \
    "$(dirname "$H")/root-cause-lib.sh") ;; esac
[ -n "$ST" ] || { echo "рамка: перечень стоячих у стража не прочитан"; exit 2; }
STREAK="полоса упавших команд"; CORR="поправка собеседника о поведении"
phrase() {  # phrase <вид> — как вид звучит в тексте отказа
    case "$1" in
        event)       echo "внешнее событие" ;;
        question)    echo "вопрос собеседника" ;;
        breakage)    echo "жалоба собеседника на поломку" ;;
        self_repeat) echo "маркер повтора в собственной речи" ;;
        *) return 1 ;;
    esac; }
mk() {  # mk <случай> <вид>… — состояние, дающее эти виды; печатает текст отказа (пусто — отказа нет)
    local c=$1 d="$W/$1" txt="Правлю строку." k; shift
    mkdir -p "$d" || exit 2
    for k; do
        case "$k" in
            streak)      printf '2' > "$d/error_streak_fired_$c" ;;
            correction)  printf '%s\n' '{"q":"не так"}' > "$d/correction-fired-$c.jsonl" ;;
            self_repeat) txt="Это третий раз за день, когда тест падает на той же строке. Правлю." ;;
            question)    printf '%s\n' '{"q":"почему падает?"}' > "$d/question-open-$c.jsonl" ;;
            breakage)    printf '%s\n' '{"date":"2026-11-01T00:00:00Z","snippet":"всё сломалось","hash":"1214"}' > "$d/breakage-fired-$c.jsonl" ;;
            event)       printf '%s\n' '{"ts":"2026-11-01T00:00:00Z","kind":"hotfix-repeat","detail":"scripts/x.sh чинился 2+ раз","project":"","status":"open"}' > "$d/pending-events.jsonl" ;;
            chain:*)     printf 'chain-ok|%s|\n' "${k#chain:}" >> "$d/five-whys-$c.seen" ;;
            # Имя повода полосы — у владельца (`rc_streak_token`, D1293), по флагу, уже записанному выше.
            chain-streak) printf 'chain-ok|streak:%s|\n' "$(bash -c '. "$1" >/dev/null 2>&1; rc_streak_token "$2"' _ \
                              "$(dirname "$H")/root-cause-lib.sh" "$d/error_streak_fired_$c")" >> "$d/five-whys-$c.seen" ;;
        esac
    done
    printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}' > "$d/t.jsonl"
    jq -cn --arg t "$txt" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$d/t.jsonl"
    jq -cn --arg s "$c" --arg p "$d/t.jsonl" --arg w "$PWD" \
        '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Write", cwd:$w, tool_input:{file_path:"hooks/x.sh", content:"x"}}' \
        | env -u FWG_STANDING STATE_DIR="$d" bash "$H" 2>/dev/null > "$d/out"
    [ -s "$d/out" ] && jq -r 'select(.hookSpecificOutput.permissionDecision == "deny") | .hookSpecificOutput.permissionDecisionReason' "$d/out" 2>/dev/null; }
reasons() { grep -F 'названного исхода (' <<< "$1"; }
[ -n "$(mk ctl streak)" ] || { echo "рамка: одна полоса — отказа нет"; exit 2; }
for k in $ST; do
    p=$(phrase "$k") || { echo "рамка: у стоячего вида «${k}» нет фразы в пробе"; exit 2; }
    m=$(mk "$k" streak "$k")
    [ -n "$m" ] || { echo "$k: полоса и стоячий вид — отказа нет, а одна полоса его даёт (страж упал на виде)"; exit 1; }
    grep '^turn:' "$W/$k/five-whys-$k.seen" 2>/dev/null | tail -1 | grep -qF -- "|$k:" || { echo "рамка: вид $k журналом не принят"; exit 2; }
    r=$(reasons "$m")
    grep -qF -- "$STREAK" <<< "$r" || { echo "$k: полоса пропала из причин отказа: ${r:0:200}"; exit 1; }
    grep -qF -- "$p" <<< "$r" && { echo "$k: стоячий вид назван причиной отказа: ${r:0:200}"; exit 1; }
    bad=$(grep -F -- "$p" <<< "$m" | grep -v 'отказа не держ.*исхода не требуют')
    [ -z "$bad" ] || { echo "$k: стоячий вид назван без слов, что отказа он не держит и исхода не требует: ${bad:0:200}"; exit 1; }
    # Предмет `question` — общий перечень `WHAT` (умолчание `rc_subject_of`; у прочих стоячих предмет свой): вид в нём остаётся.
    [ "$k" != question ] || jq -r 'select(.signal == "question") | .ref' "$W/$k/outcome-$k.jsonl" 2>/dev/null | grep -qF -- "$p" \
        || { echo "$k: предмет повода в журнале исходов потерял вид — общий перечень изменился"; exit 1; }
done
# Два вида с правом и событие: в скобках оба вида с правом, поправка не уехала в строку стоячих.
m=$(mk two streak correction event); r=$(reasons "$m")
[ -n "$m" ] || { echo "рамка: полоса, поправка и событие — отказа нет"; exit 2; }
grep -qF -- "$STREAK" <<< "$r" && grep -qF -- "$CORR" <<< "$r" || { echo "два вида с правом — в скобках не оба: ${r:0:200}"; exit 1; }
grep -F -- "$CORR" <<< "$m" | grep -q 'отказа не держ' && { echo "поправка названа стоячей"; exit 1; }
# Полоса покрыта зачтённой цепочкой, поправка открыта: скобки называют только поправку (M1).
m=$(mk cov streak correction chain-streak); r=$(reasons "$m")
[ -n "$m" ] || { echo "рамка: открытая поправка при покрытой полосе — отказа нет"; exit 2; }
grep -qF -- "$CORR" <<< "$r" || { echo "покрытая полоса: открытая поправка не названа: ${r:0:200}"; exit 1; }
grep -qF -- "$STREAK" <<< "$r" && { echo "покрытая полоса названа причиной отказа: ${r:0:200}"; exit 1; }
echo "стоячий и снятый повод не названы причиной отказа"
exit 0
