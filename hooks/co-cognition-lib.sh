#!/usr/bin/env bash
# co-cognition-lib.sh — мост L2↔L7: измерение со-эволюционного знания.
# en: bridge L2<->L7 — co-cognition share and comparison against solo knowledge.
#
# Считает по знаниевому ядру (case-/pattern-/principle-*.md; второй контур
# entity/fact/relation не знание в смысле моста и в знаменатель не входит):
#   - доли origin: co-cognition / trajectory_pivot / solo / без поля;
#   - co_cognition_ratio — доля совместно рождённых (проект моста: «тренд должен расти»,
#     сам тренд считает /knowledge-audit по .audit-history.json — здесь только срез);
#   - средний impact co-cognition против solo — проверка тезиса «совместные глубже»;
#   - топ trigger_for_co_cognition — какие триггеры реально рождают совместное знание.
#
# Значения триггера в живой базе записаны то в кавычках, то без ("contradiction" и
# contradiction) — читатель нормализует, иначе один триггер считался бы двумя.
# Ноль co-cognition — измеренный ноль, не «не измеряли»; «не измеряли» — только
# когда ядро пусто.

# cocog_block [lessons_dir] — markdown-блок для metrics.md.
cocog_block() {
    local dir="${1:-${LESSONS_DIR:-$HOME/.claude/global-lessons}}"
    echo ""
    echo "## Co-cognition health (L2↔L7)"
    # Не через `ls` с тремя глобами: ls возвращает ошибку, если ЛЮБОЙ из них не
    # раскрылся — ядро из одних case-файлов читалось бы как пустое (поймано тестом T7).
    local _any=0 _probe
    for _probe in "$dir"/case-*.md "$dir"/pattern-*.md "$dir"/principle-*.md; do
        [ -f "$_probe" ] && { _any=1; break; }
    done
    if [ "$_any" -eq 0 ]; then
        echo "_Не измеряли: знаниевое ядро пусто ($dir)._"
        return 0
    fi
    # Один проход awk по конкатенации ядра: файлы разделяются маркером FILE:
    # (grep по многим файлам медленнее и путает поля между файлами при -h).
    local agg
    agg=$(
        for f in "$dir"/case-*.md "$dir"/pattern-*.md "$dir"/principle-*.md; do
            [ -f "$f" ] || continue
            echo "FILE:"
            # только frontmatter-поля, тело не читаем
            sed -n '1,60p' "$f" | grep -E '^(origin|impact|trigger_for_co_cognition):' || true
        done | awk '
            # Поля копятся на файл и атрибутируются при СЛЕДУЮЩЕМ FILE: (или в END) —
            # иначе атрибуция зависела бы от порядка полей во frontmatter, а impact
            # файла без origin уезжал бы в корзину предыдущего файла.
            function flush() {
                if (!seen) return
                total++
                o[org]++
                if (org == "co-cognition") {
                    if (imp > 0) { ci += imp; cn2++ }
                    if (trig != "") t[trig]++
                } else if (org == "solo") {
                    if (imp > 0) { si += imp; sn2++ }
                }
            }
            /^FILE:/ { flush(); seen = 1; org = "none"; imp = 0; trig = ""; next }
            /^origin:/ { org = $2; next }
            /^impact:/ { imp = $2 + 0; next }
            /^trigger_for_co_cognition:/ { trig = $2; gsub(/"/, "", trig); next }
            END {
                flush()
                printf "TOTALS %d %d %d %d %d\n", total, o["co-cognition"], o["trajectory_pivot"], o["solo"], total - o["co-cognition"] - o["trajectory_pivot"] - o["solo"]
                if (cn2 > 0) printf "AVGIMP co %d %d\n", ci, cn2
                if (sn2 > 0) printf "AVGIMP solo %d %d\n", si, sn2
                for (k in t) printf "TRIG %s %d\n", k, t[k]
            }
        '
    )
    local total cocog pivot solo nofield
    read -r _ total cocog pivot solo nofield <<EOF
$(printf '%s\n' "$agg" | grep '^TOTALS ')
EOF
    if [ "${total:-0}" -eq 0 ]; then
        echo "_Не измеряли: знаниевое ядро пусто ($dir)._"
        return 0
    fi
    local ratio=$(( cocog * 100 / total ))
    echo "**Ядро:** ${total} (case+pattern+principle) · origin: co-cognition ${cocog}, trajectory_pivot ${pivot}, solo ${solo}, без поля ${nofield}"
    echo "**co_cognition_ratio:** ${ratio}% — проект моста: тренд должен расти (тренд считает /knowledge-audit по истории аудитов)"
    # Средний impact — целая часть и десятая, без float-математики bash
    local ci cn si sn
    read -r _ _ ci cn <<EOF
$(printf '%s\n' "$agg" | grep '^AVGIMP co ' || echo "AVGIMP co 0 0")
EOF
    read -r _ _ si sn <<EOF
$(printf '%s\n' "$agg" | grep '^AVGIMP solo ' || echo "AVGIMP solo 0 0")
EOF
    if [ "${cn:-0}" -gt 0 ] && [ "${sn:-0}" -gt 0 ]; then
        echo "**Средний impact:** co-cognition $(( ci * 10 / cn / 10 )).$(( ci * 10 / cn % 10 )) (n=${cn}) против solo $(( si * 10 / sn / 10 )).$(( si * 10 / sn % 10 )) (n=${sn})"
    fi
    local trigs
    trigs=$(printf '%s\n' "$agg" | awk '/^TRIG /{printf "%s ×%s, ", $2, $3}' | sed 's/, $//')
    [ -n "$trigs" ] && echo "**Триггеры co-cognition:** ${trigs}"
    return 0
}
