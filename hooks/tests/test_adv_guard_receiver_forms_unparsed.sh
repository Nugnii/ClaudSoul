#!/usr/bin/env bash
# test_adv_guard_receiver_forms_unparsed.sh — приёмник, разложенный не строкой вида
# `cp "…" "…"`, для извлекателя не существует: ни пары не требуется, ни о нераспознанной
# строке не сказано.
#
# Вход: копия install.sh, в которую дописаны пять доставок содержимого репозитория внутрь
#   ~/.claude, ни одна не покрыта парой в drift-check:
#     cp -r "$CLAUDSOUL_DIR/domains" "$CLAUDE_HOME/domains"          (флаг -r вместо -R)
#     cp -a "$CLAUDSOUL_DIR/bridges/." "$CLAUDE_HOME/bridges/"       (флаг -a)
#     install -m 755 "$CLAUDSOUL_DIR/bin/x.sh" "$CLAUDE_HOME/agent-bin/x.sh"
#     cat "$CLAUDSOUL_DIR/knowledge/source-tiers.md" > "$CLAUDE_HOME/source-tiers.md"
#     for f in …; do cp "$f" "$CLAUDE_HOME/prompts/$(basename "$f")"; done   (cp не в начале строки)
# Ожидание: либо каждый приёмник назван непокрытым (код 1), либо сказано, что такие-то
#   строки установщика не разобраны. Молчание — дефект: это ровно та щель, ради закрытия
#   которой страж написан («приёмник без пары даёт молчание, неотличимое от OK»).
# Факт: шаблон `^\s*cp (?:-R )?"[^"]+" "([^"]+)"` не совпадает ни с одной из пяти строк.
#   Страж печатает «приёмников install.sh: 7, непокрытых пар: 0» и выходит с 0. Число 7 при
#   этом само неверно — приёмников двенадцать.
#
# Достижимость: в самом install.sh уже есть доставка внутрь ~/.claude не через cp —
#   `echo "$CLAUDSOUL_DIR" > "$REPO_POINTER"` (строка 113, приёмник ~/.claude/claudsoul-repo)
#   и запись settings.json через jq. Извлекатель их не видит по той же причине. Пять форм
#   выше — из привычного словаря установщиков, а не экзотика.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD_SRC="$REPO/hooks/tests/test_drift_pairs_cover_install.sh"
[ -f "$GUARD_SRC" ] || { echo "FAIL: нет $GUARD_SRC"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

T="$(mktemp -d)"
P="$T/repo"
mkdir -p "$P/hooks/tests"
cp "$REPO/install.sh" "$P/install.sh"
cp "$REPO/hooks/tests/drift-check.sh" "$P/hooks/tests/drift-check.sh"
cp "$GUARD_SRC" "$P/hooks/tests/guard.sh"

cat >> "$P/install.sh" <<'INST'

# --- 10. Новые приёмники ---
cp -r "$CLAUDSOUL_DIR/domains" "$CLAUDE_HOME/domains"
cp -a "$CLAUDSOUL_DIR/bridges/." "$CLAUDE_HOME/bridges/"
install -m 755 "$CLAUDSOUL_DIR/bin/x.sh" "$CLAUDE_HOME/agent-bin/x.sh"
cat "$CLAUDSOUL_DIR/knowledge/source-tiers.md" > "$CLAUDE_HOME/source-tiers.md"
for f in "$CLAUDSOUL_DIR"/prompts/*.md; do cp "$f" "$CLAUDE_HOME/prompts/$(basename "$f")"; done
INST

out="$(bash "$P/hooks/tests/guard.sh" 2>&1)"; rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
echo "код возврата стража: $rc"

fail=0
for key in domains bridges agent-bin source-tiers.md prompts; do
    case "$out" in
        *"$key"*) echo "  · $key — назван" ;;
        *) echo "ПРОВАЛ: приёмник ~/.claude/$key не назван ни непокрытым, ни неразобранным"; fail=1 ;;
    esac
done
if [ "$rc" -eq 0 ]; then
    echo "ПРОВАЛ: код возврата 0 при пяти приёмниках без пары"
    fail=1
fi
case "$out" in
    *"приёмников install.sh: 7"*)
        echo "ПРОВАЛ: объявлено «приёмников install.sh: 7», а их 12 — число выведено из того, что шаблон сумел разобрать"
        fail=1 ;;
esac
[ "$fail" -eq 0 ] && echo "OK: приёмник виден стражу либо честно назван неразобранным"
exit "$fail"
