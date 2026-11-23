#!/usr/bin/env bash
# test_colon_lead_in_count.sh — «Проверка результата» colon-lead-in-count.py меряет объявленный результат.
#
# Результат: команда из шапки scripts/colon-lead-in-count.py печатает число реплик с
#            зачином-двоеточием, и число это — счёт по объявленному признаку, а не константа:
#            на подложенных расшифровках с двумя подходящими репликами из четырёх печатается 2,
#            при --verbose названы обе; пустой каталог даёт 0; зачин длиннее порога не считается.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Единственный кандидат в свидетели —
# `test_scripts_reject_unknown_args.sh` — зелен под заглушкой: он проверяет отказ на неизвестный
# флаг, а не счёт. Инструмент читает `~/.claude/projects/*/*.jsonl` без рычага пути, поэтому
# фикстура подкладывается через HOME. Команда БЕРЁТСЯ из шапки инструмента, как в
# test_split_provenance_log.sh.
set -uo pipefail
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/scripts/colon-lead-in-count.py"
[ -f "$TOOL" ] || { echo "FAIL: $TOOL not found"; exit 1; }
CMD=$(awk '/^# Проверка результата:/ { sub(/^# Проверка результата: */, ""); print; exit }' "$TOOL" \
    | sed -E 's/ (даёт 0|—).*//')
case "$CMD" in
    *"$(basename "$0")"*) echo "FAIL: шапка инструмента зовёт сам этот тест — рекурсия"; exit 1 ;;
    *colon-lead-in-count.py*) ;;
    *) echo "FAIL: команда шапки не запускает инструмент: '$CMD'"; exit 1 ;;
esac

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { grep -Fq -- "$2" <<< "$OUT" && ok || bad "$1" "нет строки «$2»"; }
hasnt() { grep -Fq -- "$2" <<< "$OUT" && bad "$1" "лишняя строка «$2»" || ok; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; P="$H/.claude/projects/proj"

# Реплики собеседника: две с зачином (строкой и списком блоков), одна без двоеточия, одна из
# единственной строки, одна с двоеточием В СЕРЕДИНЕ первой строки (признак — «кончается
# двоеточием»; мутант `":" in head` проходил без этой реплики); реплика ассистента — не в счёт.
mk_fixture() {
    rm -rf "$H"; mkdir -p "$P"
    {
        printf '{"type":"user","message":{"role":"user","content":"вот вывод:\\nошибка в строке 3"}}\n'
        printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"лог ниже:\\nстрока лога"}]}}\n'
        printf '{"type":"user","message":{"role":"user","content":"просто текст без зачина\\nвторая строка"}}\n'
        printf '{"type":"user","message":{"role":"user","content":"одна строка с двоеточием:"}}\n'
        printf '{"message":{"role":"assistant","content":"вот:\\nответ"}}\n'
        printf '{"type":"user","message":{"role":"user","content":"Ошибка: вот лог\\nстрока лога"}}\n'
        printf 'не json\n'
    } > "$P/s1.jsonl"
}
run_tool() {   # $@ — флаги инструмента
    OUT=$(cd "$REPO" && HOME="$H" bash -c "$CMD $*" 2>&1); RC=$?
}

# --- T1: счёт по признаку — 2 из 4 ------------------------------------------------------
mk_fixture; run_tool
[ "$RC" -eq 0 ] && ok || bad T1 "rc=$RC — $OUT"
has T1 'реплик с зачином-двоеточием: 2'

# --- T2: --verbose называет найденные и только их --------------------------------------
mk_fixture; run_tool --verbose
has T2 '· вот вывод:'
has T2 '· лог ниже:'
hasnt T2 '· просто текст'
hasnt T2 '· вот:'
hasnt T2 '· Ошибка: вот лог'

# --- T3: пустой каталог — ноль, а не молчание -------------------------------------------
rm -rf "$H"; mkdir -p "$H/.claude/projects"; run_tool
[ "$RC" -eq 0 ] && ok || bad T3 "rc=$RC — $OUT"
has T3 'реплик с зачином-двоеточием: 0'

# --- T4: зачин длиннее порога (80) не считается ------------------------------------------
mk_fixture; long=$(printf 'а%.0s' $(seq 1 85))
printf '{"type":"user","message":{"role":"user","content":"%s:\\nхвост"}}\n' "$long" >> "$P/s1.jsonl"; run_tool
has T4 'реплик с зачином-двоеточием: 2'

echo ""
echo "colon-lead-in-count tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
