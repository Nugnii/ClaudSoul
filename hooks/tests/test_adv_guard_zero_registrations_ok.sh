#!/usr/bin/env bash
# test_adv_guard_zero_registrations_ok.sh — пара «регистрация хуков» печатает OK, сравнив
# ноль записей. Это ровно тот исход, против которого заведён статус BROKEN.
#
# Вход: файлы хуков установлены и побайтово совпадают, а $CLAUDE_HOME/settings.json не
#   содержит ни одной регистрации ClaudSoul: `{"hooks":{}}`, `{}` либо только чужие хуки.
# Ожидание: сравнили ноль — BROKEN (шапка drift-check.sh: «пара, в которой сравнили ноль
#   файлов, — это не «совпадает», а сломанная проверка»). Код возврата 2.
# Факт: python-вставка печатает `0|OK|`, ветка `case` берёт OK, и пара выдаёт
#   `OK|регистрация хуков|0|0|`. Код возврата 0. Число «сравнено» равно нулю, а статус —
#   утвердительный: ни один хук не висит ни на одном событии, и это названо совпадением.
#
# Достижимость: остальные пары в этот момент сравнивают файлы (в тесте — 1 хук и 1
#   библиотека), поэтому run_all.sh идёт не в ветку «установки нет», а в последнюю и
#   печатает «N пар «репозиторий ↔ установленное» совпадают». Состояние достигается любой
#   перезаписью settings.json без раздела hooks — тем самым аддитивным слиянием, ради
#   надзора за которым пара 7 и заведена.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
DRIFT="$REPO/hooks/tests/drift-check.sh"
[ -f "$DRIFT" ] || { echo "FAIL: нет $DRIFT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq      >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

T="$(mktemp -d)"
P="$T/repo"; H="$T/home"
mkdir -p "$P/hooks/lib" "$P/skills/demo" "$P/templates" "$P/scripts" "$P/rules" "$P/lib" "$P/bin"
cp "$REPO/lib/claude-md-merge.sh" "$P/lib/claude-md-merge.sh" 2>/dev/null || { echo "SKIP: нет lib/claude-md-merge.sh"; exit 0; }
cp "$REPO/rules/CLAUDE.md" "$P/rules/CLAUDE.md"
printf 'echo resolve\n' > "$P/bin/resolve.sh"
printf 'print(0)\n' > "$P/scripts/regen-seed.py"
printf 'echo statusline\n' > "$P/scripts/statusline-claudsoul.sh"
printf 'echo hook\n' > "$P/hooks/a.sh"
printf 'echo lib\n'  > "$P/hooks/lib/b.sh"
printf '# demo\n'    > "$P/skills/demo/SKILL.md"
printf 'шаблон\n'    > "$P/templates/CLAUDE.md.tmpl"

cat > "$P/install.sh" <<'INST'
#!/usr/bin/env bash
CLAUDE_HOME="$HOME/.claude"
cp "$D/bin/resolve.sh" "$CLAUDE_HOME/bin/resolve.sh"
HOOKS_CONFIG='{
  "hooks": {
    "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/a.sh" } ] } ]
  }
}'
INST

# установленная сторона: файлы на месте и совпадают, регистраций нет
mkdir -p "$H/hooks/lib" "$H/templates"
cp "$P/hooks/a.sh" "$H/hooks/a.sh"
cp "$P/hooks/lib/b.sh" "$H/hooks/lib/b.sh"
cp "$P/templates/CLAUDE.md.tmpl" "$H/templates/CLAUDE.md.tmpl"

fail=0
for variant in '{"hooks":{}}' '{}' '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"bash /чужое/thing.sh"}]}]}}'; do
    printf '%s\n' "$variant" > "$H/settings.json"
    out="$(CLAUDSOUL_REPO="$P" CLAUDE_HOME="$H" bash "$DRIFT" 2>&1)"; rc=$?
    line="$(printf '%s\n' "$out" | grep '|регистрация хуков|' || true)"
    status="${line%%|*}"
    rest="${line#*|}"; rest="${rest#*|}"; compared="${rest%%|*}"
    echo "settings.json = $variant"
    echo "  строка пары: $line   (код возврата $rc)"
    if [ "$status" = "OK" ] && [ "${compared:-0}" -eq 0 ]; then
        echo "  ПРОВАЛ: сравнили ноль записей, а напечатано OK — статус BROKEN не сработал"
        fail=1
    fi
done
[ "$fail" -eq 0 ] && echo "OK: ноль сравнений не выдаётся за совпадение"
exit "$fail"
