#!/usr/bin/env bash
# test_adv_mechanism_consumer_holes.sh — АТАКИ на hooks/mechanism-has-consumer.sh.
#
# Страж обязан назвать новый файл scripts/, у которого нет ни исполнителя в коде, ни
# строки в реестре замеров. Обе атаки дают вход, при котором сирота проходит МОЛЧА.
#
# 1. СОБСТВЕННЫЙ ТЕСТ СЧИТАЕТСЯ ПОТРЕБИТЕЛЕМ. Область поиска исполнителя — `-- hooks
#    scripts install.sh` (mechanism-has-consumer.sh:66), а `hooks/tests/` лежит внутри
#    `hooks`. Значит строка `python3 "$TMP/scripts/x.py"` из пробы этого же прибора
#    засчитывается вызовом. Это ровно тот случай, ради которого страж написан: его шапка
#    называет `scripts/root-map.py` — «написан с зелёным тестом и коммитом и не подключён
#    ни к чему». Проба у него есть (hooks/tests/test_root_map.sh:52-53 зовут его через
#    `python3`), то есть мотивирующий случай страж бы не поймал.
# 2. РЕЕСТР СВЕРЯЕТСЯ ПОДСТРОКОЙ. `grep -qF "$name" "$REGISTRY"` (строка 71) без границы
#    слова: новый `scripts/status.sh` покрывается строкой про `ci-status.sh`, которая
#    в реестре живёт (scripts/measurements.tsv:… ci-status.sh).
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/mechanism-has-consumer.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

TMP=$(mktemp -d) || exit 1
REPO="$TMP/repo"
mkdir -p "$REPO/scripts" "$REPO/hooks/tests"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email adv@example.com
git -C "$REPO" config user.name adv
git -C "$REPO" config commit.gpgsign false

printf '#!/usr/bin/env bash\necho установщик\n' > "$REPO/install.sh"
printf '# id\tпериод\tкоманда\tчто меряет\nci-red\t7\tbash scripts/ci-status.sh\tисход CI своего коммита\n' \
    > "$REPO/scripts/measurements.tsv"
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -qm base >/dev/null 2>&1

run() {  # запустить хук на git commit в фикстуре
    jq -n --arg c "$REPO" '{tool_name:"Bash", tool_input:{command:"git commit -m правка"}, cwd:$c}' \
        | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# ── положительный контроль: сирота без всего — страж обязан сказать ───────────────
printf '#!/usr/bin/env bash\necho сирота\n' > "$REPO/scripts/lonely.sh"
git -C "$REPO" add scripts/lonely.sh >/dev/null 2>&1
OUT=$(run)
if grep -q 'lonely.sh' <<< "$OUT"; then
    ok "контроль: настоящая сирота названа"
else
    bad "контроль: настоящая сирота названа" "вывод: ${OUT:-<пусто>} — фикстура не годится"
fi
git -C "$REPO" reset -q >/dev/null 2>&1
rm -f "$REPO/scripts/lonely.sh"

# ── АТАКА 1: у сироты есть только собственная проба ───────────────────────────────
cat > "$REPO/hooks/tests/test_orphan_tool.sh" <<'EOF'
#!/usr/bin/env bash
# проба прибора: только запускает его и смотрит вывод
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
run() { python3 "$REPO/scripts/orphan-tool.py" "$@" 2>&1; }
[ -n "$(run --check)" ] || exit 1
EOF
git -C "$REPO" add hooks/tests/test_orphan_tool.sh >/dev/null 2>&1
git -C "$REPO" commit -qm "проба" >/dev/null 2>&1

printf '#!/usr/bin/env python3\nprint("нечего")\n' > "$REPO/scripts/orphan-tool.py"
git -C "$REPO" add scripts/orphan-tool.py >/dev/null 2>&1
OUT=$(run)
if grep -q 'orphan-tool.py' <<< "$OUT"; then
    ok "проба_не_потребитель: сирота с одной лишь пробой названа"
else
    bad "проба_не_потребитель: сирота с одной лишь пробой названа" \
        "вывод: ${OUT:-<пусто>} — вызов из hooks/tests/ засчитан исполнителем (область поиска включает hooks целиком)"
fi
git -C "$REPO" reset -q >/dev/null 2>&1
rm -f "$REPO/scripts/orphan-tool.py"

# ── АТАКА 2: реестр покрывает подстрокой чужого имени ─────────────────────────────
printf '#!/usr/bin/env bash\necho ещё сирота\n' > "$REPO/scripts/status.sh"
git -C "$REPO" add scripts/status.sh >/dev/null 2>&1
OUT=$(run)
if grep -q 'scripts/status.sh' <<< "$OUT"; then
    ok "реестр_подстрокой: status.sh не покрыт строкой про ci-status.sh"
else
    bad "реестр_подстрокой: status.sh не покрыт строкой про ci-status.sh" \
        "вывод: ${OUT:-<пусто>} — grep -qF «status.sh» нашёл его внутри «ci-status.sh»"
fi

echo "mechanism-consumer-holes: $PASS ok, $FAIL FAIL"
exit $(( FAIL != 0 ))
