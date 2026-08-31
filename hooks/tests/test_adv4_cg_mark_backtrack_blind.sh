#!/usr/bin/env bash
# test_adv4_cg_mark_backtrack_blind.sh
# АТАКА: completion-gate.sh опознаёт метку пункта регэкспом
#   r'^(?:- |#{2,6} )[^|\n]*(☐|◐|☑|⊘)'
# Жадный [^|\n]* съедает строку до конца и откатывается к ПОСЛЕДНЕЙ метке в строке.
# А backlog-archive.sh берёт ПЕРВУЮ метку (отдельный re.search). Расхождение: если
# заголовок закрытого ☑-пункта упоминает в описании ◐/☐ (а этот проект пишет эти глифы
# в прозе постоянно), completion-gate прочтёт метку как ◐/☐ → сочтёт пункт ОТКРЫТЫМ →
# его же красную «Проверку» НЕ прогонит и промолчит. Рубеж «обратная связь в той же
# сессии» слепнет на настоящем красном закрытии.
#
# Ожидание: красное ☑ D200 названо (как его называет архиватор — второй рубеж).
# Факт:     completion-gate молчит; архиватор тот же пункт красным видит — доказано,
#           что пункт ДЕЙСТВИТЕЛЬНО закрытый и красный, а страж его пропустил.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS/completion-gate.sh"
ARCH="$(cd "$HOOKS/.." && pwd)/scripts/backlog-archive.sh"
TMP=$(mktemp -d)
mkdir -p "$TMP/state"
BL="$TMP/BACKLOG.md"

# Заголовок ☑-пункта содержит ◐ в описании (после метки).
cat > "$BL" <<'EOF'
# BACKLOG

### D200 ☑ закрыто (было ◐, доведено до готового)
**Результат.** заявлено готовым
**Проверка.** `false` → 0
EOF

OUT=$(printf '{"session_id":"adv4","cwd":"/"}' \
      | env CG_BACKLOG="$BL" STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)

# Контроль: архиватор (первая метка = ☑) обязан назвать D200 красным.
ARCH_OUT=$(env BACKLOG_FILE="$BL" BACKLOG_ARCHIVE="$TMP/arch.md" bash "$ARCH" run 2>&1 || true)

RC=0
if grep -q 'D200' <<< "$OUT"; then
    echo "PASS: completion-gate назвал красное ☑ D200 — атака не воспроизведена"
else
    echo "RED [ATTACK]: completion-gate ПРОМОЛЧАЛ на красном ☑ D200 (метка прочтена как ◐/☐)"
    echo "  вывод completion-gate: [$OUT]"
    if grep -q 'D200' <<< "$ARCH_OUT"; then
        echo "  ДОКАЗАТЕЛЬСТВО: архиватор тот же пункт видит красным (значит он ЗАКРЫТ и красен):"
        printf '%s\n' "$ARCH_OUT" | grep 'D200' | sed 's/^/    /'
    fi
    RC=1
fi

echo "temp: $TMP (уберёт система)"
exit "$RC"
