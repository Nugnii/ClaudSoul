#!/usr/bin/env bash
# test_adv_drift_pairs_blind_receivers.sh — АТАКИ на hooks/tests/test_drift_pairs_cover_install.sh.
# СУДИТ: hooks/tests/test_drift_pairs_cover_install.sh
# Объявлено 20 сентября 2026 (D342). Индекс зависимостей связывал этот свидетель с
# `install.sh`, потому что тест кладёт фикстуру с таким именем в свою песочницу —
# прибор выхолащивал НЕ ТОТ файл, и честный свидетель числился ложно-зелёным.
# Предмет установлен по тому, что тест ЗАПУСКАЕТ, а не по упоминанию имени.
#
# Прибор обязан назвать приёмник install.sh, у которого нет пары в drift-check, а строку,
# которую не смог разобрать, — назвать вслух («покрытие по ним неизвестно»). Обе атаки
# дают приёмник, который не попадает НИ в покрытие, НИ в «не разобрано»: страж печатает
# «непокрытых пар: 0» и выходит с нулём.
#
# 1. ФИГУРНЫЕ СКОБКИ. Имена приёмников выводятся регуляркой
#    `^\s*([A-Z_][A-Z0-9_]*)="\$(?:CLAUDE_HOME|HOME/\.claude)[^"]*"` (строка 156) — она
#    требует `$CLAUDE_HOME` БЕЗ скобок. `WIDGETS_TARGET="${CLAUDE_HOME}/widgets"` мимо неё,
#    и приёмника не существует ни для одного из двух проходов. Формы `${HOME}/.claude`
#    файл нормализует (строка 118), а `${CLAUDE_HOME}` — нет: половина признака.
# 2. ЦИКЛ ЧЕРЕЗ ПОДСТАНОВКУ. `SUBST` гасит `$(...)` ДО вывода имён переменных цикла
#    (строки 111 и 133), поэтому `for f in $(find "$CLAUDSOUL_DIR"/widgets -type f)`
#    не даёт LOOP_VAR, а доставка `cp "$f" "$W2/…"` не признаётся идущей из репозитория
#    и молча выбрасывается ОБОИМИ проходами.
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/test_drift_pairs_cover_install.sh"
[ -f "$SRC" ] || { echo "FAIL: нет $SRC"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

TMP=$(mktemp -d) || exit 1
ROOT="$TMP/repo"
mkdir -p "$ROOT/hooks/tests"
cp "$SRC" "$ROOT/hooks/tests/test_drift_pairs_cover_install.sh"

# сверщик-фикстура: сравнивает ТОЛЬКО хуки, пары для widgets у него нет
cat > "$ROOT/hooks/tests/drift-check.sh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
_cmp_tree "хуки" "$REPO/hooks" "$CLAUDE_HOME/hooks" "*.sh"
EOF

_install() {  # $1 — строка объявления приёмника, $2 — строки доставки
    cat > "$ROOT/install.sh" <<EOF
#!/usr/bin/env bash
CLAUDSOUL_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
CLAUDE_HOME="\$HOME/.claude"
HOOKS_TARGET="\$CLAUDE_HOME/hooks"
$1

for hook_script in "\$CLAUDSOUL_DIR"/hooks/*.sh; do
    cp "\$hook_script" "\$HOOKS_TARGET/\$(basename "\$hook_script")"
done
$2
EOF
}

_run() { bash "$ROOT/hooks/tests/test_drift_pairs_cover_install.sh" 2>&1; }

# ── контроль: приёмник без скобок — страж обязан назвать его непокрытым ───────────
_install 'WIDGETS_TARGET="$CLAUDE_HOME/widgets"' \
         'cp "$CLAUDSOUL_DIR/widgets/w.json" "$WIDGETS_TARGET/w.json"'
OUT=$(_run); RC=$?
if [ "$RC" -ne 0 ] && grep -q 'widgets' <<< "$OUT"; then
    ok "контроль: приёмник \$CLAUDE_HOME/widgets назван непокрытым"
else
    bad "контроль: приёмник \$CLAUDE_HOME/widgets назван непокрытым" \
        "код=$RC, вывод: $(printf '%s' "$OUT" | tr '\n' ' ') — фикстура не годится"
fi

# ── АТАКА 1: то же самое, но имя приёмника объявлено в фигурных скобках ───────────
_install 'WIDGETS_TARGET="${CLAUDE_HOME}/widgets"' \
         'cp "$CLAUDSOUL_DIR/widgets/w.json" "$WIDGETS_TARGET/w.json"'
OUT=$(_run); RC=$?
if [ "$RC" -ne 0 ]; then
    ok "фигурные_скобки: приёмник не потерян"
else
    bad "фигурные_скобки: приёмник не потерян" \
        "код=0, вывод: $(printf '%s' "$OUT" | tr '\n' ' ') — ни покрытия, ни «не разобрано»"
fi

# ── АТАКА 2: цикл по подстановке команды ──────────────────────────────────────────
_install 'W2_TARGET="$CLAUDE_HOME/widgets2"' \
         'for w in $(find "$CLAUDSOUL_DIR"/widgets -type f); do
    cp "$w" "$W2_TARGET/$(basename "$w")"
done'
OUT=$(_run); RC=$?
if [ "$RC" -ne 0 ]; then
    ok "цикл_через_подстановку: приёмник не потерян"
else
    bad "цикл_через_подстановку: приёмник не потерян" \
        "код=0, вывод: $(printf '%s' "$OUT" | tr '\n' ' ') — SUBST стёр источник цикла до вывода LOOP_VARS"
fi

echo "drift-pairs-blind-receivers: $PASS ok, $FAIL FAIL"
exit $(( FAIL != 0 ))
